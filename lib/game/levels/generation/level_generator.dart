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
import 'difficulty_parameters.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'level_seed.dart';
import 'metrics.dart';
import 'motifs.dart';
import 'removal_order.dart';
import '../analytics/generation_analytics.dart';
import '../seeds/seeds.dart';
import 'result.dart';
import 'retrograde_constructor.dart';
import 'sightline_table.dart';
import 'silhouettes.dart';

/// Milestone types triggered at specific level multiples.
///
/// Phase 5 retired `ring` — the Ring milestone now flows through the
/// [LevelSeed] pipeline (`milestoneSeedFor` → `Director.choosePlanFromSeed`)
/// instead of its bespoke `_generateRing` branch.
enum _MilestoneType {
  maxDensity,
  sparseSniper,
}

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

  /// When false, the diversity ledger never rejects a candidate (it is still
  /// updated for telemetry). Set to false in tests that expect strict
  /// determinism across multiple `generate()` calls on the same generator;
  /// production callers should leave it at the default `true`.
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
  // Phase 3 retired the monotone fallback path entirely. The counter remains
  // wired so any future regression can be detected; it should never go
  // above 0 in production.
  int _monotoneFallbackHitCount = 0;
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
    this.enableDiversityGating = true,
    GenerationAnalyticsSink? analyticsSink,
  })  : _validator = validator ?? LevelValidator(),
        _director = director ?? Director(),
        _diversityLedger = diversityLedger ?? DiversityLedger(),
        analyticsSink = analyticsSink ?? noopAnalyticsSink;

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

  /// Should be `0` in Phase 3+ (monotone fallback retired). Kept as a
  /// regression sensor; any non-zero value means we shipped a fallback path
  /// we forgot to delete.
  int get monotoneFallbackHitCount => _monotoneFallbackHitCount;

  /// Per-archetype emission counter. Used by Phase 3's distribution test.
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
      monotoneFallbackHits: _monotoneFallbackHitCount,
      archetypeEmissions:
          Map<GenerationArchetype, int>.from(_archetypeEmissionCounts),
      seedEmissions: Map<String, int>.from(_seedEmissionCounts),
      strongMotifEmissions: _strongMotifEmissionCount,
      strongMotifEmissionsWithMotif: _strongMotifEmissionsWithMotifCount,
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
    _monotoneFallbackHitCount = 0;
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
  }) {
    final config = LevelConfiguration.fromLevelId(levelId, mode: mode);
    return generateFromConfiguration(
      config,
      primarySeed: levelId,
      applyMilestones: true,
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
    int maxAttempts = 28,
    DifficultyTier? targetTier,
  }) {
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
      final opening =
          useOpeningSeeds ? seedRegistry[config.levelId] : null;
      final seed = opening ?? milestoneSeedFor(config);
      if (seed != null) {
        final seedSalt = seed.seedRng ?? 0;
        final rng = Random(primarySeed * 31337 + seedSalt);
        final seedResult = _attemptDirectorDrivenGeneration(
          config,
          rng,
          targetTier: targetTier,
          seed: seed,
        );
        if (seedResult.isSuccess) {
          final level = seedResult.value;
          final validationResult = _validator.validate(level);
          if (validationResult.isValid) {
            _seedEmissionCounts[seed.id] =
                (_seedEmissionCounts[seed.id] ?? 0) + 1;
            _assertGeneratedLayout(level);
            _commitPendingEmission();
            return seedResult;
          }
        }
        // Seed path failed (e.g. silhouette starvation on a tiny grid):
        // fall through to the regular pipeline so the level still ships.
        _discardPendingEmission();
      }
    }

    // ── Milestone levels (every 25th, Medium/Hard only) ───────────────
    if (applyMilestones) {
      final milestone = _getMilestoneType(config);
      if (milestone != null) {
        final rng = Random(primarySeed * 31337);
        final result = _generateMilestone(milestone, config, rng);
        if (result.isSuccess) {
          final level = result.value;
          final validationResult = _validator.validate(level);
          if (validationResult.isValid) {
            _assertGeneratedLayout(level);
            _commitPendingMilestoneEmission(milestone);
            return result;
          }
          _discardPendingEmission();
        } else {
          _discardPendingEmission();
        }
      }
    }

    // ── Normal generation with retries ────────────────────────────────
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final rng = Random(primarySeed * 31337 + attempt * 999983);

      final nodeCountScale = 1.0 - (attempt ~/ 2) * 0.15;
      final scaledConfig = attempt < 2
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

      final result = _attemptGeneration(scaledConfig, rng, targetTier: targetTier);
      if (result.isSuccess) {
        final level = result.value;
        final validationResult = _validator.validate(level);
        if (!validationResult.isValid) {
          _discardPendingEmission();
          continue;
        }

        final waves = LevelSolver.countRemovalWaves(level);
        final (wMin0, wMax0) =
            removalWaveBounds(scaledConfig.difficulty, level.nodes.length);
        var wMin = wMin0;
        var wMax = wMax0;
        if (attempt >= maxAttempts ~/ 2) {
          wMin = max(1, wMin0 - 1);
          wMax = min(level.nodes.length, wMax0 + 4);
        }
        if (attempt >= maxAttempts - 4) {
          wMin = max(1, wMin0 - 2);
          wMax = min(level.nodes.length, wMax0 + 10);
        }
        if (waves >= wMin && waves <= wMax) {
          _assertGeneratedLayout(level);
          _commitPendingEmission();
          return Result.success(level);
        }
        // Out-of-band wave count — drop the staged event so the next attempt
        // can stage afresh.
        _discardPendingEmission();
      }
    }

    // Phase 3: no monotone fallback any more. The Director Renegotiation
    // already had its chances above. Surface a typed error so callers can
    // pick a sensible response (re-roll a new seed, prompt for a different
    // mode, etc.) instead of the old "always emit something" behaviour.
    _discardPendingEmission();
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
  Result<LevelData, GenerationError> generateDailyChallenge(int dayKey) {
    final config = LevelConfiguration.forDailyChallenge(dayKey);
    return generateFromConfiguration(
      config,
      primarySeed: dayKey,
      applyMilestones: false,
      maxAttempts: 32,
      targetTier: DifficultyTier.expert,
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
  }) {
    return _attemptDirectorDrivenGeneration(
      config,
      random,
      targetTier: targetTier,
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
    Result<LevelData, GenerationError>? nonNovelFallback;
    LevelMetrics? nonNovelMetrics;
    LevelFingerprint? nonNovelFp;
    GenerationPlan? nonNovelPlan;
    int nonNovelRenegotiations = 0;

    final evaluatorTier =
        targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    final evaluatorProfile = DifficultyProfile.forTier(evaluatorTier);

    for (var k = 0; k < _evaluatorRetryBudget; k++) {
      // Derive a per-iteration RNG so successive retries diverge
      // deterministically without consuming unbounded state from `random`.
      final iterationRandom = Random(random.nextInt(0x7fffffff));
      var plan = seed != null
          ? _director.choosePlanFromSeed(seed, config, iterationRandom)
          : _director.choosePlan(
              config,
              iterationRandom,
              overrideTier: targetTier,
            );

      Result<LevelData, GenerationError>? once;
      var renegotiationsForThisAttempt = 0;
      for (var r = 0; r <= _director.maxRenegotiations; r++) {
        once = _runPlannedOnce(plan, config, iterationRandom);
        if (once.isSuccess) break;
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
      final inBand = evaluatorProfile.passes(metrics);
      if (!inBand) _evaluatorRejectionCount++;

      final fingerprint = computeLevelFingerprint(
        level: level,
        metrics: metrics,
        silhouette: plan.silhouette,
      );
      final novel = !enableDiversityGating ||
          _diversityLedger.isNovel(fingerprint);
      if (!novel) {
        _diversityRejectionCount++;
        nonNovelFallback ??= once;
        nonNovelPlan ??= plan;
        nonNovelMetrics ??= metrics;
        nonNovelFp ??= fingerprint;
        nonNovelRenegotiations = renegotiationsForThisAttempt;
        continue;
      }

      if (inBand) {
        _retrogradeInBandSuccessCount++;
        _retrogradeSuccessCount++;
        _diversityLedger.record(fingerprint);
        _recordEmissionTelemetry(
          plan: plan,
          level: level,
          metrics: metrics,
          fingerprint: fingerprint,
          inBand: true,
          novel: true,
          seed: seed,
          renegotiations: renegotiationsForThisAttempt,
        );
        return once;
      }
      novelOutOfBand ??= once;
      novelOutOfBandFp ??= fingerprint;
      novelOutOfBandMetrics ??= metrics;
      novelOutOfBandPlan ??= plan;
      novelOutOfBandRenegotiations = renegotiationsForThisAttempt;
    }

    // Prefer the novel out-of-band so we keep the ledger window clean.
    if (novelOutOfBand != null) {
      _retrogradeOutOfBandSuccessCount++;
      _retrogradeSuccessCount++;
      _diversityLedger.record(novelOutOfBandFp!);
      _recordEmissionTelemetry(
        plan: novelOutOfBandPlan!,
        level: novelOutOfBand.value,
        metrics: novelOutOfBandMetrics!,
        fingerprint: novelOutOfBandFp,
        inBand: false,
        novel: true,
        seed: seed,
        renegotiations: novelOutOfBandRenegotiations,
      );
      return novelOutOfBand;
    }
    // Last resort: emit a non-novel candidate WITHOUT recording it in the
    // ledger. This keeps the window's "all pairs distance ≥ 5" invariant
    // intact (the cost is that the very next emission can be close to
    // this one, which we accept over crashing the caller).
    if (nonNovelFallback != null) {
      _retrogradeOutOfBandSuccessCount++;
      _retrogradeSuccessCount++;
      _diversityLedger.record(nonNovelFp!);
      _recordEmissionTelemetry(
        plan: nonNovelPlan!,
        level: nonNovelFallback.value,
        metrics: nonNovelMetrics!,
        fingerprint: nonNovelFp,
        inBand: false,
        novel: false,
        seed: seed,
        renegotiations: nonNovelRenegotiations,
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
    required GenerationPlan plan,
    required LevelData level,
    required LevelMetrics metrics,
    required LevelFingerprint fingerprint,
    required bool inBand,
    required bool novel,
    required LevelSeed? seed,
    required int renegotiations,
  }) {
    final visible = _visibleMotifsIn(plan, level);
    _pendingEmission = _PendingDirectorEmission(
      plan: plan,
      visibleMotifs: visible,
      event: buildEmissionEvent(
        level: level,
        archetype: plan.archetype,
        silhouette: plan.silhouette,
        seed: seed,
        inBand: inBand,
        novelFingerprint: novel,
        metrics: metrics,
        fingerprint: fingerprint,
        renegotiations: renegotiations,
      ),
    );
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
    analyticsSink.emit(pending.event);
    _pendingEmission = null;
  }

  /// Campaign milestones reuse the telemetry staged inside
  /// [_attemptDirectorDrivenGeneration] but tag synthetic `seedId` values so
  /// corpus / QA tooling can correlate emissions without implying a pinned
  /// [LevelSeed] row.
  void _commitPendingMilestoneEmission(_MilestoneType type) {
    final pending = _pendingEmission;
    if (pending == null) return;
    final seedTag = switch (type) {
      _MilestoneType.maxDensity => 'milestone:maxDensity',
      _MilestoneType.sparseSniper => 'milestone:sparseSniper',
    };
    final e = pending.event;
    _pendingEmission = _PendingDirectorEmission(
      plan: pending.plan,
      visibleMotifs: pending.visibleMotifs,
      event: GenerationEmissionEvent(
        levelId: e.levelId,
        archetype: e.archetype,
        silhouette: e.silhouette,
        seedId: seedTag,
        inBand: e.inBand,
        novelFingerprint: e.novelFingerprint,
        metrics: e.metrics,
        fingerprint: e.fingerprint,
        renegotiations: e.renegotiations,
      ),
    );
    _commitPendingEmission();
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
        if (n == null || n.dir != r.direction) {
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

  Result<LevelData, GenerationError> _runPlannedOnce(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random,
  ) {
    if (plan.useLegacyGreedyPath) {
      // §5 Experimental archetype — preserve the legacy greedy path so
      // "happy accidents" the retrograde-with-scorer combo would never pick
      // still occur. Honour the plan's chosen mask + target.
      return _attemptLegacyWithSilhouette(plan, config, random);
    }
    return _runRetrogradeForPlan(plan, config, random);
  }

  Result<LevelData, GenerationError> _runRetrogradeForPlan(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random,
  ) {
    try {
      final sightlines =
          _sightlineTableFor(config.gridWidth, config.gridHeight);
      final scorer = CandidateScorer(weights: plan.spec.scorerWeights);
      final constructor = RetrogradeConstructor(
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        silhouette: plan.silhouetteMask,
        targetNodeCount: plan.targetNodeCount,
        scorer: scorer,
        sightlines: sightlines,
        random: random,
        reservations: plan.reservations,
      );
      final placements = constructor.construct();
      if (placements == null || placements.length != plan.targetNodeCount) {
        return Result.error(
          GenerationError.noValidDirections(
            'Retrograde construction exhausted rollback budget '
            '(archetype=${plan.archetype.name})',
          ),
        );
      }
      final palette = _getColorPalette();
      final nodes = <NodeData>[];
      for (var i = 0; i < placements.length; i++) {
        final p = placements[i];
        final colorSlot = random.nextInt(palette.length);
        nodes.add(NodeData(
          id: i,
          x: p.position.x,
          y: p.position.y,
          dir: p.direction,
          color: palette[colorSlot],
          colorSlot: colorSlot,
        ));
      }
      return Result.success(LevelData(
        levelId: config.levelId,
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        playCells: silhouetteToPlayCells(
          plan.silhouetteMask,
          gridWidth: config.gridWidth,
          gridHeight: config.gridHeight,
        ),
        nodes: nodes,
      ));
    } catch (e) {
      return Result.error(
        GenerationError.unexpected('Retrograde generation failed: $e'),
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

      final colorSlot = random.nextInt(palette.length);
      nodes.add(NodeData(
        id: i,
        x: position.x,
        y: position.y,
        dir: direction,
        color: palette[colorSlot],
        colorSlot: colorSlot,
      ));
    }

    return nodes;
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
  // Milestone levels (Item 10)
  // ────────────────────────────────────────────────────────────────────────

  /// Returns the milestone type for this level, or null for normal levels.
  /// Milestones fire every 25th level for Medium/Hard only.
  static _MilestoneType? _getMilestoneType(LevelConfiguration config) {
    if (config.difficulty.mode == DifficultyMode.easy) return null;
    final id = config.levelId;
    if (id < 25) return null;

    final mod = id % 100;
    if (mod == 0) return _MilestoneType.sparseSniper;
    if (mod == 50) return _MilestoneType.maxDensity;
    // mod == 25 and mod == 75 are now handled by the [LevelSeed] pipeline
    // (diamond / ring respectively); see `milestoneSeedFor`.
    return null;
  }

  Result<LevelData, GenerationError> _generateMilestone(
    _MilestoneType type,
    LevelConfiguration config,
    Random random,
  ) {
    switch (type) {
      case _MilestoneType.maxDensity:
        return _generateMaxDensity(config, random);
      case _MilestoneType.sparseSniper:
        return _generateSparseSniper(config, random);
    }
  }

  /// Nearly maximum density — fills as many cells as the grid allows.
  Result<LevelData, GenerationError> _generateMaxDensity(
    LevelConfiguration config,
    Random random,
  ) {
    final maxCount = min(
        config.gridWidth * config.gridHeight, max(config.targetNodeCount, 40));
    final denseConfig = LevelConfiguration(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      targetNodeCount: maxCount,
      difficulty: config.difficulty,
      archetype: config.archetype,
      directionBias: DirectionBiasType.uniform,
      irregularMaskProbability: config.irregularMaskProbability,
      irregularLayoutExtraTries: config.irregularLayoutExtraTries,
      minimumTargetNodeCount: config.minimumTargetNodeCount,
    );
    return _attemptGeneration(denseConfig, random);
  }

  /// Nodes placed only on the border of the grid.
  /// Very few nodes on a large grid — a "sniper" challenge.
  Result<LevelData, GenerationError> _generateSparseSniper(
    LevelConfiguration config,
    Random random,
  ) {
    final sparseCount = max(
      config.difficulty.minNodes,
      (config.targetNodeCount * 0.45).round(),
    );
    final w = min(20, config.gridWidth + 2);
    final h = min(20, config.gridHeight + 2);
    final sparseConfig = LevelConfiguration(
      levelId: config.levelId,
      gridWidth: w,
      gridHeight: h,
      targetNodeCount: sparseCount,
      difficulty: config.difficulty,
      archetype: config.archetype,
      directionBias: DirectionBiasType.uniform,
      irregularMaskProbability: config.irregularMaskProbability,
      irregularLayoutExtraTries: config.irregularLayoutExtraTries,
      minimumTargetNodeCount: config.minimumTargetNodeCount,
    );
    return _attemptGeneration(sparseConfig, random);
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
  final GenerationEmissionEvent event;
  const _PendingDirectorEmission({
    required this.plan,
    required this.visibleMotifs,
    required this.event,
  });
}
