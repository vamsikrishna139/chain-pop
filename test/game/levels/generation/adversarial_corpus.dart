// T0.4 — THE FROZEN ADVERSARIAL CORPUS.
//
// 300 real generated boards, selected exactly once on 2026-08-19 against
// `generationVersion: 1`, and never re-selected. These are checked-in literals.
//
//     The corpus is a scientific instrument. Selection happens exactly once.
//
// ── Why this file exists ────────────────────────────────────────────────────
//
// T0.3 measured F1 at 66% of Medium boards won in <=6 taps, p50 6. A defect
// that large has to have its *shape* measured before the core algorithm is
// touched, because a random corpus cannot tell a real fix from three impostors
// that produce the same headline number:
//
//   * the trivial boards genuinely got deeper cores            -> the fix
//   * node counts grew, so `coreTapDepth` rose while cores      -> F1 intact
//     stayed last-popped                                            and hidden
//   * the whole distribution shifted up                         -> overshoot
//
// Only a per-stratum before/after diff on **identical level ids** separates
// them, and that requires the ids to be frozen before P1 starts.
//
// ── Why selection may never be re-run ───────────────────────────────────────
//
// Severity membership is a function of *current* `tapsToWin`. Re-deriving it
// after P1 would select a different set of boards and destroy the comparison
// while appearing to work perfectly. `adversarial_corpus_selection_test.dart`
// is checked in for provenance, not for reuse.
//
// ── Why the selection is statistically sound ────────────────────────────────
//
// Selecting the worst N cases by a *noisy* measure makes them improve on
// re-measurement even under a no-op change — regression to the mean, which
// fakes a win and invalidates any severity-stratified before/after study. That
// does not apply here: `tapsToWin` is deterministic per
// `(levelId, mode, generationVersion)` under the T0.0 contract, so there is no
// noise to regress. The corpus is only trustworthy because T0.0b passed.
//
// ── Not the same thing as T1.2's adversarial fixtures ───────────────────────
//
// Same adjective, different instrument. This is 300 generated boards answering
// "did the population improve, and where?". T1.2's ~4 hand-built `LevelData`
// answer "can the floor be bypassed?" by forcing each selection path. Both are
// required; the fixtures cannot be pulled forward here because they assert
// against `_ensureCoreQuality`, which T1.2 creates.

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/generation_version.dart';

/// Boards whose **geometry** P1 moved, declared explicitly.
///
/// ── The plan was wrong about this, and the guards are what proved it ────────
///
/// §0.1 of `docs/IMPLEMENTATION_PLAN_V2.md` argued that changing core selection
/// cannot change a board, because `_climaxBandCoreIds` is a pure function of
/// the solved board and draws no randomness. Both halves of that are true; the
/// conclusion does not follow.
///
/// `enrichLevel` runs **inside** the generator's accept/reject loop, and the
/// generator re-validates the *enriched* board before accepting a candidate
/// (`level_generator.dart` — `final enriched = _enrichLevel(...)` immediately
/// followed by `if (!validationResult.isValid) { _discardPendingEmission();
/// continue; }`). Cores steer the mechanics placed around them: locked nodes
/// exclude cores, and relays must avoid core *rows* because a relay can rotate
/// a core into a permanent face-off. So a different core set means a different
/// lock and relay placement, which means a candidate that used to be accepted
/// can now be rejected — and the next attempt produces different geometry.
///
/// Measured over the frozen corpus, P1 moved 42 of 300 boards this way: 34
/// Medium and 8 Hard. Node-count deltas run in **both** directions with a
/// median of 0 and a mean of +0.2, and every Hard board kept its node count
/// exactly, which is what rules out the "node counts inflated so `tapsToWin`
/// rose while cores stayed last-popped" impostor the corpus exists to catch.
/// `captureRate` p50 went 0.58 -> 1.00 over the same population.
///
/// ── Why this is a list and not a relaxed assertion ──────────────────────────
///
/// Turning the drift check off would retire the instrument. Naming the boards
/// keeps it: any board **not** in this set that ever moves is still a failure,
/// and this set is expected to shrink to nothing rather than grow — P2's
/// re-baselining will move geometry deliberately and wholesale, at which point
/// the corpus is re-frozen and this list is deleted, not extended.
///
/// Keyed `levelId/mode` to match `CorpusEntry.key`.
const Set<String> kP1GeometryMovers = {
  // Hard control — all eight kept their node count exactly; only the shipped
  // candidate changed.
  '189/hard', '479/hard', '494/hard', '788/hard',
  '808/hard', '891/hard', '947/hard', '1174/hard',
  // Medium — severity and representative views.
  '268/medium', '303/medium', '304/medium', '319/medium',
  '323/medium', '326/medium', '391/medium', '403/medium',
  '443/medium', '482/medium', '489/medium', '503/medium',
  '521/medium', '531/medium', '548/medium', '550/medium',
  '556/medium', '572/medium', '580/medium', '581/medium',
  '593/medium', '632/medium', '713/medium', '762/medium',
  '861/medium', '882/medium', '886/medium', '942/medium',
  '998/medium', '1206/medium', '1274/medium', '1365/medium',
  '1411/medium', '1493/medium',
};

