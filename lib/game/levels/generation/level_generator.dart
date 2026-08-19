import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'archetype.dart';
import 'candidate_scorer.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'director.dart';
import 'diversity_ledger.dart';
import 'generation_error.dart';
import 'generation_version.dart';
import 'difficulty_parameters.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'level_seed.dart';
import 'metrics.dart';
import 'progression_profile.dart';
import 'motifs.dart';
import 'removal_order.dart';
import '../analytics/generation_analytics.dart';
import '../seeds/seeds.dart';
import 'result.dart';
import 'retrograde_constructor.dart';
import 'sightline_table.dart';
import 'silhouettes.dart';
import 'level_enrichment.dart';
import 'silhouette_session_tracker.dart';
import 'visual_composition.dart';

/// Generates deterministic, deadlock-free puzzle levels.
///
/// ## Pipeline (Phase 3+)
///
/// 1. **Director** picks an archetype (§5), silhouette, difficulty tier and
///    scorer weights for the attempt.
/// 2. **Retrograde Constructor** (or, for Experimental archetype, the legacy
///    greedy path) builds the layout from the empty board outward.
/// 3. **Quality Evaluator** scores the result against §6 bands; up to K=8
///    retries reach for in-band metrics.
/// 4. **Diversity Ledger** rejects fingerprints within Hamming distance 5 of
///    anything in the last-20 emission window.
/// 5. If the K-loop exhausts, the Director's renegotiation (silhouette
///    swap + 10% node-count downscale) gets one more chance per attempt.
///
/// The monotone / strip fallbacks (`_generateFallbackLevel`,
/// `_generateOneDirection`, `_levelDataRowMajorMonotone`, `_levelDataMonotone`)
/// were retired in Phase 3 — the Director Renegotiation now plays that role.
class LevelGenerator {
  final LevelValidator _validator;

  /// Director that picks archetype / silhouette / scorer-weights per attempt.
  final Director _director;

  /// Diversity ledger that gates emissions on the 23-bit fingerprint.
  final DiversityLedger _diversityLedger;

  /// Penalizes consecutive geometric-lattice silhouettes in K-loop ranking.
  final SilhouetteSessionTracker _silhouetteSessionTracker;

  /// When false, the diversity ledger never rejects a candidate (it is still
  /// updated for telemetry). Production callers should leave it at the
  /// default `true`.
  ///
  /// **This does NOT make a shared generator deterministic**, despite what
  /// this comment used to claim. The flag is honoured in exactly one place —
  /// the `isNovel` check in the K-loop — while `_silhouetteSessionTracker`
  /// keeps scoring candidates by `streakPenalty`/`diversityBoost` regardless,
  /// so two `generate(id)` calls on the same instance can still diverge.
  ///
  /// For byte-identity, construct a fresh [LevelGenerator.neutral] per call.
  /// See the T0.0b probes in
  /// `test/game/levels/generation/determinism_contract_test.dart`.
  final bool enableDiversityGating;

  /// Phase 6 §9 — analytics sink. Defaults to a no-op so the
  /// generator stays usable in tests + apps that don't wire telemetry.
  /// Host apps inject their own [GenerationAnalyticsSink] to forward
  /// events to Firebase / Amplitude / their existing collector.
  final GenerationAnalyticsSink analyticsSink;

  // ── Phase-1/2/3 telemetry (used by tests + later by analytics) ────────────
  int _retrogradeAttemptCount = 0;
  int _retrogradeSuccessCount = 0;
  int _retrogradeInBandSuccessCount = 0;
  int _retrogradeOutOfBandSuccessCount = 0;
  int _evaluatorRejectionCount = 0;
  int _diversityRejectionCount = 0;
  int _legacyAttemptCount = 0;
  int _renegotiationCount = 0;
  int _blockingDirCandidatesOffered = 0;
  int _blockingDirCandidatesPicked = 0;
  int _crunchZoneBlockingPicked = 0;
  int _releaseZoneFallbackPicked = 0;
  int _constructionSolvabilityRetries = 0;
  int _winningBlockingRetryIndex0 = 0;
  int _winningBlockingRetryIndex1 = 0;
  int _winningBlockingRetryIndex2 = 0;
  int? _lastWinningBlockingRetryIndex;
  int _maxAttemptsExhaustedCount = 0;
  int _rejectAspectCount = 0;
  int _rejectOccupancyCount = 0;
  int _rejectComponentsCount = 0;
  int _rejectSingletonCount = 0;
  int _rejectBlobVsGridCount = 0;

  // Per-archetype emission counts, used by Phase 3's "distribution matches
  // §5 within ±3%" acceptance test.
  final Map<GenerationArchetype, int> _archetypeEmissionCounts = {
    for (final a in GenerationArchetype.values) a: 0,
  };
  // Phase-4 motif telemetry — drives the "Strong-Motif archetype hits target
  // motif visibility in ≥ 70%" acceptance criterion. We count the strong-motif
  // emissions that successfully shipped *with* at least one motif reservation
  // intact, plus a histogram by motif id for analytics.
  int _strongMotifEmissionCount = 0;
  int _strongMotifEmissionsWithMotifCount = 0;
  final Map<MotifId, int> _motifEmissionCounts = {
    for (final m in MotifId.values) m: 0,
  };
  // Phase 5 — seed-driven emission counter (by seed id).
  final Map<String, int> _seedEmissionCounts = <String, int>{};

  // Phase 6 — staged emission record. Filled inside
  // `_attemptDirectorDrivenGeneration`; committed (= counters incremented +
  // analytics sink fired) or discarded by `generateFromConfiguration` once
  // it knows whether the level actually ships. Keeps every emission counter
  // exactly aligned with shipped levels, regardless of how many retries
  // the outer wave-validation loop burns.
  _PendingDirectorEmission? _pendingEmission;
  // Cached per (gridWidth, gridHeight) — sightline tables are pure-geometry
  // and safe to share across attempts.
  final Map<int, SightlineTable> _sightlineCache = <int, SightlineTable>{};

  LevelGenerator({
    LevelValidator? validator,
    Director? director,
    DiversityLedger? diversityLedger,
    SilhouetteSessionTracker? silhouetteSessionTracker,
    this.enableDiversityGating = true,
    GenerationAnalyticsSink? analyticsSink,
  })  : _validator = validator ?? LevelValidator(),
        _director = director ?? Director(),
        _diversityLedger = diversityLedger ?? DiversityLedger(),
        _silhouetteSessionTracker =
            silhouetteSessionTracker ?? SilhouetteSessionTracker(),
        analyticsSink = analyticsSink ?? noopAnalyticsSink;

  /// Named construction guaranteeing an empty ledger and silhouette
  /// tracker, for tests and reproduction.
  ///
  /// Functionally equivalent to `LevelGenerator()` today, since the default
  /// constructor also creates fresh session state when none is injected. It
  /// exists so byte-identity call sites *declare* that they depend on neutral
  /// state rather than relying on that default staying true.
  factory LevelGenerator.neutral({
    LevelValidator? validator,
    Director? director,
    bool enableDiversityGating = true,
    GenerationAnalyticsSink? analyticsSink,
  }) {
    return LevelGenerator(
      validator: validator,
      director: director,
      diversityLedger: DiversityLedger(),
      silhouetteSessionTracker: SilhouetteSessionTracker(),
      enableDiversityGating: enableDiversityGating,
      analyticsSink: analyticsSink,
    );
  }

  /// Index (0=0.72, 1=0.45, 2=0.25) from the most recent successful retrograde build.
  int? get lastWinningBlockingRetryIndex => _lastWinningBlockingRetryIndex;

  /// Number of times the Director-driven retrograde path was tried.
  int get retrogradeAttemptCount => _retrogradeAttemptCount;

  /// Number of times the retrograde path produced a placement set successfully.
  int get retrogradeSuccessCount => _retrogradeSuccessCount;

  /// Subset of [retrogradeSuccessCount] that also passed the Phase-2
  /// difficulty-profile evaluator on first / best attempt.
  int get retrogradeInBandSuccessCount => _retrogradeInBandSuccessCount;

  /// Subset of [retrogradeSuccessCount] returned after the evaluator's K=8
  /// retries all missed band (we still ship the best/last to keep the
  /// monotone-fallback rate low).
  int get retrogradeOutOfBandSuccessCount => _retrogradeOutOfBandSuccessCount;

