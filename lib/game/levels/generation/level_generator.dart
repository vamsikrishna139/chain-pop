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
  // T2.5 — K-loop mortality, per stage.
  //
  // `_evaluatorRejectionCount` cannot answer "which gate starves the funnel":
  // it also increments on the `!inBand` branch when the candidate then *goes
  // on to be counted*, so it is not a count of rejections. It is kept
  // unchanged so the analytics series stays a like-for-like measurement, and
  // these stand beside it. All are write-only — nothing reads them but tests.
  int _kloopIterations = 0;
  int _kloopBudgetBreaks = 0;
  int _constructionFailures = 0;
  int _fsrCapRejects = 0;
  int _compositionHardRejects = 0;
  int _cudFloorRejects = 0;
  int _outOfBandNoted = 0;
  // Attribution for [_compositionHardRejects]. `visual.reason` names the first
  // failing rule in the fixed priority order aspect → blobVsGrid → occupancy →
  // singleton → components, hard or soft — so on a hard reject it can name a
  // *soft* rule that also failed. `kHardCompositionRules` is {aspect,
  // components} and aspect is first, so the attribution is exact: reason ==
  // aspect means aspect; anything else means components was the hard failure.
  // Getting this wrong is the same trap T2.4c fell into.
  int _hardRejectAspect = 0;
  int _hardRejectComponents = 0;
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

  // ── Candidate telemetry (the bundle, per plan §T2.0) ──────────────────────
  //
  // The open question T2.1 raised and could not answer while it was parked:
  // when repeated `generate(44)` stopped producing different boards, did the
  // diversity ledger stop *influencing* selection, or did the generator stop
  // *producing* eligible alternatives for it to choose between? Those have
  // opposite fixes, and no counter in the session snapshot separated them.
  //
  // Write-only, like every counter here (T0.0c asserts as much): nothing reads
  // these during generation, so they cannot move a board.
  int _candidateCount = 0;
  int _novelCandidateCount = 0;
  int _acceptedNovelCandidateCount = 0;
  final Map<String, int> _fallbackReasonCounts = <String, int>{};

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

  // Seeded-path *failure* telemetry, by seed id.
  //
  // [_seedEmissionCounts] counts only the seeded attempts that shipped, which
  // is why the milestone-fallthrough defect survived for so long: a milestone
  // that burned all its attempts and quietly shipped as an ordinary procedural
  // board was indistinguishable, from the outside, from one that never had a
  // seed at all. Nothing counted the failure, so nothing could alert on it.
  //
  // These five are that missing half. They are pure counters — no behaviour
  // depends on them — but between them they say exactly *why* a milestone did
  // not ship as itself:
  //
  //   attempts             seeded iterations entered
  //   constructionFailures the Director could not build the pinned silhouette
  //   validationFailures   it built, but the enriched board was invalid
  //   mechanicShortfalls   it built and validated, but could not seat the
  //                        lock/relay budget
  //   fallthroughs         the seeded path gave up and the level shipped as a
  //                        procedural board — the landmark is gone
  final Map<String, int> _seedAttemptCounts = <String, int>{};
  final Map<String, int> _seedConstructionFailureCounts = <String, int>{};
  final Map<String, int> _seedValidationFailureCounts = <String, int>{};
  final Map<String, int> _seedMechanicShortfallCounts = <String, int>{};
  final Map<String, int> _seedFallthroughCounts = <String, int>{};

  void _bumpSeed(Map<String, int> counter, String id) =>
      counter[id] = (counter[id] ?? 0) + 1;

  /// How many seeded attempts may be spent chasing a board that seats its
  /// *full* lock/relay budget before the path ships a mechanic-short one.
  ///
  /// The audit (`milestone_seed_audit_test`) measured the trade directly: on
  /// every slot that lost its landmark, 30-39 of the 40 attempts ended in a
  /// shortfall and none ever seated the full budget. Retrying is close to free
  /// of upside there and costs the whole 40-attempt burn, so the cap is small.
  /// It is not zero because the cheap slots *do* recover within an attempt or
  /// two (225, 325, 825 all emit after one shortfall).
  static const int _kSeedMechanicShortfallRetries = 3;

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
        analyticsSink = analyticsSink ?? noopAnalyticsSink {
    // Hand the Director a read-only view of session history so it can break
    // same-family runs at request time. The tracker stays owned here; the
    // Director only ever reads it.
    _director.currentFamilyStreak = () => (
          family: _silhouetteSessionTracker.currentStreakFamily() ??
              SilhouetteVisualFamily.geometricLattice,
          length: _silhouetteSessionTracker.currentStreakLength(),
        );
  }

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

  /// T2.5 — K-loop mortality, per stage. Every iteration entered exits through
  /// exactly one of: [constructionFailures], [fsrCapRejects],
  /// [compositionHardRejects], [cudFloorRejects], or reaching the ledger
  /// ([candidateCount]). [kloopBudgetBreaks] counts iterations never entered
  /// because the latency budget ended the loop early; [outOfBandNoted] is an
  /// observation, not an exit — those candidates still reach the ledger.
  int get kloopIterations => _kloopIterations;
  int get kloopBudgetBreaks => _kloopBudgetBreaks;
  int get constructionFailures => _constructionFailures;
  int get fsrCapRejects => _fsrCapRejects;
  int get compositionHardRejects => _compositionHardRejects;
  int get cudFloorRejects => _cudFloorRejects;
  int get outOfBandNoted => _outOfBandNoted;
  int get hardRejectAspect => _hardRejectAspect;
  int get hardRejectComponents => _hardRejectComponents;

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

  /// Seeded iterations entered, by seed id.
  Map<String, int> get seedAttemptCounts =>
      Map<String, int>.unmodifiable(_seedAttemptCounts);

  /// Seeded iterations where the Director could not build the pinned
  /// silhouette at all.
  Map<String, int> get seedConstructionFailureCounts =>
      Map<String, int>.unmodifiable(_seedConstructionFailureCounts);

  /// Seeded iterations that built a board whose enrichment failed validation.
  Map<String, int> get seedValidationFailureCounts =>
      Map<String, int>.unmodifiable(_seedValidationFailureCounts);

  /// Seeded iterations discarded because the enriched board could not seat its
  /// full lock/relay budget.
  Map<String, int> get seedMechanicShortfallCounts =>
      Map<String, int>.unmodifiable(_seedMechanicShortfallCounts);

  /// Seeds that gave up and let the level ship as an ordinary procedural
  /// board. **Any non-zero entry here is a lost milestone**, and the whole
  /// point of this counter is that it can no longer happen silently.
  Map<String, int> get seedFallthroughCounts =>
      Map<String, int>.unmodifiable(_seedFallthroughCounts);

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
      seedAttempts: Map<String, int>.from(_seedAttemptCounts),
      seedConstructionFailures:
          Map<String, int>.from(_seedConstructionFailureCounts),
      seedValidationFailures:
          Map<String, int>.from(_seedValidationFailureCounts),
      seedMechanicShortfalls:
          Map<String, int>.from(_seedMechanicShortfallCounts),
      seedFallthroughs: Map<String, int>.from(_seedFallthroughCounts),
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
    _kloopIterations = 0;
    _kloopBudgetBreaks = 0;
    _constructionFailures = 0;
    _fsrCapRejects = 0;
    _coreFloorRejects = 0;
    _compositionHardRejects = 0;
    _cudFloorRejects = 0;
    _outOfBandNoted = 0;
    _hardRejectAspect = 0;
    _hardRejectComponents = 0;
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
    _candidateCount = 0;
    _novelCandidateCount = 0;
    _acceptedNovelCandidateCount = 0;
    _fallbackReasonCounts.clear();
    for (final a in GenerationArchetype.values) {
      _archetypeEmissionCounts[a] = 0;
    }
    _strongMotifEmissionCount = 0;
    _strongMotifEmissionsWithMotifCount = 0;
    for (final m in MotifId.values) {
      _motifEmissionCounts[m] = 0;
    }
    _seedEmissionCounts.clear();
    _seedAttemptCounts.clear();
    _seedConstructionFailureCounts.clear();
    _seedValidationFailureCounts.clear();
    _seedMechanicShortfallCounts.clear();
    _seedFallthroughCounts.clear();
  }

  /// T2.4a shadow-mode score samples. Capped so a long session cannot grow
  /// them without bound; the cap is far above any single corpus sweep.
  static const int _kVisualScoreSampleCap = 50000;
  final List<double> _visualScoresAccepted = [];
  final List<double> _visualScoresRejected = [];

  /// Composition scores of candidates that passed the composition rules.
  List<double> get visualScoresAccepted =>
      List.unmodifiable(_visualScoresAccepted);

  /// Composition scores of candidates the composition rules rejected.
  ///
  /// This is the population T2.4b cannot obtain any other way: these boards are
  /// discarded inside the K-loop and never reach a CSV.
  List<double> get visualScoresRejected =>
      List.unmodifiable(_visualScoresRejected);

  /// Candidates that survived construction, the FSR cap and composition
  /// admission, i.e. everything the diversity ledger was actually offered.
  int get candidateCount => _candidateCount;

  /// Of those, how many the ledger judged novel.
  int get novelCandidateCount => _novelCandidateCount;

  /// Of the novel ones, how many were retained as in-band candidates — the
  /// pool the comparator then ranks.
  int get acceptedNovelCandidateCount => _acceptedNovelCandidateCount;

  /// Which exit path each shipped level took, by name. A generator whose
  /// boards have stopped varying reads very differently here depending on the
  /// cause: `in-band` with `candidateCount == 1` means nothing else was
  /// produced; `in-band` with a healthy candidate count and
  /// `novelCandidateCount == candidateCount` means the ledger saw plenty and
  /// simply had no reason to prefer a different one.
  Map<String, int> get fallbackReasonCounts =>
      Map<String, int>.unmodifiable(_fallbackReasonCounts);

  void _noteFallbackReason(String reason) =>
      _fallbackReasonCounts[reason] = (_fallbackReasonCounts[reason] ?? 0) + 1;

  void _recordVisualScore(VisualCompositionResult visual,
      {required bool accepted}) {
    // Easy short-circuits to pass() without evaluating the rules, so its
    // filler detail must not be mistaken for a perfect composition.
    if (!visual.evaluated) return;
    final target = accepted ? _visualScoresAccepted : _visualScoresRejected;
    if (target.length >= _kVisualScoreSampleCap) return;
    target.add(visual.score);
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
        // On [maxAttempts] here, rather than a smaller seeded-specific cap:
        // a tight cap looks like the obvious way to bound this path, and the
        // measurement says otherwise. Sniper slots fail construction
        // repeatedly and then *succeed*, at attempt 14 (L100), 15 (L400), 18
        // (L1000) and 19 (L600); an 8-attempt cap would trade six landmarks
        // for latency that is no longer the problem. The multi-second stalls
        // (L725 Hard: 42.5s) came from the shortfall burn below, and capping
        // that at [_kSeedMechanicShortfallRetries] took the same slot to
        // ~2.4s. Anything left here is bounded by attempts that are
        // individually cheap, and [_seedFallthroughCounts] now makes a give-up
        // visible instead of silent. Re-measure with
        // `milestone_seed_audit_test` before bounding this further.
        final seedSalt = seed.seedRng ?? 0;
        // Latency bound for the seeded path. Kept on its own stopwatch rather
        // than shared with the main pipeline below: it must not hand the
        // fall-through pipeline a clock that is already spent (that regressed
        // deadlock_test — the regular path then starts over budget and
        // exhausts its attempts). It only ever *shortens* the seeded search,
        // and only once there is a retained board to ship.
        final seedWatch = timeBudget != null ? (Stopwatch()..start()) : null;
        /// Valid + solvable seeded board that could not seat the level's full
        /// lock/relay budget. Shipping it keeps the milestone's pinned identity
        /// (silhouette, archetype, telemetry seed id); the alternative —
        /// falling through to the procedural pipeline — silently turns the
        /// milestone into an ordinary board, which is how L150 stopped
        /// emitting as `milestone-overload`.
        LevelData? seedMechanicShort;
        _PendingDirectorEmission? seedMechanicShortEmission;
        var shortfalls = 0;
        for (int i = 0; i < maxAttempts; i++) {
          if (seedWatch != null &&
              seedMechanicShort != null &&
              seedWatch.elapsed >= timeBudget!) {
            break;
          }
          _bumpSeed(_seedAttemptCounts, seed.id);
          final rng = Random(primarySeed * 31337 + seedSalt + i);
          final seedResult = _attemptDirectorDrivenGeneration(
            seedConfig,
            rng,
            targetTier: targetTier,
            seed: seed,
            overBudget: seedWatch == null
                ? null
                : () => seedWatch.elapsed >= timeBudget!,
          );
          if (seedResult.isError) {
            _bumpSeed(_seedConstructionFailureCounts, seed.id);
          }
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
                _bumpSeed(_seedMechanicShortfallCounts, seed.id);
                shortfalls++;
                if (shortfalls < _kSeedMechanicShortfallRetries) {
                  // Retry while retries are left — a board that seats the full
                  // budget is the better milestone — but retain the first
                  // shortfall so an exit that never reaches the cap (the
                  // `seedWatch` break, or construction/validation failures for
                  // the remaining attempts) still ships the *seed* rather than
                  // dropping to the procedural pipeline.
                  if (seedMechanicShort == null) {
                    seedMechanicShort = enriched;
                    seedMechanicShortEmission = _pendingEmission;
                  }
                  _discardPendingEmission();
                  continue;
                }
                // Out of retries: ship this board rather than the seed. The
                // discard-and-retry above used to be unconditional, and after
                // `maxAttempts` the whole seeded path fell through to the
                // procedural pipeline — so a milestone that could not seat one
                // lock silently stopped being a milestone at all. A landmark
                // missing a mechanic is a far smaller loss than a landmark that
                // is not there, and `campaign_mechanic_audit_test` only ever
                // asserts `locks <= budget.lockCount`, so a short board is
                // legal by the campaign's own rules.
                //
                // Shipped from *this* attempt while its staged emission is
                // still live, so the seed's telemetry cannot go dark. (The
                // post-loop path ships the retained board instead, and has to
                // restore `_pendingEmission` by hand to get the same effect.)
              }

              _seedEmissionCounts[seed.id] =
                  (_seedEmissionCounts[seed.id] ?? 0) + 1;
              _assertGeneratedLayout(enriched);
              _commitPendingEmission();
              return Result.success(enriched);
            }
            _bumpSeed(_seedValidationFailureCounts, seed.id);
          }
        }
        // Attempts exhausted (or the latency budget ran out) without ever
        // reaching the shortfall cap. Ship the retained seeded board if there
        // is one: a milestone that is one lock short still reads as the
        // milestone, whereas a procedural board does not.
        if (seedMechanicShort != null) {
          _seedEmissionCounts[seed.id] = (_seedEmissionCounts[seed.id] ?? 0) + 1;
          _assertGeneratedLayout(seedMechanicShort);
          _pendingEmission = seedMechanicShortEmission;
          _commitPendingEmission();
          return Result.success(seedMechanicShort);
        }
        // Seed path failed outright (e.g. silhouette starvation on a tiny
        // grid): fall through to the regular pipeline so the level still ships.
        //
        // This is the silent milestone loss: the level generates, the player
        // gets a playable board, and nothing anywhere says the landmark is
        // gone. The counter is what makes it sayable.
        _bumpSeed(_seedFallthroughCounts, seed.id);
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
    // NOTE: this clock deliberately does NOT cover the seeded path above —
    // sharing it regressed deadlock_test, because the regular pipeline then
    // starts already over budget and exhausts its attempts. The seeded path
    // runs the same [timeBudget] on its own stopwatch instead, so a fall-
    // through arrives here with a full clock.
    final budgetWatch = timeBudget != null ? (Stopwatch()..start()) : null;
    /// Valid + solvable, but missed the ideal removal-wave band.
    LevelData? budgetFallback;
    /// Valid + solvable, but short of the level's lock/relay budget. Strictly
    /// worse than [budgetFallback], so only shipped when nothing else exists.
    LevelData? mechanicShortFallback;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final overBudgetNow =
          budgetWatch != null && budgetWatch.elapsed >= timeBudget!;
      final overBudgetShippable = budgetFallback ??
          (allowMechanicShortFallback ? mechanicShortFallback : null);
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
        // F1 — reject a board whose core floor cannot be met, rather than
        // shipping the deepest placement that happened to exist.
        //
        // `_ensureCoreQuality` repicks over three widening rungs and then
        // escalates the core count one at a time up to the mode's `maxCores`.
        // When even that misses, it returns "best seen". On a geometrically
        // flat board that is not a near miss: `medium L236` (16 nodes, 7x7)
        // needs depth 8 and its deepest reachable placement is **3**, so the
        // board shipped as a three-tap win and took F1 red — the same gate
        // this project has already paid for once, in P2.
        //
        // §12 of the plan pre-committed this exact remedy for this exact
        // situation: *"T1.2's bounded repick cannot fix these. Move the remedy
        // upstream into candidate rejection — do not let it silently ship
        // 'best seen'."* The board is not repairable by core placement; the
        // right answer is a different board.
        //
        // Cheap, measured before implementing: **1 of 184** Medium enrichment
        // calls across L1-300 misses the floor, and Hard and Easy never do. So
        // this costs the K-loop essentially nothing, which matters because
        // candidate supply is P2b's binding constraint.
        //
        // Procedural path only. The seeded path at the milestone call site
        // deliberately does not reject: a lost seed is a lost milestone
        // (`seedFallthroughCounts`), and the same asymmetry already applies to
        // the node floor there for the same reason.
        var coreFloorUnmet = false;
        final enriched = _enrichLevel(
          result.value,
          scaledConfig,
          targetTier,
          onCoreSelection: (rec) {
            if (rec.floorAchieved < rec.floorRequired) coreFloorUnmet = true;
          },
        );
        if (coreFloorUnmet) {
          _coreFloorRejects++;
          _discardPendingEmission();
          continue;
        }
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
          //
          // Recorded unconditionally; *consumed* conditionally. The opt-in
          // above governs the over-budget escape only — that is the path whose
          // cost the paragraph above measured. The attempt-exhaustion path at
          // the bottom of this method consumes it for every caller, because
          // there the alternative is not a slightly worse level, it is
          // `Result.error` and a level the player cannot play at all.
          mechanicShortFallback ??= enriched;
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

    // Attempts exhausted. Before surfacing an error, ship anything valid that
    // was retained along the way, ranked worst-acceptable-last:
    //
    //   budgetFallback        — valid, solvable, wave count outside the ideal
    //                           band. A slightly-off level.
    //   mechanicShortFallback — valid, solvable, but could not seat its full
    //                           lock/relay budget. A level missing a mechanic.
    //
    // Both are strictly better than the alternative. This branch used to return
    // `Result.error` outright, and P1 turned that from theoretical into real:
    // raising Medium sector 3+ from two cores to three (T1.3) starves relay
    // placement on the odd cramped board, because `_markSpecialNodes` keeps
    // relays out of *core rows* and three cores occupy three of them. Exactly
    // one level in 1..1500 hit it — **L427 Medium** — and it went from
    // generating fine to not generating at all. A campaign level that cannot be
    // produced is a level the player cannot play, which is a worse defect than
    // any of the ones P1 set out to fix.
    //
    // The typed error is retained for the case where genuinely nothing valid
    // was ever built, so callers can still distinguish "we tried and got
    // something imperfect" from "we got nothing".
    final exhaustedFallback = budgetFallback ?? mechanicShortFallback;
    if (exhaustedFallback != null) {
      _discardPendingEmission();
      _maxAttemptsExhaustedCount++;
      return Result.success(exhaustedFallback);
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

  /// T2.9a — test-only relaxation of the K-loop's CUD floor, in depth units.
  ///
  /// T2.5's mortality table put the CUD floor at **22.3% of Hard iterations**,
  /// the second-largest killer after composition `components`. Whether it is
  /// *safe* to relax is a separate question from whether it is large, and the
  /// T2.8 lesson says measure one variable alone before believing either.
  ///
  /// Zero by default, so the shipped behaviour is untouched and no board
  /// moves. Only `p2b_cud_isolation_report_test.dart` writes it.
  @visibleForTesting
  static int cudFloorRelaxation = 0;

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
    // T2.4c — the composition score of each retained fallback.
    //
    // Before T2.4c, a candidate violating `components` / `singleton` /
    // `occupancy` / `blobVsGrid` never reached these slots at all: it was
    // discarded in the K-loop. Now it can, so "first one found" would let a
    // badly-composed board become the shipped fallback where previously an
    // error or a later attempt would have. Keeping the best-composed instead
    // is what makes softening the rules safe on the paths that have no
    // comparator — it is the same ranking decision the in-band pool gets, and
    // without it T2.4c's p10 floor would be defended on the in-band path only.
    double novelOutOfBandComposition = -1;
    double nonNovelComposition = -1;
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
    // T2.9a — `cudFloorRelaxation` is 0 in every shipped path.
    final cudFloor =
        evaluatorProfile.criticalUnlockDepth.min - cudFloorRelaxation;

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
        _kloopBudgetBreaks += _evaluatorRetryBudget - k;
        break;
      }
      _kloopIterations++;
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
      if (once == null || once.isError) {
        _constructionFailures++;
        continue;
      }

      final level = once.value;
      final metrics = LevelMetrics.compute(level);
      if (!DifficultyProfile.passesFsrCap(metrics)) {
        _evaluatorRejectionCount++;
        _fsrCapRejects++;
        continue;
      }

      final visual = evaluateVisualComposition(level, evaluatorTier);
      // T2.4a — record the composition score for BOTH populations. Shadow mode:
      // the decision below is untouched, this only observes. T2.4b needs the
      // *rejected* distribution as much as the accepted one, and the generator
      // is the only place a rejected candidate is ever visible.
      // Recorded against "no rule failed", NOT against "was admitted".
      // T2.4c widens admission; keeping the split on rule violation is what
      // lets the accepted / rejected distributions in
      // `docs/playtests/composition_calibration.md` stay the same measurement
      // before and after the bundle.
      _recordVisualScore(visual, accepted: visual.reason == null);
      // Per-rule volumes likewise count violations, hard or soft, so the T2.4b
      // reject-reason table remains a like-for-like series.
      _incrementVisualRejectCounter(visual.reason);
      if (!visual.passes) {
        _evaluatorRejectionCount++;
        _compositionHardRejects++;
        if (visual.reason == VisualCompositionRejectReason.aspect) {
          _hardRejectAspect++;
        } else {
          _hardRejectComponents++;
        }
        continue;
      }

      final inBand = evaluatorProfile.passes(metrics) && !visual.softFailed;
      if (!inBand) {
        _evaluatorRejectionCount++;
        _outOfBandNoted++;
        if (metrics.criticalUnlockDepth < cudFloor) {
          _cudFloorRejects++;
          continue;
        }
      }

      _candidateCount++;
      final visible = _visibleMotifsIn(plan, level);
      final dominantMotif = visible.isEmpty ? MotifId.none : visible.first;
      final fingerprint = computeLevelFingerprint(
        level: level,
        metrics: metrics,
        silhouette: plan.silhouette,
        // T2.6 — the *evaluator's* tier, the same one the band and the CUD
        // floor are taken from, so the buckets are cut on the population this
        // candidate is actually judged against. A seed's tier need not match
        // the mode it ships on (the T2.2 lesson), and `evaluatorTier` is the
        // one that already resolves that.
        tier: evaluatorTier,
        dominantMotifId: motifIdFingerprintSlot(dominantMotif),
      );
      final novel =
          !enableDiversityGating || _diversityLedger.isNovel(fingerprint);
      if (novel) _novelCandidateCount++;
      if (!novel) {
        _diversityRejectionCount++;
        // Strictly-better only, so the first candidate still wins ties and the
        // pre-T2.4c "first found" behaviour is preserved whenever composition
        // does not separate them. Note this also fixes an existing
        // inconsistency: `renegotiations` and `telemetry` used `=` while the
        // rest used `??=`, so they described a different candidate than the
        // one retained. The whole record now updates together.
        if (nonNovelFallback == null || visual.score > nonNovelComposition) {
          nonNovelFallback = once;
          nonNovelPlan = plan;
          nonNovelMetrics = metrics;
          nonNovelFp = fingerprint;
          nonNovelRenegotiations = renegotiationsForThisAttempt;
          nonNovelTelemetry = runTelemetry ?? ConstructionTelemetry.zero;
          nonNovelComposition = visual.score;
        }
        continue;
      }

      if (inBand) {
        _acceptedNovelCandidateCount++;
        inBandCandidates.add(_InBandCandidate(
          result: once,
          plan: plan,
          metrics: metrics,
          fingerprint: fingerprint,
          visibleMotifs: visible,
          renegotiations: renegotiationsForThisAttempt,
          constructionTelemetry: runTelemetry ?? ConstructionTelemetry.zero,
          compositionScore: visual.score,
        ));
        continue;
      }
      if (novelOutOfBand == null || visual.score > novelOutOfBandComposition) {
        novelOutOfBand = once;
        novelOutOfBandFp = fingerprint;
        novelOutOfBandMetrics = metrics;
        novelOutOfBandPlan = plan;
        novelOutOfBandRenegotiations = renegotiationsForThisAttempt;
        novelOutOfBandTelemetry = runTelemetry ?? ConstructionTelemetry.zero;
        novelOutOfBandComposition = visual.score;
      }
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
      _noteFallbackReason('in-band');
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

    // T2.9b — yield to the non-novel fallback when this path's candidate is
    // below the composition floor and the fallback's is not.
    //
    // Exit priority is `in-band` > `novel-out-of-band` > `non-novel`, which
    // ranks novelty above the band and above composition. Measured on Medium
    // L1–300, that ordering is backwards on quality — the *last resort* is the
    // best-composed path, because it is the only one that selects purely on
    // composition:
    //
    //   exit path            n    composition p10   below the 0.63 floor
    //   non-novel           76         0.7201              3
    //   in-band            175         0.6016             26
    //   novel-out-of-band   49         0.5615             18
    //
    // 16% of levels were producing 38% of the sub-floor boards. Both paths
    // ship an out-of-band board either way, so the band is not the thing being
    // traded — only novelty is, and only when the novel candidate is
    // measurably badly composed and a better-composed alternative is in hand.
    //
    // Deliberately narrow. It fires only when the novel candidate is *below*
    // the floor and the non-novel one is *above* it; when both are above,
    // below, or the fallback is absent, novelty still wins as before. On Hard
    // it is close to a no-op — 10 levels take this path and none are
    // sub-floor — so it does not spend the DoD's `non-novel` budget on the
    // tier that budget is for.
    if (novelOutOfBand != null && nonNovelFallback != null) {
      final floor = kCompositionFloor[evaluatorTier];
      if (floor != null &&
          novelOutOfBandComposition < floor &&
          nonNovelComposition >= floor) {
        novelOutOfBand = null;
      }
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
      _noteFallbackReason('novel-out-of-band');
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
    // Last resort: emit a non-novel candidate, and DO record it in the ledger.
    //
    // This comment used to claim the opposite — that the emission was not
    // recorded, "keeping the window's all-pairs distance ≥ 5 invariant intact"
    // — while the code twenty lines below recorded anyway, on 286 of 300 Hard
    // levels. T2.8 took the comment at its word and made the code match it,
    // measured in isolation, and the result falsified the idea:
    //
    //   non-novel exits   Hard 286 -> 285   Medium 256 -> 275   Easy 239 -> 264
    //   rankable / level  Hard 0.05 -> 0.05  Medium 0.17 -> 0.13  Easy 0.06 -> 0.04
    //
    // Flat on Hard and worse on both other modes, so it was reverted per the
    // plan's pre-committed rule. The reason it backfires: skipping the record
    // stops the window turning over, so it ages into a set of *older* entries
    // that are no less similar — the eviction churn that occasionally cleared
    // a blocking neighbour is lost, and nothing is gained in exchange.
    //
    // The invariant the old comment named was never real, and the feedback
    // loop it implied is not what starves novelty. The binding constraint is
    // the fingerprint's usable entropy (T2.6/T2.7). Full reading in
    // `docs/playtests/p2b_t28_isolated.md`.
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
      _noteFallbackReason('non-novel');
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
    _noteFallbackReason('exhausted');
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
            compositionScore: c.compositionScore,
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

    // T2.4c — composition, second only to silhouette diversity.
    //
    // Placed high on purpose. This is the term that replaces four hard
    // rejections, and it can only do that job if a well-composed candidate
    // still beats a scattered one when both exist; buried under the Hard
    // metric keys it would almost never break a tie and softening the rules
    // would be a pure loss of quality control.
    //
    // Banded rather than compared raw. The score is an unweighted mean of five
    // continuous terms, so almost every pair separates by *something* at full
    // precision — comparing raw would make composition the de-facto sole sort
    // key and silently retire the tempo, CUD and topology ordering below.
    // [kCompositionRankBand] is the granularity at which two boards genuinely
    // look differently composed; inside one band the existing order decides.
    final compositionBand = _compositionBand(b).compareTo(_compositionBand(a));
    if (compositionBand != 0) return compositionBand;

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

  int _compositionBand(_InBandCandidate c) =>
      (c.compositionScore / kCompositionRankBand).floor();

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
    void Function(CoreSelectionRecord record)? onCoreSelection,
  }) {
    final tier =
        targetTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    return enrichLevel(
      level,
      config,
      tier,
      mechanicOverride: mechanicOverride,
      onCoreSelection: onCoreSelection,
    );
  }

  /// F1 — how many procedural candidates were rejected because no core
  /// placement on that board could reach the mode's tap-depth floor.
  int _coreFloorRejects = 0;
  int get coreFloorRejects => _coreFloorRejects;

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