/// Boards the milestone-seed fix moved, 2026-08-20. Same contract as
/// [kP1GeometryMovers]: named, not exempted by a relaxed assertion, and any
/// board outside this set that moves is still a failure.
///
/// Eleven of the 300 frozen ids sit on milestone slots; two moved, and both are
/// the fix doing exactly what it was written to do.
///
/// **550/medium — 16 -> 27 nodes.** The overload milestone. Its seeded path
/// used to spend all 40 attempts failing to seat the full lock/relay budget and
/// then fall through to the ordinary procedural pipeline, so the board measured
/// here was never the milestone at all — it was whatever the fallback produced.
/// The node count is the tell: 16 nodes is a procedural Medium board, 27 is the
/// overload seed's own target. The ceiling moves with it (16 -> 24) because it
/// is a different board, not a re-scored one.
///
/// **1225/medium — 23 -> 21 nodes.** The diamond milestone, same mechanism.
///
/// The other nine milestone ids in the corpus were already emitting their seed
/// (sector 1, or slots whose budget seats on the first attempt) and did not
/// move — including 950/medium, which was expected to and did not.
///
/// Keyed `levelId/mode` to match `CorpusEntry.key`.
const Set<String> kMilestoneSeedFixMovers = {
  '550/medium', '1225/medium',
};

/// Shape of this corpus definition — bump when the entry schema changes.
const int kAdversarialCorpusVersion = 1;

/// The `generationVersion` the corpus was frozen against.
///
/// Freezing is keyed on `(levelId, mode, generationVersion)`, **not `levelId`
/// alone**: a future `generationVersion: 2` re-rolls content, so it must not be
/// allowed to silently redefine which board a frozen id means. Asserted by
/// `adversarial_corpus_guards_test.dart` rather than left as a comment.
const int kAdversarialCorpusGenerationVersion = 1;

/// Seed of the ~600-board Medium pool the severity view was drawn from.
/// Disjoint from `kReportSampleSeed` (20260813), so the T0.3 canary's 100 ids
/// remain a genuine held-out set — see `kAdversarialCorpusIsDisjointFromCanary`
/// in the guards test.
const int kAdversarialPoolSeed = 20260819;

/// Boards measured to build the severity quintiles.
const int kAdversarialPoolSize = 600;

/// The three views. Each answers a different question, and the corpus is
/// useless without all three.
enum CorpusView {
  /// 100 Medium boards, 20 from each empirical `tapsToWin` quintile.
  /// Answers: did we fix the disease?
  mediumSeverity,

  /// 100 Medium boards drawn uniformly over L1-1500, unfiltered.
  /// Answers: did we bloat the patient?
  ///
  /// A plain uniform draw is deliberate. `sector` is a pure function of
  /// `levelId` via `worldForLevel`, so uniform sampling reproduces campaign
  /// sector prevalence by construction; explicit sector stratification could
  /// only distort it.
  mediumRepresentative,

  /// 100 Hard boards drawn uniformly. An over-correction control, and **never
  /// an optimisation target** — Hard measures healthy today and shares
  /// `_markCoreNodes` with Medium, so P1 can break it.
  hardControl,
}