  /// Total evaluator rejections (out-of-band Retrograde attempts).
  int get evaluatorRejectionCount => _evaluatorRejectionCount;

  /// Diversity-ledger rejections (candidate too close to recent emissions).
  int get diversityRejectionCount => _diversityRejectionCount;

  /// Number of times the legacy greedy path was tried (Experimental archetype
  /// in Phase 3+).
  int get legacyAttemptCount => _legacyAttemptCount;

  /// Number of Director Renegotiations (silhouette swap / node-count
  /// downscale). Each successful retrograde attempt that needed at least one
  /// renegotiation counts here.
  int get renegotiationCount => _renegotiationCount;

  /// Per-archetype emission counter.
  Map<GenerationArchetype, int> get archetypeEmissionCounts =>
      Map<GenerationArchetype, int>.unmodifiable(_archetypeEmissionCounts);

  /// Total Strong-Motif archetype emissions (Phase 4).
  int get strongMotifEmissionCount => _strongMotifEmissionCount;

  /// Subset of [strongMotifEmissionCount] that shipped with ≥ 1 motif
  /// reservation actually present in the emitted level. Drives §4.6's "70%
  /// motif visibility" acceptance criterion.
  int get strongMotifEmissionsWithMotifCount =>
      _strongMotifEmissionsWithMotifCount;

  /// Per-motif emission counter. `MotifId.none` counts levels that shipped
  /// with zero reservations (Strong-Motif failures + every other archetype).
  Map<MotifId, int> get motifEmissionCounts =>
      Map<MotifId, int>.unmodifiable(_motifEmissionCounts);

  /// Per-[LevelSeed] emission counter (Phase 5). Each successful seeded
  /// emission increments the seed's id; non-seed levels never appear here.
  Map<String, int> get seedEmissionCounts =>
      Map<String, int>.unmodifiable(_seedEmissionCounts);

  /// Phase 6 §9 — returns a cumulative session snapshot suitable for the
  /// weekly QA-by-archetype report (the host app calls this every N levels
  /// and forwards the result to its sink).
  GenerationSessionSnapshot snapshotSession() {
    return GenerationSessionSnapshot(
      retrogradeAttempts: _retrogradeAttemptCount,
      retrogradeInBandSuccesses: _retrogradeInBandSuccessCount,
      retrogradeOutOfBandSuccesses: _retrogradeOutOfBandSuccessCount,
      evaluatorRejections: _evaluatorRejectionCount,
      diversityRejections: _diversityRejectionCount,
      legacyAttempts: _legacyAttemptCount,
      renegotiations: _renegotiationCount,
      archetypeEmissions:
          Map<GenerationArchetype, int>.from(_archetypeEmissionCounts),
      seedEmissions: Map<String, int>.from(_seedEmissionCounts),
      strongMotifEmissions: _strongMotifEmissionCount,
      strongMotifEmissionsWithMotif: _strongMotifEmissionsWithMotifCount,
      blockingDirCandidatesOffered: _blockingDirCandidatesOffered,
      blockingDirCandidatesPicked: _blockingDirCandidatesPicked,
      crunchZoneBlockingPicked: _crunchZoneBlockingPicked,
      releaseZoneFallbackPicked: _releaseZoneFallbackPicked,
      constructionSolvabilityRetries: _constructionSolvabilityRetries,
      winningBlockingRetryIndex0: _winningBlockingRetryIndex0,
      winningBlockingRetryIndex1: _winningBlockingRetryIndex1,
      winningBlockingRetryIndex2: _winningBlockingRetryIndex2,
      maxAttemptsExhaustedCount: _maxAttemptsExhaustedCount,
      rejectAspectCount: _rejectAspectCount,
      rejectOccupancyCount: _rejectOccupancyCount,
      rejectComponentsCount: _rejectComponentsCount,
      rejectSingletonCount: _rejectSingletonCount,
      rejectBlobVsGridCount: _rejectBlobVsGridCount,
    );
  }

  /// Shared diversity ledger. Exposed read-only for tests.
  DiversityLedger get diversityLedger => _diversityLedger;

  /// Resets all internal counters; useful between test runs.
  void resetCounters() {
    _retrogradeAttemptCount = 0;
    _retrogradeSuccessCount = 0;
    _retrogradeInBandSuccessCount = 0;
    _retrogradeOutOfBandSuccessCount = 0;
    _evaluatorRejectionCount = 0;
    _diversityRejectionCount = 0;
    _legacyAttemptCount = 0;
    _renegotiationCount = 0;
    _blockingDirCandidatesOffered = 0;
    _blockingDirCandidatesPicked = 0;
    _crunchZoneBlockingPicked = 0;
    _releaseZoneFallbackPicked = 0;
    _constructionSolvabilityRetries = 0;
    _winningBlockingRetryIndex0 = 0;
    _winningBlockingRetryIndex1 = 0;
    _winningBlockingRetryIndex2 = 0;
    _maxAttemptsExhaustedCount = 0;
    _rejectAspectCount = 0;
    _rejectOccupancyCount = 0;
    _rejectComponentsCount = 0;
    _rejectSingletonCount = 0;
    _rejectBlobVsGridCount = 0;
    for (final a in GenerationArchetype.values) {
      _archetypeEmissionCounts[a] = 0;
    }
    _strongMotifEmissionCount = 0;
    _strongMotifEmissionsWithMotifCount = 0;
    for (final m in MotifId.values) {
      _motifEmissionCounts[m] = 0;
    }
    _seedEmissionCounts.clear();
  }

  void _incrementVisualRejectCounter(VisualCompositionRejectReason? reason) {
    if (reason == null) return;
    switch (reason) {
      case VisualCompositionRejectReason.aspect:
        _rejectAspectCount++;
        break;
      case VisualCompositionRejectReason.occupancy:
        _rejectOccupancyCount++;
        break;
      case VisualCompositionRejectReason.components:
        _rejectComponentsCount++;
        break;
      case VisualCompositionRejectReason.singleton:
        _rejectSingletonCount++;
        break;
      case VisualCompositionRejectReason.blobVsGrid:
        _rejectBlobVsGridCount++;
        break;
    }
  }