/// T2.4c — the granularity at which composition scores are treated as
/// different when ranking in-band candidates.
///
/// 0.05 of a 0..1 unweighted mean of five terms, i.e. two candidates must
/// differ by a quarter of a point on one rule (or a spread across several)
/// before composition outranks tempo, CUD and topology. Chosen against the
/// T2.4b distributions: shipped-vs-rejected p50 separation is 0.30 on Medium
/// and 0.24 on Hard, so a real composition difference clears several bands
/// while measurement-level jitter clears none.
const double kCompositionRankBand = 0.05;

/// T2.9b — the composition score below which a board is considered to have
/// missed the quality floor T2.4b calibrated, per tier.
///
/// **Medium 0.577, Hard 0.65** — re-derived by T2.10a. Hard is unchanged; only
/// Medium moved, and the reason is not the one this section originally assumed.
///
/// The old Medium 0.63 was the shipped p10 of L1–300 under the pre-P2b regime.
/// Measured on the *pre-P2b tree* over two later, disjoint windows of the same
/// campaign, it was never met there either:
///
///   Medium p10, pre-P2b :  L1-300 **0.6530**   L301-800 0.6097   L801-1300 0.6246
///   Medium p10, post-P2b:  L1-300 0.6153       L301-800 0.6008   L801-1300 0.6057
///
/// So 0.63 was overfit to the first 300 levels, not merely to the old
/// selection regime — a distinction that only appeared once a fresh corpus was
/// used. P2b's actual cost is **−0.009 to −0.019** on Medium, not the −0.03+ it
/// looked like when only L1–300 was ever measured.
///
/// The new Medium floor is the 2.5th percentile of a 2,000-resample bootstrap
/// of the L301–800 p10 (**0.5880**) less a **0.01** margin — one fifth of
/// `kCompositionRankBand`, so smaller than the granularity at which two boards
/// read as differently composed, and large enough to absorb the corpus-to-
/// corpus noise the interval shows. Validated on the held-out L801–1300 window
/// it did not derive from (p10 0.6057, clears).
///
/// **Hard keeps 0.65 deliberately.** The same derivation proposed 0.657, which
/// would *tighten* the gate as a side effect of recalibrating a different tier
/// — and 0.65 already holds on every post-P2b window (0.6632 / 0.6754 /
/// 0.6654). A recalibration is not a licence to move gates that are passing.
///
/// Derivation and the control run: `docs/playtests/p2b_t210a_recalibration.md`.
///
/// Easy is absent on purpose: `evaluateVisualComposition` short-circuits for
/// Easy, so `compositionScore` there is filler rather than a measurement and
/// ranking on it would sort on noise.
///
/// Used by the `novel-out-of-band` yield (T2.9b) and **not** by the in-band
/// comparator. Placing it there as a lexicographic tier above silhouette
/// diversity was implemented, instrumented and reverted: it fired on 29 of 168
/// Medium comparator calls, and moved the shipped composition p10, p25, min and
/// every funnel number by **zero**. The bottom decile is made of levels where
/// *every* in-band candidate is sub-floor, and a comparator can only reorder
/// what exists. See `docs/playtests/p2b_t29c_floor_tier.md`.
const Map<DifficultyTier, double> kCompositionFloor = {
  DifficultyTier.medium: 0.577,
  DifficultyTier.hard: 0.65,
  DifficultyTier.expert: 0.65,
};

class _InBandCandidate {
  final Result<LevelData, GenerationError> result;
  final GenerationPlan plan;
  final LevelMetrics metrics;
  final LevelFingerprint fingerprint;
  final List<MotifId> visibleMotifs;
  final int renegotiations;
  final ConstructionTelemetry constructionTelemetry;

  /// T2.4c — `VisualCompositionResult.score`, 0..1, higher is better.
  final double compositionScore;

  const _InBandCandidate({
    required this.result,
    required this.plan,
    required this.metrics,
    required this.fingerprint,
    required this.visibleMotifs,
    required this.renegotiations,
    required this.constructionTelemetry,
    required this.compositionScore,
  });
}