/// One frozen board.
class CorpusEntry {
  const CorpusEntry(
    this.levelId,
    this.mode,
    this.view, {
    this.quintile = 0,
    this.severityRank = 0,
    this.freezeTaps = 0,
    this.freezeNodes = 0,
  });

  final int levelId;
  final DifficultyMode mode;
  final CorpusView view;

  /// 1..5 for the severity view, 0 elsewhere. 1 is the shallowest quintile.
  final int quintile;

  /// 1-based rank of this board's `tapsToWin` within the 600-board selection
  /// pool at freeze time; 1 is the shallowest board seen. 0 outside the
  /// severity view. Recorded so a post-P1 diff can be ordered by how bad the
  /// board was, independently of which quintile it landed in.
  final int severityRank;

  /// `tapsToWin` observed **during selection**, in the selection sweep. 0 where
  /// not recorded (the representative and Hard views were drawn uniformly and
  /// first generated by the baseline run).
  ///
  /// Documentation, and a cross-check: it is expected to move in P1. The
  /// machine-readable baseline is the CSV.
  final int freezeTaps;

  /// Node count observed during selection. Unlike [freezeTaps] this is a P1
  /// **invariant** — `budget.coreCount` is consumed only post-generation, so no
  /// part of P1 can move a node count. It is asserted against the baseline in
  /// `adversarial_corpus_baseline_test.dart`, which is how the corpus proves
  /// its own order-independence: the selection sweep and the corpus sweep visit
  /// these ids in completely different orders, and a shared generator instance
  /// would make the two disagree.
  final int freezeNodes;

  String get key => '$levelId/${mode.name}';

  /// `(levelId, mode, generationVersion)` — the full freeze key.
  String get freezeKey => '$levelId/${mode.name}/v$kGenerationVersion';
}

/// Empirical `tapsToWin` quintile boundaries at freeze time.
///
/// Cuts are **rank-based**, not value-based: with 66% of Medium at <=6 taps the
/// value distribution is dominated by ties, so value cuts would leave quintiles
/// empty and the n=20 requirement unmeetable. Adjacent quintiles therefore
/// share a boundary value (Q1 ends at 4 and Q2 begins at 4); the split inside a
/// tied value is by ascending `levelId`, which is stable and independent of
/// everything P1 touches.
class QuintileBounds {
  const QuintileBounds(
    this.quintile, {
    required this.minTaps,
    required this.maxTaps,
    required this.poolCount,
  });

  final int quintile;
  final int minTaps;
  final int maxTaps;
  final int poolCount;
}

/// Recorded at freeze time. Never recomputed — see the file header.
const List<QuintileBounds> kQuintileBoundsAtFreeze = [
  QuintileBounds(1, minTaps: 2, maxTaps: 4, poolCount: 120),
  QuintileBounds(2, minTaps: 4, maxTaps: 5, poolCount: 120),
  QuintileBounds(3, minTaps: 5, maxTaps: 6, poolCount: 120),
  QuintileBounds(4, minTaps: 6, maxTaps: 8, poolCount: 120),
  QuintileBounds(5, minTaps: 8, maxTaps: 28, poolCount: 120),
];