  /// Effective inclusive bounds on [LevelSolver.countRemovalWaves].
  static (int min, int max) removalWaveBounds(
    DifficultyParameters d,
    int nodeCount,
  ) {
    if (nodeCount <= 0) return (0, 0);
    var minW = d.minChainLength;
    final maxW = min(d.maxChainLength, nodeCount);
    if (d.mode == DifficultyMode.hard) {
      if (nodeCount <= 18) {
        minW = min(minW, 2);
      } else if (nodeCount <= 35) {
        minW = min(minW, 3);
      } else {
        // Dense hard boards may still clear in relatively few waves; keep lower
        // bound compatible with solver-compatible outputs.
        minW = min(minW, 3);
      }
    }
    minW = min(minW, maxW);
    if (minW < 1) minW = 1;
    return (minW, maxW);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────

  /// Generates a deterministic [LevelData] for the given [levelId].
  ///
  /// Checks for milestone levels first, then falls back to the normal
  /// backward-generation loop with archetype-driven shape/bias selection.
  Result<LevelData, GenerationError> generate(
    int levelId, {
    DifficultyMode? mode,
    Duration? timeBudget,
  }) {
    final config = LevelConfiguration.fromLevelId(levelId, mode: mode);
    return generateFromConfiguration(
      config,
      primarySeed: levelId,
      applyMilestones: true,
      timeBudget: timeBudget,
    );
  }

  /// Deterministic [LevelData] from an explicit [config] (daily puzzles, tests).
  ///
  /// [primarySeed] drives RNG streams; it should differ per puzzle when
  /// [config.levelId] is reused. [applyMilestones] is off for dailies so
  /// campaign milestone layouts never hijack the date key. [targetTier], when
  /// non-null, lets daily / special callers ask the Phase-2 evaluator to use
  /// the Expert band even though the underlying [config] is Medium.
  Result<LevelData, GenerationError> generateFromConfiguration(
    LevelConfiguration config, {
    required int primarySeed,
    bool applyMilestones = true,
    int maxAttempts = 40,
    DifficultyTier? targetTier,
    Duration? timeBudget,
    bool allowMechanicShortFallback = false,
  }) {
    // T0.0c: fold generationVersion into seed derivation (identity at v1)
    if (kGenerationVersion > 1) {
      primarySeed = primarySeed ^ ((kGenerationVersion - 1) * 73856093);
    }

    final validation = config.validate();
    if (!validation.isValid) {
      return Result.error(
        GenerationError.invalidConfiguration(validation.message),
      );
    }

    final resolvedTargetTier =
        targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    final useOpeningSeeds = config.difficulty.mode != DifficultyMode.hard &&
        resolvedTargetTier != DifficultyTier.expert;

    // ── Phase 5: seed-driven path ───────────────────────────────────
    // Hand-authored seeds (opening levels, milestones such as Ring) bypass
    // the random Director sampling. The constructor, evaluator, and
    // diversity ledger still run; only the *style* knobs are pinned.
    if (applyMilestones) {
      final opening = useOpeningSeeds ? seedRegistry[config.levelId] : null;
      final seed = opening ??
          showcaseSeedFor(config.levelId) ??
          milestoneSeedFor(config);
      if (seed != null) {
        var seedConfig = config;
        if (seed.gridWidth != null || seed.gridHeight != null) {
          seedConfig = LevelConfiguration(
            levelId: config.levelId,
            gridWidth: seed.gridWidth ?? config.gridWidth,
            gridHeight: seed.gridHeight ?? config.gridHeight,
            // Use the seed's pinned count when it has one: the Director reads
            // `seed.targetNodeCount`, so leaving the base config's count here
            // leaves the two disagreeing, and the evaluator then rejects every
            // candidate — burning all maxAttempts on a board it was never
            // going to accept.
            targetNodeCount: seed.targetNodeCount ?? config.targetNodeCount,
            difficulty: config.difficulty,
            archetype: config.archetype,
            directionBias: config.directionBias,
            irregularMaskProbability: config.irregularMaskProbability,
            irregularLayoutExtraTries: config.irregularLayoutExtraTries,
            minimumTargetNodeCount: config.minimumTargetNodeCount,
          );
          final validation = seedConfig.validate();
          if (!validation.isValid) {
            return Result.error(
                GenerationError.invalidConfiguration(validation.message));
          }
        }
        final seedSalt = seed.seedRng ?? 0;
        for (int i = 0; i < maxAttempts; i++) {
          final rng = Random(primarySeed * 31337 + seedSalt + i);
          final seedResult = _attemptDirectorDrivenGeneration(
            seedConfig,
            rng,
            targetTier: targetTier,
            seed: seed,
          );
          if (seedResult.isSuccess) {
            final enriched = _enrichLevel(
                seedResult.value, seedConfig, targetTier,
                mechanicOverride: seed.mechanicOverride);
            final validationResult = _validator.validate(enriched);
            if (validationResult.isValid) {
              final budget = budgetForLevel(
                levelId: seedConfig.levelId,
                mode: seedConfig.difficulty.mode,
                mechanicOverride: seed.mechanicOverride,
              );
              final lockCount =
                  enriched.nodes.where((n) => n.kind == NodeKind.locked).length;
              final relayCount =
                  enriched.nodes.where((n) => n.kind == NodeKind.relay).length;
              if (lockCount < budget.lockCount ||
                  relayCount < budget.relayCount) {
                _discardPendingEmission();
                continue;
              }

              _seedEmissionCounts[seed.id] =
                  (_seedEmissionCounts[seed.id] ?? 0) + 1;
              _assertGeneratedLayout(enriched);
              _commitPendingEmission();
              return Result.success(enriched);
            }
          }
        }
        // Seed path failed (e.g. silhouette starvation on a tiny grid):
        // fall through to the regular pipeline so the level still ships.
        _discardPendingEmission();
      }
    }

    // Sample the archetype once for the entire generation process to prevent selection bias
    final lockedArchetype = GenerationArchetypeSpec.sampleForTier(
      Random(primarySeed * 31337),
      resolvedTargetTier,
    );

    // ── Normal generation with retries ────────────────────────────────
    // Optional latency budget: levels are generated at load, and a small tail
    // of seeds burn all [maxAttempts] chasing the ideal removal-wave band
    // (~1s worst case). When [timeBudget] is set, once we're over budget we
    // ship the best fully-validated level found so far, relaxing only the
    // wave-band *preference* — solvability/layout are still enforced. Off by
    // default → behaviour is byte-identical for the generation test suites.
    //
    // NOTE: this clock deliberately does NOT cover the seeded path above. That
    // path is unbounded, and a seed with a high pinned node count can send it
    // into a multi-minute search (see milestone_seeds.dart). Extending this
    // watch to cover it was tried and regressed deadlock_test — the regular
    // pipeline then starts already over budget and exhausts its attempts.
    // Bounding the seeded path needs a deadline inside the Director, not a
    // shared stopwatch here.
    final budgetWatch = timeBudget != null ? (Stopwatch()..start()) : null;
    /// Valid + solvable, but missed the ideal removal-wave band.
    LevelData? budgetFallback;
    /// Valid + solvable, but short of the level's lock/relay budget. Strictly
    /// worse than [budgetFallback], so only shipped when nothing else exists.
    LevelData? mechanicShortFallback;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final overBudgetNow =
          budgetWatch != null && budgetWatch.elapsed >= timeBudget!;
      final overBudgetShippable = budgetFallback ?? mechanicShortFallback;
      if (overBudgetNow && overBudgetShippable != null) {
        _discardPendingEmission();
        return Result.success(overBudgetShippable);
      }
      // Once over budget, fast-forward to the most-relaxed regime (low node
      // count, clean archetype) so the attempt *constructs* quickly — the
      // in-iteration budget escape below then ships the first valid level.
      // This bounds the silhouette-starved tail that otherwise burns every
      // attempt at full node count before succeeding.
      final regimeAttempt =
          overBudgetNow ? max(attempt, maxAttempts - 4) : attempt;
      final rng = Random(primarySeed * 31337 + attempt * 999983);

      final nodeCountScale = 1.0 - (regimeAttempt ~/ 2) * 0.15;
      final scaledConfig = regimeAttempt < 2
          ? config
          : () {
              var scaledTarget =
                  (config.targetNodeCount * nodeCountScale).round().clamp(
                        config.difficulty.minNodes,
                        config.targetNodeCount,
                      );
              final minFloor = config.minimumTargetNodeCount;
              if (minFloor != null && scaledTarget < minFloor) {
                scaledTarget = minFloor;
              }
              return LevelConfiguration(
                levelId: config.levelId,
                gridWidth: config.gridWidth,
                gridHeight: config.gridHeight,
                targetNodeCount: scaledTarget,
                difficulty: config.difficulty,
                archetype: config.archetype,
                directionBias: config.directionBias,
                irregularMaskProbability: config.irregularMaskProbability,
                irregularLayoutExtraTries: config.irregularLayoutExtraTries,
                minimumTargetNodeCount: config.minimumTargetNodeCount,
              );
            }();

      final currentArchetype = regimeAttempt < maxAttempts - 10
          ? lockedArchetype
          : GenerationArchetype.cleanAuthored;

      final result = _attemptGeneration(
        scaledConfig,
        rng,
        targetTier: targetTier,
        overrideArchetype: currentArchetype,
        overBudget: budgetWatch == null
            ? null
            : () => budgetWatch.elapsed >= timeBudget!,
      );
      if (result.isSuccess) {
        final enriched = _enrichLevel(result.value, scaledConfig, targetTier);
        final validationResult = _validator.validate(enriched);
        if (!validationResult.isValid) {
          _discardPendingEmission();
          continue;
        }

        final budget =
            budgetFor(levelId: config.levelId, mode: config.difficulty.mode);
        final lockCount =
            enriched.nodes.where((n) => n.kind == NodeKind.locked).length;
        final relayCount =
            enriched.nodes.where((n) => n.kind == NodeKind.relay).length;
        if (lockCount < budget.lockCount || relayCount < budget.relayCount) {
          // Mechanic-budget shortfall. Retrying is right when there is time,
          // but this is also the branch that made [timeBudget] powerless on
          // the Daily path: once over budget the retry regime scales the node
          // count *down*, which makes a lock/relay shortfall *more* likely, so
          // a starved date key kept landing here and burned all
          // [maxAttempts] no matter how much wall clock had elapsed (measured:
          // 5.0 s against a 400 ms budget on 2026-08-19). Retain the board as
          // a last-resort fallback so the escape at the top of the loop has
          // something valid to ship. Ranked below [budgetFallback]: a
          // wave-band miss is a better level than a mechanic-short one.
          //
          // Opt-in per caller, because it is **not** free. Campaign Hard has a
          // gen p75 of ~190 ms against a 200 ms budget, so a large share of
          // levels brush the budget; enabling this there cost 12 of 100 Hard
          // levels their locked nodes and their silhouette mask, and broke the
          // L150 milestone emission. Only Daily — where the alternative was a
          // 40-attempt burn — opts in.
          if (budgetWatch != null && allowMechanicShortFallback) {
            mechanicShortFallback ??= enriched;
          }
          _discardPendingEmission();
          continue;
        }

        // Over budget: ship this freshly-staged valid level immediately
        // (commits its telemetry + ledger record), skipping the wave-band
        // preference. Bounds worst-case generation latency.
        if (budgetWatch != null && budgetWatch.elapsed >= timeBudget!) {
          _assertGeneratedLayout(enriched);
          _commitPendingEmission();
          return Result.success(enriched);
        }

        final waves = LevelSolver.countRemovalWaves(enriched);
        final (wMin0, wMax0) =
            removalWaveBounds(scaledConfig.difficulty, enriched.nodes.length);
        var wMin = wMin0;
        var wMax = wMax0;
        if (attempt >= maxAttempts ~/ 2) {
          wMin = max(1, wMin0 - 1);
          wMax = min(enriched.nodes.length, wMax0 + 4);
        }
        if (attempt >= maxAttempts - 4) {
          wMin = max(1, wMin0 - 2);
          wMax = min(enriched.nodes.length, wMax0 + 10);
        }
        if (waves >= wMin && waves <= wMax) {
          _assertGeneratedLayout(enriched);
          _commitPendingEmission();
          return Result.success(enriched);
        }
        // Out-of-band wave count — retain as a budget fallback (valid +
        // solvable, just not in the ideal wave band) before dropping the
        // staged event so the next attempt can stage afresh.
        budgetFallback ??= enriched;
        _discardPendingEmission();
      }
    }

    // Phase 3: no monotone fallback any more. The Director Renegotiation
    // already had its chances above. Surface a typed error so callers can
    // pick a sensible response (re-roll a new seed, prompt for a different
    // mode, etc.) instead of the old "always emit something" behaviour.
    _discardPendingEmission();
    _maxAttemptsExhaustedCount++;
    return Result.error(
      GenerationError.noValidDirections(
        'Director exhausted $maxAttempts attempts; no in-band level '
        'produced',
      ),
    );
  }

  /// Same puzzle for every player on a given local calendar day.
  ///
  /// Builds on [LevelConfiguration.forDailyChallenge] (medium grid + baseline
  /// density + irregular-mask bias). Milestones stay off for date keys.
  /// The Phase-2 evaluator targets the Expert band for Daily.
  /// [timeBudget] bounds the search the same way the campaign path is bounded;
  /// `null` leaves it **fully unbounded** (40 attempts × 8 K × 4 renegotiations),
  /// which is what produced the 5.5 s outlier on 2026-08-19. Production passes
  /// `LevelManager.dailyGenerationBudget`; the generation test suites leave it
  /// null so their results stay byte-identical.
  Result<LevelData, GenerationError> generateDailyChallenge(
    int dayKey, {
    Duration? timeBudget,
  }) {
    final config = LevelConfiguration.forDailyChallenge(dayKey);
    return generateFromConfiguration(
      config,
      primarySeed: dayKey,
      applyMilestones: false,
      maxAttempts: 40,
      targetTier: DifficultyTier.expert,
      timeBudget: timeBudget,
      // Daily is the path where a mechanic-budget shortfall used to burn all 40
      // attempts regardless of the clock; campaign deliberately keeps retrying.
      allowMechanicShortFallback: true,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Core backward-generation
  // ────────────────────────────────────────────────────────────────────────

  /// Single generation attempt — Phase-3+ Director-driven path.
  ///
  /// The legacy direct entrypoint was retired alongside the monotone
  /// fallback. The Experimental archetype still delegates to a tightly
  /// scoped greedy variant ([`_attemptLegacyWithSilhouette`]) for §5's
  /// "happy accidents" property.
  Result<LevelData, GenerationError> _attemptGeneration(
    LevelConfiguration config,
    Random random, {
    DifficultyTier? targetTier,
    GenerationArchetype? overrideArchetype,
    bool Function()? overBudget,
  }) {
    return _attemptDirectorDrivenGeneration(
      config,
      random,
      targetTier: targetTier,
      overrideArchetype: overrideArchetype,
      overBudget: overBudget,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Phase 1 — Retrograde Constructor path
  // Phase 2 — Quality-Evaluator retry loop (up to [_evaluatorRetryBudget]
  //           tries against [DifficultyProfile.passes]).
  // Phase 3 — Director chooses archetype/silhouette/weights; Diversity
  //           Ledger gates emissions; Director Renegotiation handles
  //           silhouette starvation.
  // ────────────────────────────────────────────────────────────────────────

  /// §9 Phase 2 K = 8.
  static const int _evaluatorRetryBudget = 8;

  Result<LevelData, GenerationError> _attemptDirectorDrivenGeneration(
    LevelConfiguration config,
    Random random, {
    DifficultyTier? targetTier,
    LevelSeed? seed,
    GenerationArchetype? overrideArchetype,
    bool Function()? overBudget,
  }) {
    _retrogradeAttemptCount++;

    // Track two kinds of "second-best": (a) novel out-of-band candidates
    // that we know are safe to record in the ledger, and (b) non-novel
    // candidates we hold as a last-resort to avoid returning an error.
    Result<LevelData, GenerationError>? novelOutOfBand;
    LevelFingerprint? novelOutOfBandFp;
    LevelMetrics? novelOutOfBandMetrics;
    GenerationPlan? novelOutOfBandPlan;
    int novelOutOfBandRenegotiations = 0;
    ConstructionTelemetry? novelOutOfBandTelemetry;
    Result<LevelData, GenerationError>? nonNovelFallback;
    LevelMetrics? nonNovelMetrics;
    LevelFingerprint? nonNovelFp;
    GenerationPlan? nonNovelPlan;
    int nonNovelRenegotiations = 0;
    ConstructionTelemetry nonNovelTelemetry = ConstructionTelemetry.zero;
    final inBandCandidates = <_InBandCandidate>[];

    final evaluatorTier =
        targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    final evaluatorProfile = DifficultyProfile.forTier(evaluatorTier);
    final cudFloor = evaluatorProfile.criticalUnlockDepth.min;

    // Lock the archetype choice for this outer candidate generation wave to prevent selection bias
    final lockedArchetype = overrideArchetype ??
        (seed == null
            ? GenerationArchetypeSpec.sampleForTier(random, evaluatorTier)
            : null);

    for (var k = 0; k < _evaluatorRetryBudget; k++) {
      // Latency budget: once over budget, stop spending evaluator iterations
      // as soon as we have *something* shippable this attempt — the selection
      // block below returns the best candidate found.
      if (overBudget != null &&
          overBudget() &&
          (inBandCandidates.isNotEmpty ||
              novelOutOfBand != null ||
              nonNovelFallback != null)) {
        break;
      }
      // Derive a per-iteration RNG so successive retries diverge
      // deterministically without consuming unbounded state from `random`.
      final iterationRandom = Random(random.nextInt(0x7fffffff));
      var plan = seed != null
          ? _director.choosePlanFromSeed(seed, config, iterationRandom)
          : _director.choosePlan(
              config,
              iterationRandom,
              overrideTier: targetTier,
              overrideArchetype: lockedArchetype,
            );

      Result<LevelData, GenerationError>? once;
      ConstructionTelemetry? runTelemetry;
      var renegotiationsForThisAttempt = 0;
      for (var r = 0; r <= _director.maxRenegotiations; r++) {
        final run = _runPlannedOnceWithTelemetry(
          plan,
          config,
          iterationRandom,
          targetTier: evaluatorTier,
        );
        once = run.result;
        runTelemetry = run.telemetry;
        if (once.isSuccess) break;
        // Over budget: stop renegotiating (each renegotiation re-runs the full
        // construction) — take what this iteration produced and move on.
        if (overBudget != null && overBudget()) break;
        final greedyFailed = _legacyGreedyFailure(once, plan);
        final renegotiated = greedyFailed
            ? _director.renegotiateAfterGreedyFailure(
                plan, config, iterationRandom)
            : _director.renegotiate(plan, config, iterationRandom);
        if (renegotiated == null) break;
        _renegotiationCount++;
        renegotiationsForThisAttempt++;
        plan = renegotiated;
      }
      if (once == null || once.isError) continue;

      final level = once.value;
      final metrics = LevelMetrics.compute(level);
      if (!DifficultyProfile.passesFsrCap(metrics)) {
        _evaluatorRejectionCount++;
        continue;
      }

      final visual = evaluateVisualComposition(level, evaluatorTier);
      if (!visual.passes) {
        _evaluatorRejectionCount++;
        _incrementVisualRejectCounter(visual.reason);
        continue;
      }

      final inBand = evaluatorProfile.passes(metrics) && visual.passes;
      if (!inBand) {
        _evaluatorRejectionCount++;
        if (metrics.criticalUnlockDepth < cudFloor) {
          continue;
        }
      }

      final visible = _visibleMotifsIn(plan, level);
      final dominantMotif = visible.isEmpty ? MotifId.none : visible.first;
      final fingerprint = computeLevelFingerprint(
        level: level,
        metrics: metrics,
        silhouette: plan.silhouette,
        dominantMotifId: motifIdFingerprintSlot(dominantMotif),
      );
      final novel =
          !enableDiversityGating || _diversityLedger.isNovel(fingerprint);
      if (!novel) {
        _diversityRejectionCount++;
        nonNovelFallback ??= once;
        nonNovelPlan ??= plan;
        nonNovelMetrics ??= metrics;
        nonNovelFp ??= fingerprint;
        nonNovelRenegotiations = renegotiationsForThisAttempt;
        nonNovelTelemetry = runTelemetry ?? ConstructionTelemetry.zero;
        continue;
      }

      if (inBand) {
        inBandCandidates.add(_InBandCandidate(
          result: once,
          plan: plan,
          metrics: metrics,
          fingerprint: fingerprint,
          visibleMotifs: visible,
          renegotiations: renegotiationsForThisAttempt,
          constructionTelemetry: runTelemetry ?? ConstructionTelemetry.zero,
        ));
        continue;
      }
      novelOutOfBand ??= once;
      novelOutOfBandFp ??= fingerprint;
      novelOutOfBandMetrics ??= metrics;
      novelOutOfBandPlan ??= plan;
      novelOutOfBandRenegotiations = renegotiationsForThisAttempt;
      novelOutOfBandTelemetry ??= runTelemetry ?? ConstructionTelemetry.zero;
    }

    if (inBandCandidates.isNotEmpty) {
      final best = _selectBestInBandCandidate(
        inBandCandidates,
        evaluatorTier,
      );
      if (_isHardExpertTier(evaluatorTier)) {
        _guardHardExpertOpening(
          best.metrics,
          context: 'in-band Hard/Expert emission',
        );
      }
      _retrogradeInBandSuccessCount++;
      _retrogradeSuccessCount++;
      _diversityLedger.record(best.fingerprint);
      _recordEmissionTelemetry(
        config: config,
        plan: best.plan,
        level: best.result.value,
        metrics: best.metrics,
        fingerprint: best.fingerprint,
        inBand: true,
        novel: true,
        seed: seed,
        renegotiations: best.renegotiations,
        visibleMotifs: best.visibleMotifs,
        construction: best.constructionTelemetry,
      );
      return best.result;
    }

    // Hard/Expert: discard novel OOB candidates that violate the opening ceiling.
    if (novelOutOfBand != null &&
        _isHardExpertTier(evaluatorTier) &&
        !_openingWithinHardExpertBand(novelOutOfBandMetrics!)) {
      novelOutOfBand = null;
    }

    // Ship best novel out-of-band when the K-loop found no in-band candidate.
    // Hard/Expert may still ship here when opening is within [3,11] but other
    // metrics missed band — the opening ceiling is the hard guard.
    if (novelOutOfBand != null) {
      if (_isHardExpertTier(evaluatorTier)) {
        _guardHardExpertOpening(
          novelOutOfBandMetrics!,
          context: 'metrics-OOB Hard/Expert emission',
        );
      }
      _retrogradeOutOfBandSuccessCount++;
      _retrogradeSuccessCount++;
      _diversityLedger.record(novelOutOfBandFp!);
      _recordEmissionTelemetry(
        config: config,
        plan: novelOutOfBandPlan!,
        level: novelOutOfBand.value,
        metrics: novelOutOfBandMetrics!,
        fingerprint: novelOutOfBandFp,
        inBand: false,
        novel: true,
        seed: seed,
        renegotiations: novelOutOfBandRenegotiations,
        construction: novelOutOfBandTelemetry ?? ConstructionTelemetry.zero,
      );
      return novelOutOfBand;
    }
    // Last resort: emit a non-novel candidate WITHOUT recording it in the
    // ledger. This keeps the window's "all pairs distance ≥ 5" invariant
    // intact (the cost is that the very next emission can be close to
    // this one, which we accept over crashing the caller).
    if (nonNovelFallback != null) {
      if (_isHardExpertTier(evaluatorTier) &&
          !_openingWithinHardExpertBand(nonNovelMetrics!)) {
        nonNovelFallback = null;
      }
    }
    if (nonNovelFallback != null) {
      if (_isHardExpertTier(evaluatorTier)) {
        _guardHardExpertOpening(
          nonNovelMetrics!,
          context: 'non-novel Hard/Expert emission',
        );
      }
      _retrogradeOutOfBandSuccessCount++;
      _retrogradeSuccessCount++;
      _diversityLedger.record(nonNovelFp!);
      _recordEmissionTelemetry(
        config: config,
        plan: nonNovelPlan!,
        level: nonNovelFallback.value,
        metrics: nonNovelMetrics!,
        fingerprint: nonNovelFp,
        inBand: false,
        novel: false,
        seed: seed,
        renegotiations: nonNovelRenegotiations,
        construction: nonNovelTelemetry,
      );
      return nonNovelFallback;
    }
    return Result.error(
      GenerationError.noValidDirections(
        'Director exhausted retries; no candidate produced',
      ),
    );
  }

  /// Stages an emission record. Counters + analytics fire only when the
  /// outer caller commits via [_commitPendingEmission].
  void _recordEmissionTelemetry({
    required LevelConfiguration config,
    required GenerationPlan plan,
    required LevelData level,
    required LevelMetrics metrics,
    required LevelFingerprint fingerprint,
    required bool inBand,
    required bool novel,
    required LevelSeed? seed,
    required int renegotiations,
    String recipeId = 'neutral',
    List<MotifId> visibleMotifs = const [],
    ConstructionTelemetry construction = ConstructionTelemetry.zero,
  }) {
    final visible = visibleMotifs.isNotEmpty
        ? visibleMotifs
        : _visibleMotifsIn(plan, level);
    final topology = LevelTopologyMetrics.compute(level);
    final pathsCapped = metrics.viablePathCount >= 0
        ? metrics.viablePathCountCapped
        : LevelMetrics.compute(level, includeViablePath: true)
            .viablePathCountCapped;
    _pendingEmission = _PendingDirectorEmission(
      plan: plan,
      visibleMotifs: visible,
      construction: construction,
      event: buildEmissionEvent(
        level: level,
        contentIdentity: contentIdentityFor(
          levelId: level.levelId,
          mode: config.difficulty.mode,
          recipeId: recipeId,
        ),
        archetype: plan.archetype,
        silhouette: plan.silhouette,
        seed: seed,
        inBand: inBand,
        novelFingerprint: novel,
        metrics: metrics,
        fingerprint: fingerprint,
        renegotiations: renegotiations,
        visibleMotifs: visible,
        construction: construction,
        chainDepthMax: topology.chainDepthMax,
        maxHubInDegree: topology.maxHubInDegree,
        avgUnlockFanout: topology.avgUnlockFanout,
        pathsCapped: pathsCapped,
      ),
    );
  }

  _InBandCandidate _selectBestInBandCandidate(
    List<_InBandCandidate> candidates,
    DifficultyTier tier,
  ) {
    candidates.sort((a, b) => _compareInBandCandidates(a, b, tier));

    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      for (var i = 0; i < candidates.length && i < 5; i++) {
        final c = candidates[i];
        final withPaths = LevelMetrics.compute(
          c.result.value,
          includeViablePath: true,
        );
        final paths = withPaths.viablePathCount;
        if (paths >= 2 && paths <= 8 && !withPaths.viablePathCountCapped) {
          return _InBandCandidate(
            result: c.result,
            plan: c.plan,
            metrics: withPaths,
            fingerprint: c.fingerprint,
            visibleMotifs: c.visibleMotifs,
            renegotiations: c.renegotiations,
            constructionTelemetry: c.constructionTelemetry,
          );
        }
      }
    }
    return candidates.first;
  }

  int _compareInBandCandidates(
    _InBandCandidate a,
    _InBandCandidate b,
    DifficultyTier tier,
  ) {
    final silhouetteScore =
        _silhouetteRankingScore(b).compareTo(_silhouetteRankingScore(a));
    if (silhouetteScore != 0) return silhouetteScore;

    final profile = DifficultyProfile.forTier(tier);
    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      final w0 = b.metrics.waveZeroWidth.compareTo(a.metrics.waveZeroWidth);
      if (w0 != 0) return w0;
    }

    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      final arcA = profile.temporalArcScore(a.metrics.tempoProfile);
      final arcB = profile.temporalArcScore(b.metrics.tempoProfile);
      final arc = arcB.compareTo(arcA);
      if (arc != 0) return arc;

      final cud = b.metrics.criticalUnlockDepth
          .compareTo(a.metrics.criticalUnlockDepth);
      if (cud != 0) return cud;

      final topoA = profile.topologySoftScoreFromMetrics(a.metrics);
      final topoB = profile.topologySoftScoreFromMetrics(b.metrics);
      final topo = topoB.compareTo(topoA);
      if (topo != 0) return topo;

      final fsrA = DifficultyProfile.midgameFsr(a.metrics.tempoProfile);
      final fsrB = DifficultyProfile.midgameFsr(b.metrics.tempoProfile);
      final midFsr = fsrB.compareTo(fsrA);
      if (midFsr != 0) return midFsr;

      final densityA = _spatialDensity(a.result.value);
      final densityB = _spatialDensity(b.result.value);
      return densityB.compareTo(densityA);
    }

    final cud =
        b.metrics.criticalUnlockDepth.compareTo(a.metrics.criticalUnlockDepth);
    if (cud != 0) return cud;
    final fsr =
        b.metrics.forcedSequenceRatio.compareTo(a.metrics.forcedSequenceRatio);
    if (fsr != 0) return fsr;
    // P4: prefer the candidate whose choice *rhythm* reads better — keeps
    // offering a decision and varies, rather than one long forced corridor.
    // Ranking term only; it never admits or rejects a board.
    final rhythmA =
        ChoiceRhythm.fromTempoProfile(a.metrics.tempoProfile).rankingScore;
    final rhythmB =
        ChoiceRhythm.fromTempoProfile(b.metrics.tempoProfile).rankingScore;
    final rhythm = rhythmB.compareTo(rhythmA);
    if (rhythm != 0) return rhythm;
    final densityA = _spatialDensity(a.result.value);
    final densityB = _spatialDensity(b.result.value);
    final density = densityB.compareTo(densityA);
    if (density != 0) return density;
    if (tier == DifficultyTier.hard) {
      final aOpen = a.metrics.firstLegalMoveCount >= 3 ? 1 : 0;
      final bOpen = b.metrics.firstLegalMoveCount >= 3 ? 1 : 0;
      if (bOpen != aOpen) return bOpen - aOpen;
    }
    return b.metrics.firstLegalMoveCount
        .compareTo(a.metrics.firstLegalMoveCount);
  }

  double _spatialDensity(LevelData level) {
    final area = level.gridWidth * level.gridHeight;
    if (area == 0) return 0;
    return level.nodes.length / area;
  }

  LevelData _enrichLevel(
    LevelData level,
    LevelConfiguration config,
    DifficultyTier? targetTier, {
    MechanicBudgetOverride? mechanicOverride,
  }) {
    final tier =
        targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    return enrichLevel(level, config, tier, mechanicOverride: mechanicOverride);
  }

  double _silhouetteRankingScore(_InBandCandidate candidate) {
    final penalty =
        _silhouetteSessionTracker.streakPenalty(candidate.plan.silhouette);
    final boost =
        _silhouetteSessionTracker.diversityBoost(candidate.plan.silhouette);
    return penalty + boost;
  }

  /// Flushes the staged emission — increments counters and forwards the
  /// event to the analytics sink. Called by `generateFromConfiguration`
  /// once it commits to returning a level.
  void _commitPendingEmission() {
    final pending = _pendingEmission;
    if (pending == null) return;
    final plan = pending.plan;
    _archetypeEmissionCounts[plan.archetype] =
        (_archetypeEmissionCounts[plan.archetype] ?? 0) + 1;
    if (plan.archetype == GenerationArchetype.strongMotif) {
      _strongMotifEmissionCount++;
    }
    if (pending.visibleMotifs.isEmpty) {
      _motifEmissionCounts[MotifId.none] =
          (_motifEmissionCounts[MotifId.none] ?? 0) + 1;
    } else {
      if (plan.archetype == GenerationArchetype.strongMotif) {
        _strongMotifEmissionsWithMotifCount++;
      }
      for (final id in pending.visibleMotifs) {
        _motifEmissionCounts[id] = (_motifEmissionCounts[id] ?? 0) + 1;
      }
    }
    _applyConstructionTelemetry(pending.construction);
    analyticsSink.emit(pending.event);
    _silhouetteSessionTracker.record(pending.plan.silhouette);
    _pendingEmission = null;
  }

  /// Adds one shipped level's construction counters to the session snapshot.
  void _applyConstructionTelemetry(ConstructionTelemetry t) {
    _crunchZoneBlockingPicked += t.crunchZoneBlockingPicked;
    _releaseZoneFallbackPicked += t.releaseZoneFallbackPicked;
    _blockingDirCandidatesOffered += t.blockingDirCandidatesOffered;
    _blockingDirCandidatesPicked += t.blockingDirCandidatesPicked;
    _constructionSolvabilityRetries += t.constructionSolvabilityRetries;
    _lastWinningBlockingRetryIndex = t.winningBlockingRetryIndex;
    final winIdx = t.winningBlockingRetryIndex;
    if (winIdx == 0) {
      _winningBlockingRetryIndex0++;
    } else if (winIdx == 1) {
      _winningBlockingRetryIndex1++;
    } else if (winIdx == 2) {
      _winningBlockingRetryIndex2++;
    }
  }

  /// Drops the staged record without flushing — used when the outer
  /// wave-validation loop rejects the candidate.
  void _discardPendingEmission() {
    _pendingEmission = null;
  }

  /// Returns the IDs of motif blocks from [plan] whose every reservation
  /// (cell + direction) is intact in [level]. A motif partially overwritten
  /// during construction (which the atomic check should already prevent)
  /// would be excluded.
  List<MotifId> _visibleMotifsIn(GenerationPlan plan, LevelData level) {
    if (plan.motifs.isEmpty) return const [];
    final byCell = <int, NodeData>{
      for (final n in level.nodes) gridCellKey(n.x, n.y): n,
    };
    final visible = <MotifId>[];
    for (final m in plan.motifs) {
      var allPresent = true;
      for (final r in m.reservations) {
        final n = byCell[r.cellKey];
        if (n == null) {
          allPresent = false;
          break;
        }
        // Lock clusters may adapt direction at inject time (Phase 2C).
        if (m.id != MotifId.lockCluster && n.dir != r.direction) {
          allPresent = false;
          break;
        }
      }
      if (allPresent) visible.add(m.id);
    }
    return visible;
  }

  bool _legacyGreedyFailure(
    Result<LevelData, GenerationError> result,
    GenerationPlan plan,
  ) {
    if (!plan.useLegacyGreedyPath || result.isSuccess) return false;
    final t = result.error.type;
    return t == 'greedy_elimination_exhausted' ||
        t == 'greedy_direction_assignment_failed';
  }

  ({Result<LevelData, GenerationError> result, ConstructionTelemetry telemetry})
      _runPlannedOnceWithTelemetry(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random, {
    DifficultyTier? targetTier,
  }) {
    if (plan.useLegacyGreedyPath) {
      return (
        result: _attemptLegacyWithSilhouette(plan, config, random),
        telemetry: ConstructionTelemetry.zero,
      );
    }
    return _runRetrogradeForPlan(
      plan,
      config,
      random,
      targetTier: targetTier,
    );
  }

  ({Result<LevelData, GenerationError> result, ConstructionTelemetry telemetry})
      _runRetrogradeForPlan(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random, {
    DifficultyTier? targetTier,
  }) {
    try {
      final sightlines =
          _sightlineTableFor(config.gridWidth, config.gridHeight);
      final scorer = CandidateScorer(weights: plan.spec.scorerWeights);
      final tier =
          targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
      final budget = budgetFor(levelId: config.levelId, mode: config.difficulty.mode);
      final constructor = RetrogradeConstructor(
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        silhouette: plan.silhouetteMask,
        targetNodeCount: plan.targetNodeCount,
        scorer: scorer,
        sightlines: sightlines,
        random: random,
        motifPlacements: plan.motifs,
        tier: tier,
        portalPairCount: budget.portalPairCount,
      );
      final placements = constructor.construct();
      final telemetry = ConstructionTelemetry(
        blockingDirCandidatesOffered: constructor.reassignmentFlipsOffered > 0
            ? constructor.reassignmentFlipsOffered
            : scorer.blockingDirCandidatesOffered,
        blockingDirCandidatesPicked: constructor.reassignmentCrunchFlips > 0
            ? constructor.reassignmentCrunchFlips
            : scorer.blockingDirCandidatesPicked,
        crunchZoneBlockingPicked: scorer.crunchZoneBlockingPicked,
        releaseZoneFallbackPicked: scorer.releaseZoneFallbackPicked,
        constructionSolvabilityRetries:
            constructor.constructionSolvabilityRetries,
        winningBlockingRetryIndex: constructor.winningBlockingRetryIndex,
      );
      if (placements == null || placements.length != plan.targetNodeCount) {
        return (
          result: Result.error(
            GenerationError.noValidDirections(
              'Retrograde construction exhausted rollback budget '
              '(archetype=${plan.archetype.name})',
            ),
          ),
          telemetry: telemetry,
        );
      }
      final palette = _getColorPalette();
      final nodes = <NodeData>[];
      for (var i = 0; i < placements.length; i++) {
        final p = placements[i];
        nodes.add(NodeData(
          id: i,
          x: p.position.x,
          y: p.position.y,
          dir: p.direction,
          color: palette[0],
          colorSlot: 0,
        ));
      }

      // Compute waves to determine depth-tinting.
      final tempLevel = LevelData(
        levelId: config.levelId,
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        playCells: silhouetteToPlayCells(
          plan.silhouetteMask,
          gridWidth: config.gridWidth,
          gridHeight: config.gridHeight,
        ),
        nodes: nodes,
        portalPairs: constructor.placedPortals,
      );

      final waveMap = LevelSolver.nodeWaveIndices(tempLevel);
      var maxWave = 0;
      for (final w in waveMap.values) {
        if (w > maxWave) maxWave = w;
      }

      final finalNodes = <NodeData>[];
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final wave = waveMap[node.id] ?? 0;
        final depth = maxWave > 0 ? wave / maxWave : 0.0;
        int colorSlot;
        if (depth <= 0.33) {
          colorSlot = 2 + random.nextInt(2); // 2 or 3 (warm)
        } else if (depth <= 0.66) {
          colorSlot = random.nextInt(2); // 0 or 1 (green/cyan)
        } else {
          colorSlot = 4 + random.nextInt(2); // 4 or 5 (blue/purple)
        }
        finalNodes.add(node.copyWith(
          colorSlot: colorSlot,
          color: palette[colorSlot],
        ));
      }
      return (
        result: Result.success(LevelData(
          levelId: config.levelId,
          gridWidth: config.gridWidth,
          gridHeight: config.gridHeight,
          playCells: silhouetteToPlayCells(
            plan.silhouetteMask,
            gridWidth: config.gridWidth,
            gridHeight: config.gridHeight,
          ),
          nodes: finalNodes,
          portalPairs: constructor.placedPortals,
          silhouetteId: plan.silhouette,
        )),
        telemetry: telemetry,
      );
    } catch (e) {
      return (
        result: Result.error(
          GenerationError.unexpected('Retrograde generation failed: $e'),
        ),
        telemetry: ConstructionTelemetry.zero,
      );
    }
  }