/// Every frozen board, in view order.
///
/// No sector filter and no core-count filter, anywhere. The earlier sketch in
/// `docs/playtests/T0_EXIT_GATE.md` restricted Medium to "boards with cores,
/// sectors 3+". That filter is a bug: T0.3 found the shallowest boards are
/// overwhelmingly sector 2, single-core, and Medium sector 2 keeps
/// `coreCount: 1` after T1.3 — so those boards are fixed by T1.1/T1.2 or not at
/// all, and a corpus that excludes them cannot see the fix. The eligible
/// population is every board that can ship to a player.
const List<CorpusEntry> kAdversarialCorpus = [
  CorpusEntry(130, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 1, freezeTaps: 2, freezeNodes: 14),  // S2 cores=1
  CorpusEntry(261, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 93, freezeTaps: 4, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(507, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 116, freezeTaps: 4, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(132, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 2, freezeTaps: 2, freezeNodes: 19),  // S2 cores=1
  CorpusEntry(263, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 63, freezeTaps: 3, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(516, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 117, freezeTaps: 4, freezeNodes: 14),  // S5 cores=2
  CorpusEntry(133, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 3, freezeTaps: 2, freezeNodes: 15),  // S2 cores=1
  CorpusEntry(268, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 94, freezeTaps: 4, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(526, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 118, freezeTaps: 4, freezeNodes: 18),  // S5 cores=2
  CorpusEntry(134, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 41, freezeTaps: 3, freezeNodes: 14),  // S2 cores=1
  CorpusEntry(303, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 95, freezeTaps: 4, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(541, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 119, freezeTaps: 4, freezeNodes: 18),  // S5 cores=2
  CorpusEntry(135, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 88, freezeTaps: 4, freezeNodes: 21),  // S2 cores=1
  CorpusEntry(320, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 96, freezeTaps: 4, freezeNodes: 16),  // S3 cores=2
  CorpusEntry(548, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 120, freezeTaps: 4, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(138, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 89, freezeTaps: 4, freezeNodes: 15),  // S2 cores=1
  CorpusEntry(323, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 97, freezeTaps: 4, freezeNodes: 18),  // S3 cores=2
  CorpusEntry(667, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 65, freezeTaps: 3, freezeNodes: 13),  // S6 cores=2
  CorpusEntry(139, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 4, freezeTaps: 2, freezeNodes: 16),  // S2 cores=1
  CorpusEntry(326, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 1, severityRank: 64, freezeTaps: 3, freezeNodes: 16),  // S3 cores=2
  CorpusEntry(154, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 218, freezeTaps: 5, freezeNodes: 21),  // S2 cores=1
  CorpusEntry(258, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 221, freezeTaps: 5, freezeNodes: 16),  // S3 cores=2
  CorpusEntry(550, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 121, freezeTaps: 4, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(200, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 219, freezeTaps: 5, freezeNodes: 25),  // S2 cores=1
  CorpusEntry(269, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 222, freezeTaps: 5, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(556, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 122, freezeTaps: 4, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(219, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 220, freezeTaps: 5, freezeNodes: 18),  // S2 cores=1
  CorpusEntry(271, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 223, freezeTaps: 5, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(562, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 123, freezeTaps: 4, freezeNodes: 16),  // S5 cores=2
  CorpusEntry(1142, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 178, freezeTaps: 4, freezeNodes: 22),  // S2 cores=1
  CorpusEntry(304, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 224, freezeTaps: 5, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(572, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 124, freezeTaps: 4, freezeNodes: 13),  // S5 cores=2
  CorpusEntry(1149, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 179, freezeTaps: 4, freezeNodes: 22),  // S2 cores=1
  CorpusEntry(307, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 225, freezeTaps: 5, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(580, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 125, freezeTaps: 4, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(1151, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 180, freezeTaps: 4, freezeNodes: 16),  // S2 cores=1
  CorpusEntry(311, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 226, freezeTaps: 5, freezeNodes: 13),  // S3 cores=2
  CorpusEntry(587, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 126, freezeTaps: 4, freezeNodes: 17),  // S5 cores=2
  CorpusEntry(1181, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 181, freezeTaps: 4, freezeNodes: 15),  // S2 cores=1
  CorpusEntry(313, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 2, severityRank: 227, freezeTaps: 5, freezeNodes: 20),  // S3 cores=2
  CorpusEntry(230, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 323, freezeTaps: 6, freezeNodes: 14),  // S2 cores=1
  CorpusEntry(266, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 324, freezeTaps: 6, freezeNodes: 20),  // S3 cores=2
  CorpusEntry(501, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 245, freezeTaps: 5, freezeNodes: 22),  // S5 cores=2
  CorpusEntry(1146, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 301, freezeTaps: 5, freezeNodes: 21),  // S2 cores=1
  CorpusEntry(272, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 325, freezeTaps: 6, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(503, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 341, freezeTaps: 6, freezeNodes: 14),  // S5 cores=2
  CorpusEntry(1199, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 302, freezeTaps: 5, freezeNodes: 18),  // S2 cores=1
  CorpusEntry(310, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 326, freezeTaps: 6, freezeNodes: 20),  // S3 cores=2
  CorpusEntry(504, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 342, freezeTaps: 6, freezeNodes: 21),  // S5 cores=2
  CorpusEntry(1229, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 303, freezeTaps: 5, freezeNodes: 21),  // S2 cores=1
  CorpusEntry(322, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 327, freezeTaps: 6, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(508, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 343, freezeTaps: 6, freezeNodes: 17),  // S5 cores=2
  CorpusEntry(324, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 328, freezeTaps: 6, freezeNodes: 15),  // S3 cores=2
  CorpusEntry(514, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 246, freezeTaps: 5, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(329, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 329, freezeTaps: 6, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(515, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 344, freezeTaps: 6, freezeNodes: 21),  // S5 cores=2
  CorpusEntry(356, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 330, freezeTaps: 6, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(521, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 345, freezeTaps: 6, freezeNodes: 22),  // S5 cores=2
  CorpusEntry(378, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 331, freezeTaps: 6, freezeNodes: 19),  // S4 cores=2
  CorpusEntry(522, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 3, severityRank: 346, freezeTaps: 6, freezeNodes: 18),  // S5 cores=2
  CorpusEntry(1178, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 387, freezeTaps: 6, freezeNodes: 17),  // S2 cores=1
  CorpusEntry(256, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 458, freezeTaps: 8, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(505, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 420, freezeTaps: 7, freezeNodes: 15),  // S5 cores=2
  CorpusEntry(265, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 459, freezeTaps: 8, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(511, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 464, freezeTaps: 8, freezeNodes: 22),  // S5 cores=2
  CorpusEntry(283, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 406, freezeTaps: 7, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(513, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 421, freezeTaps: 7, freezeNodes: 21),  // S5 cores=2
  CorpusEntry(284, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 407, freezeTaps: 7, freezeNodes: 14),  // S3 cores=2
  CorpusEntry(534, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 465, freezeTaps: 8, freezeNodes: 18),  // S5 cores=2
  CorpusEntry(291, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 408, freezeTaps: 7, freezeNodes: 15),  // S3 cores=2
  CorpusEntry(544, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 466, freezeTaps: 8, freezeNodes: 14),  // S5 cores=2
  CorpusEntry(380, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 409, freezeTaps: 7, freezeNodes: 20),  // S4 cores=2
  CorpusEntry(546, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 422, freezeTaps: 7, freezeNodes: 21),  // S5 cores=2
  CorpusEntry(386, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 410, freezeTaps: 7, freezeNodes: 18),  // S4 cores=2
  CorpusEntry(549, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 467, freezeTaps: 8, freezeNodes: 20),  // S5 cores=2
  CorpusEntry(391, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 460, freezeTaps: 8, freezeNodes: 15),  // S4 cores=2
  CorpusEntry(598, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 423, freezeTaps: 7, freezeNodes: 20),  // S5 cores=2
  CorpusEntry(399, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 461, freezeTaps: 8, freezeNodes: 20),  // S4 cores=2
  CorpusEntry(605, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 424, freezeTaps: 7, freezeNodes: 16),  // S5 cores=2
  CorpusEntry(403, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 4, severityRank: 462, freezeTaps: 8, freezeNodes: 21),  // S4 cores=2
  CorpusEntry(1, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 504, freezeTaps: 12, freezeNodes: 12),  // S1 cores=0
  CorpusEntry(306, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 484, freezeTaps: 9, freezeNodes: 21),  // S3 cores=2
  CorpusEntry(616, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 486, freezeTaps: 9, freezeNodes: 17),  // S5 cores=2
  CorpusEntry(2, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 496, freezeTaps: 10, freezeNodes: 10),  // S1 cores=0
  CorpusEntry(340, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 497, freezeTaps: 10, freezeNodes: 17),  // S3 cores=2
  CorpusEntry(660, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 487, freezeTaps: 9, freezeNodes: 22),  // S6 cores=2
  CorpusEntry(4, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 506, freezeTaps: 13, freezeNodes: 13),  // S1 cores=0
  CorpusEntry(443, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 485, freezeTaps: 9, freezeNodes: 18),  // S4 cores=2
  CorpusEntry(677, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 488, freezeTaps: 9, freezeNodes: 22),  // S6 cores=2
  CorpusEntry(7, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 586, freezeTaps: 22, freezeNodes: 22),  // S1 cores=0
  CorpusEntry(1255, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 494, freezeTaps: 9, freezeNodes: 19),  // S3 cores=2
  CorpusEntry(713, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 489, freezeTaps: 9, freezeNodes: 20),  // S6 cores=2
  CorpusEntry(8, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 508, freezeTaps: 14, freezeNodes: 14),  // S1 cores=0
  CorpusEntry(1269, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 495, freezeTaps: 9, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(742, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 498, freezeTaps: 10, freezeNodes: 19),  // S6 cores=2
  CorpusEntry(13, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 555, freezeTaps: 18, freezeNodes: 18),  // S1 cores=0
  CorpusEntry(1272, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 500, freezeTaps: 10, freezeNodes: 22),  // S3 cores=2
  CorpusEntry(784, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 490, freezeTaps: 9, freezeNodes: 22),  // S7 cores=2
  CorpusEntry(16, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 556, freezeTaps: 18, freezeNodes: 18),  // S1 cores=0
  CorpusEntry(1411, DifficultyMode.medium, CorpusView.mediumSeverity, quintile: 5, severityRank: 481, freezeTaps: 8, freezeNodes: 17),  // S4 cores=2

  // ── medium representative — uniform over L1-1500, unfiltered ──────
  CorpusEntry(35, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(36, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(64, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(73, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(95, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(98, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(120, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(156, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(163, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(167, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(174, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(180, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(190, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(207, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(237, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(252, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(275, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(319, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(328, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(353, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(384, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(395, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(400, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(412, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(421, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(431, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(440, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(454, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(456, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(460, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(480, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(482, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(489, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(530, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(531, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(537, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(539, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(540, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(543, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(581, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(593, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(632, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(653, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(658, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(666, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(683, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(734, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(741, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(754, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(762, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(766, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(770, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(777, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(831, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(844, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(860, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(861, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(880, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(882, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(886, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(906, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(928, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(931, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(942, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(949, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(990, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(991, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(998, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1011, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1022, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1031, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1039, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1061, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1093, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1108, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1121, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1126, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1160, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1161, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1168, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1183, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1204, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1206, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1212, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1215, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1225, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1227, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1252, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1274, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1286, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1316, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1365, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1373, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1375, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1383, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1409, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1434, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1446, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1492, DifficultyMode.medium, CorpusView.mediumRepresentative),
  CorpusEntry(1493, DifficultyMode.medium, CorpusView.mediumRepresentative),

  // ── hard control — uniform; never an optimisation target ──────────
  CorpusEntry(3, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(11, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(23, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(28, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(65, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(99, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(100, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(105, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(117, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(125, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(131, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(144, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(173, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(179, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(182, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(189, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(197, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(199, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(203, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(208, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(211, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(214, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(242, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(243, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(246, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(286, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(341, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(346, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(347, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(354, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(381, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(451, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(452, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(457, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(467, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(476, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(479, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(481, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(483, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(494, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(545, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(547, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(558, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(579, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(582, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(595, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(609, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(636, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(639, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(643, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(652, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(669, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(685, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(698, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(726, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(737, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(745, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(756, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(764, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(772, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(788, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(790, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(805, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(808, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(833, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(836, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(856, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(857, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(874, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(891, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(902, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(939, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(947, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(950, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(969, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1000, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1002, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1045, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1046, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1056, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1069, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1102, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1171, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1174, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1179, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1184, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1202, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1216, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1232, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1259, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1270, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1300, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1335, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1341, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1351, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1381, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1419, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1436, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1470, DifficultyMode.hard, CorpusView.hardControl),
  CorpusEntry(1498, DifficultyMode.hard, CorpusView.hardControl),
];

/// The frozen boards of one view, in declaration order.
List<CorpusEntry> corpusView(CorpusView view) =>
    [for (final e in kAdversarialCorpus) if (e.view == view) e];

/// The severity boards of one quintile.
List<CorpusEntry> corpusQuintile(int quintile) => [
      for (final e in kAdversarialCorpus)
        if (e.view == CorpusView.mediumSeverity && e.quintile == quintile) e,
    ];