  /// §5 Experimental archetype's "use the legacy greedy path" option. Runs
  /// the same code path as the Phase 1/2 fallback (`_attemptLegacyGeneration`),
  /// but constrained to the silhouette / target the Director chose so the
  /// Experimental archetype still respects the diversity ledger.
  Result<LevelData, GenerationError> _attemptLegacyWithSilhouette(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random,
  ) {
    _legacyAttemptCount++;
    final playCells = silhouetteToPlayCells(
      plan.silhouetteMask,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
    );
    try {
      final positions = _selectUniquePositions(
        plan.targetNodeCount,
        config.gridWidth,
        config.gridHeight,
        random,
        playCells,
      );
      if (positions.length < plan.targetNodeCount) {
        return Result.error(
          GenerationError.noValidDirections(
            'Silhouette too small for greedy Experimental path',
          ),
        );
      }
      final solutionPath = tryGreedyEliminationOrder(
        positions,
        config.gridWidth,
        config.gridHeight,
        random,
      );
      if (solutionPath == null) {
        return Result.error(GenerationError.greedyEliminationExhausted());
      }
      final nodes = _assignDirections(
        solutionPath,
        config.gridWidth,
        config.gridHeight,
        random,
        DirectionBiasType.uniform,
      );
      if (nodes == null) {
        return Result.error(
          GenerationError.greedyDirectionAssignmentFailed(),
        );
      }
      return Result.success(LevelData(
        levelId: config.levelId,
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        playCells: playCells,
        nodes: nodes,
      ));
    } catch (e) {
      return Result.error(
        GenerationError.unexpected('Greedy Experimental path failed: $e'),
      );
    }
  }

  SightlineTable _sightlineTableFor(int gridWidth, int gridHeight) {
    final key = (gridHeight << 8) | (gridWidth & 0xff);
    return _sightlineCache.putIfAbsent(
      key,
      () => SightlineTable.forGrid(gridWidth, gridHeight),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Position selection (stratified sampling)
  // ────────────────────────────────────────────────────────────────────────

  List<Point<int>> _selectUniquePositions(
    int count,
    int gridWidth,
    int gridHeight,
    Random random,
    Set<String>? allowedCells,
  ) {
    final positions = <Point<int>>[];
    final used = <String>{};

    if (allowedCells != null && allowedCells.isNotEmpty) {
      final pool = allowedCells.map((k) {
        final parts = k.split(',');
        return Point(int.parse(parts[0]), int.parse(parts[1]));
      }).toList()
        ..shuffle(random);
      if (pool.length < count) return positions;
      for (var i = 0; i < count; i++) {
        positions.add(pool[i]);
      }
      return positions;
    }

    if (count > 1) {
      final sectors = sqrt(count.toDouble()).ceil();
      final sectorW = (gridWidth / sectors).ceil();
      final sectorH = (gridHeight / sectors).ceil();

      for (int sy = 0; sy < sectors && positions.length < count; sy++) {
        for (int sx = 0; sx < sectors && positions.length < count; sx++) {
          final xMin = sx * sectorW;
          final xMax = min(xMin + sectorW, gridWidth);
          final yMin = sy * sectorH;
          final yMax = min(yMin + sectorH, gridHeight);
          if (xMin >= gridWidth || yMin >= gridHeight) continue;

          for (int attempt = 0; attempt < 8; attempt++) {
            final x = xMin + random.nextInt(xMax - xMin);
            final y = yMin + random.nextInt(yMax - yMin);
            final key = '$x,$y';
            if (used.add(key)) {
              positions.add(Point(x, y));
              break;
            }
          }
        }
      }
    }

    int safety = 0;
    while (positions.length < count && safety++ < count * 100) {
      final x = random.nextInt(gridWidth);
      final y = random.nextInt(gridHeight);
      final key = '$x,$y';
      if (used.add(key)) {
        positions.add(Point(x, y));
      }
    }

    positions.shuffle(random);
    return positions;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Direction assignment (backward guarantee + bias)
  // ────────────────────────────────────────────────────────────────────────

  List<NodeData>? _assignDirections(
    List<Point<int>> solutionPath,
    int gridWidth,
    int gridHeight,
    Random random,
    DirectionBiasType bias,
  ) {
    final nodes = <NodeData>[];
    final palette = _getColorPalette();

    for (int i = 0; i < solutionPath.length; i++) {
      final position = solutionPath[i];
      final futureNodes = solutionPath.sublist(i + 1);

      final direction = _findValidDirection(
        position,
        futureNodes,
        gridWidth,
        gridHeight,
        random,
        bias,
      );

      if (direction == null) return null;

      nodes.add(NodeData(
        id: i,
        x: position.x,
        y: position.y,
        dir: direction,
        color: palette[0],
        colorSlot: 0,
      ));
    }

    // Compute waves to determine depth-tinting.
    final tempLevel = LevelData(
      levelId: 0,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      playCells: null,
      nodes: nodes,
    );

    final waveMap = LevelSolver.nodeWaveIndices(tempLevel);
    var maxWave = 0;
    for (final w in waveMap.values) {
      if (w > maxWave) maxWave = w;
    }

    final finalNodes = <NodeData>[];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final wave = waveMap[node.id] ?? 0;
      final depth = maxWave > 0 ? wave / maxWave : 0.0;
      int colorSlot;
      if (depth <= 0.33) {
        colorSlot = 2 + random.nextInt(2); // 2 or 3 (warm)
      } else if (depth <= 0.66) {
        colorSlot = random.nextInt(2); // 0 or 1 (green/cyan)
      } else {
        colorSlot = 4 + random.nextInt(2); // 4 or 5 (blue/purple)
      }
      finalNodes.add(node.copyWith(
        colorSlot: colorSlot,
        color: palette[colorSlot],
      ));
    }

    return finalNodes;
  }

  /// Finds a direction whose ray does not hit any [futureNodes], using
  /// weighted ordering from [bias].
  Direction? _findValidDirection(
    Point<int> position,
    List<Point<int>> futureNodes,
    int gridWidth,
    int gridHeight,
    Random random,
    DirectionBiasType bias,
  ) {
    final ordered = _biasedDirectionOrder(
      random,
      bias,
      position,
      gridWidth,
      gridHeight,
    );

    if (futureNodes.isEmpty) return ordered.first;

    final futureSet = <int>{
      for (final p in futureNodes) gridCellKey(p.x, p.y),
    };

    for (final dir in ordered) {
      if (!_directionHitsNodes(
          position, dir, futureSet, gridWidth, gridHeight)) {
        return dir;
      }
    }

    return null;
  }

  /// Returns the four directions in a weighted-random order.
  List<Direction> _biasedDirectionOrder(
    Random random,
    DirectionBiasType bias,
    Point<int> position,
    int gridWidth,
    int gridHeight,
  ) {
    switch (bias) {
      case DirectionBiasType.uniform:
        return Direction.values.toList()..shuffle(random);

      case DirectionBiasType.horizontal:
        return _weightedShuffle(random, {
          Direction.left: 2.0,
          Direction.right: 2.0,
          Direction.up: 1.0,
          Direction.down: 1.0,
        });

      case DirectionBiasType.vertical:
        return _weightedShuffle(random, {
          Direction.up: 2.0,
          Direction.down: 2.0,
          Direction.left: 1.0,
          Direction.right: 1.0,
        });

      case DirectionBiasType.inward:
        final cx = gridWidth / 2.0;
        final cy = gridHeight / 2.0;
        return _weightedShuffle(random, {
          Direction.left: position.x > cx ? 2.0 : 0.5,
          Direction.right: position.x < cx ? 2.0 : 0.5,
          Direction.up: position.y > cy ? 2.0 : 0.5,
          Direction.down: position.y < cy ? 2.0 : 0.5,
        });

      case DirectionBiasType.outward:
        final cx = gridWidth / 2.0;
        final cy = gridHeight / 2.0;
        return _weightedShuffle(random, {
          Direction.left: position.x < cx ? 2.0 : 0.5,
          Direction.right: position.x > cx ? 2.0 : 0.5,
          Direction.up: position.y < cy ? 2.0 : 0.5,
          Direction.down: position.y > cy ? 2.0 : 0.5,
        });
    }
  }

  /// Weighted random ordering: picks directions one at a time with
  /// probability proportional to weight.
  List<Direction> _weightedShuffle(
    Random random,
    Map<Direction, double> weights,
  ) {
    final result = <Direction>[];
    final pool = Map<Direction, double>.from(weights);
    while (pool.isNotEmpty) {
      final total = pool.values.fold(0.0, (a, b) => a + b);
      var r = random.nextDouble() * total;
      Direction? picked;
      for (final entry in pool.entries) {
        r -= entry.value;
        if (r <= 0) {
          picked = entry.key;
          break;
        }
      }
      picked ??= pool.keys.last;
      result.add(picked);
      pool.remove(picked);
    }
    return result;
  }

  /// Ray-cast: returns true if the ray hits any future node before exiting.
  bool _directionHitsNodes(
    Point<int> position,
    Direction dir,
    Set<int> futureSet,
    int gridWidth,
    int gridHeight,
  ) {
    int x = position.x;
    int y = position.y;

    while (true) {
      switch (dir) {
        case Direction.up:
          y--;
          break;
        case Direction.down:
          y++;
          break;
        case Direction.left:
          x--;
          break;
        case Direction.right:
          x++;
          break;
      }
      if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return false;
      if (futureSet.contains(gridCellKey(x, y))) return true;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Phase 3 retired _generateFallbackLevel / _generateOneDirection /
  // _levelDataRowMajorMonotone / _levelDataMonotone — the Director's
  // archetype + silhouette renegotiation replaces them. Anything that needs
  // a "monotone" feel can build a seeded RingSeed / etc. in Phase 5.
  // ────────────────────────────────────────────────────────────────────────

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  static bool _isHardExpertTier(DifficultyTier tier) =>
      tier == DifficultyTier.hard || tier == DifficultyTier.expert;

  static bool _openingWithinHardExpertBand(LevelMetrics metrics) {
    const band = DifficultyProfile.hardExpertOpeningBand;
    return band.contains(metrics.firstLegalMoveCount) &&
        band.contains(metrics.waveZeroWidth);
  }

  /// Hard ceiling on opening width for Hard/Expert emissions (Option A band).
  static void _guardHardExpertOpening(
    LevelMetrics metrics, {
    required String context,
  }) {
    const band = DifficultyProfile.hardExpertOpeningBand;
    if (metrics.firstLegalMoveCount > band.max ||
        metrics.waveZeroWidth > band.max) {
      throw StateError(
        '$context: opening=${metrics.firstLegalMoveCount} '
        'waveZero=${metrics.waveZeroWidth} exceeds band max ${band.max}',
      );
    }
  }

  void _assertGeneratedLayout(LevelData level) {
    final msg = LevelData.layoutValidationMessage(level);
    assert(msg == null, 'Invalid layout: $msg');
  }

  List<Color> _getColorPalette() => AppColors.nodePalette;

  /// Returns the grid width for a given [levelId] and [mode].
  static int calculateGridSize(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).gridWidth;
  }

  /// Returns the target node count for a given [levelId] and [mode].
  static int calculateNodeCount(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).targetNodeCount;
  }
}

/// Phase 6 — staged emission record. The Director-driven path fills this
/// once per successful candidate; the outer caller commits it (counters +
/// analytics) or drops it depending on wave-validation outcome.
class _PendingDirectorEmission {
  final GenerationPlan plan;
  final List<MotifId> visibleMotifs;
  final ConstructionTelemetry construction;
  final GenerationEmissionEvent event;
  const _PendingDirectorEmission({
    required this.plan,
    required this.visibleMotifs,
    required this.construction,
    required this.event,
  });
}

class _InBandCandidate {
  final Result<LevelData, GenerationError> result;
  final GenerationPlan plan;
  final LevelMetrics metrics;
  final LevelFingerprint fingerprint;
  final List<MotifId> visibleMotifs;
  final int renegotiations;
  final ConstructionTelemetry constructionTelemetry;

  const _InBandCandidate({
    required this.result,
    required this.plan,
    required this.metrics,
    required this.fingerprint,
    required this.visibleMotifs,
    required this.renegotiations,
    required this.constructionTelemetry,
  });
}
