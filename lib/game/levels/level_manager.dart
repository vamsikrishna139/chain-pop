import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../theme/app_colors.dart';
import '../daily_challenge.dart';
import 'level.dart';
import 'generation/generation.dart';

/// Thin adapter that bridges the game engine (which expects a simple
/// `LevelData`) with the [LevelGenerator] Result-based API.
///
/// The manager resolves generation results and always returns a valid
/// [LevelData] — either the generated level or a safe fallback.
class LevelManager {
  static LevelGenerator generator = LevelGenerator.neutral();

  /// Receives the campaign diversity history after each level [getLevel]
  /// serves, so it can be persisted (W2.4). Bootstrap points this at storage;
  /// it stays null in tests, which keeps every generation suite pure.
  ///
  /// Without it the ledger is session-only: novelty reset on every launch, so
  /// a returning player could be served a board they had just played.
  static void Function(List<int> bits)? onDiversityLedgerChanged;

  /// Told about every generation failure that [getLevel] or the Daily papered
  /// over with a fallback board (W2.5). Bootstrap reports it as a Crashlytics
  /// non-fatal plus an analytics event; null in tests. Always invoked on the
  /// calling isolate, including for a Daily generated on a worker isolate.
  static void Function(String kind, int id, String reason)?
      onGenerationFallback;

  /// Seeds [generator]'s diversity ledger from persisted [bits]. Call once at
  /// startup, before the first [getLevel]. Never touches the Daily, which
  /// generates from a fresh generator by contract.
  static void restoreDiversityLedger(List<int> bits) {
    if (bits.isEmpty) return;
    generator.diversityLedger.restore(bits);
  }

  /// Latency budget for on-load campaign generation. A small tail of seeds
  /// otherwise burn the full attempt budget (~1s) chasing the ideal
  /// removal-wave band; past this the generator ships the best valid level it
  /// already found. Bounds the "Building level…" wait without affecting the
  /// common path or the (budget-free) generation test suites.
  static const Duration generationBudget = Duration(milliseconds: 200);

  /// Work budget for the Daily Challenge, in constructions (K-loop iterations
  /// plus renegotiations; see `LevelGenerator.generateFromConfiguration`).
  ///
  /// **Why work, not time (W2.2).** This used to be a 400 ms stopwatch, and the
  /// over-budget escape ships whichever valid board it holds when the clock
  /// trips — so a slow or busy phone shipped a different Daily than a fast one,
  /// breaking "same board for everyone on a date". Counting constructions trips
  /// at the same point on every device.
  ///
  /// **Why 64.** Measured unbounded over all 365 keys of 2027
  /// (`daily_work_budget_probe_test.dart`): p50 17, p90 59, p95 69, p100 172
  /// constructions at ~5.5 ms each on a dev Mac. 64 leaves ~92% of dates
  /// exactly as unbounded generation would make them and caps the tail near
  /// the old 400 ms on desktop. A slower phone takes proportionally longer
  /// instead of getting a different board; that runs in the isolate.
  ///
  /// `null` would mean fully unbounded (40 attempts × 8 K × 4 renegotiations),
  /// which measured 5.5 s on one key before any budget existed.
  static const int dailyWorkBudget = 64;

  /// Gen V2 campaign work budget, in constructions (docs/GEN_V2_PLAN.md).
  /// V2 never uses [generationBudget]: a wall-clock budget lets a slow phone
  /// ship a different board than a fast one for the same level.
  static const int genV2WorkBudget = 48;

  /// Per-mode Gen V2 cut-over: campaign levels with `id >= genV2FromLevel[mode]`
  /// generate with V2. A mode with no entry stays entirely on V1, so tests and
  /// any caller that never ran the bootstrap keep V1 boards.
  ///
  /// Set once at startup from [resolveGenV2FromLevel] and persisted, so a
  /// level a player had already reached keeps the board they saw.
  static final Map<DifficultyMode, int> genV2FromLevel = {};

  /// First Daily date key (yyyymmdd) generated with V2. Earlier dates keep
  /// their V1 board, so a past Daily a player has stars for never changes.
  /// Null = Daily stays on V1.
  static int? genV2DailyFromKey = kGenV2DailyFromKeyDefault;

  /// First Daily on Gen V2: **1 December 2026**. A deliberate choice, not a
  /// placeholder.
  ///
  /// * A month boundary keeps each calendar month on one generator: the
  ///   Daily calendar shows one month at a time, so November is all V1 and
  ///   December all V2 — a player never sees the two styles mixed in a grid.
  /// * It does not depend on release timing. Ship before Dec 1 and the switch
  ///   happens on Dec 1; ship after and every player starts on V2.
  /// * It is not "everyone plays the same board": the build that adds this
  ///   also caps every Daily at one relay (v9 ships 1–3), so updated and
  ///   older builds already differ on any date, November replays included.
  ///   Stars and completed ticks are keyed by date and are unaffected.
  static const int kGenV2DailyLaunchKey = 20261201;

  /// [kGenV2DailyLaunchKey], unless a test build overrides it with
  /// `--dart-define=GEN_V2_DAILY_FROM=yyyymmdd` (device checklist item 7:
  /// play a post-cut-over Daily without touching the device clock). Release
  /// builds pass no define.
  static const int kGenV2DailyFromKeyDefault = int.fromEnvironment(
      'GEN_V2_DAILY_FROM',
      defaultValue: kGenV2DailyLaunchKey);

  /// Where V2 starts for a mode, given what storage knows.
  ///
  /// * [stored] wins whenever present: the cut-over is decided once.
  /// * A player with no progress in the mode (nothing beyond level 1 unlocked
  ///   and no stars on it) gets V2 from level 1.
  /// * Anyone else gets V2 from the first level they have not unlocked yet,
  ///   so every board they could already have seen stays V1.
  static int resolveGenV2FromLevel({
    required int? stored,
    required int highestUnlocked,
    required bool hasProgress,
  }) {
    if (stored != null && stored >= 1) return stored;
    if (!hasProgress) return 1;
    return highestUnlocked + 1;
  }

  /// Generator version for campaign level [levelId] in [mode].
  static int generationVersionFor(int levelId, DifficultyMode? mode) {
    final from = genV2FromLevel[mode ?? DifficultyMode.easy];
    return (from != null && levelId >= from) ? 2 : 1;
  }

  /// Generator version for the Daily on [dayKey].
  static int dailyGenerationVersionFor(int dayKey) {
    final from = genV2DailyFromKey;
    return (from != null && dayKey >= from) ? 2 : 1;
  }

  /// Returns a valid, solvable [LevelData] for [levelId].
  ///
  /// Uses the full generation pipeline from [LevelGenerator]. If generation
  /// fails, or ships a board that breaks the layout invariants, a playable
  /// fallback board is returned and the failure is reported through
  /// [onGenerationFallback] — never thrown, and never assert-only.
  ///
  /// Layout validation runs in release too (W2.5). It used to be assert-only,
  /// so release builds skipped the bounds, duplicate-cell and play-cell checks
  /// entirely; they are cheap next to generation itself.
  static LevelData getLevel(int levelId, {DifficultyMode? mode}) {
    // Serve the board this player already saw for (mode, id). Generation reads
    // the diversity ledger and a wall-clock budget, so regenerating a level —
    // backing out and re-entering, or the menu's Play after an abandon — used
    // to deal a *different* board for the same level number (and let players
    // reroll a hard one). The board just served is also in the ledger, which
    // all but guaranteed the reroll.
    final cacheKey = _servedKey(levelId, mode);
    final cached = _served.remove(cacheKey);
    if (cached != null) {
      _served[cacheKey] = cached; // refresh LRU position
      return cached;
    }
    _lastGenerationFellBack = false;
    final level = _generate(levelId, mode: mode);
    // A fallback board is not "the" level — let the next visit try again.
    if (_lastGenerationFellBack) return level;
    _remember(cacheKey, level);
    return level;
  }

  /// [getLevel] for UI code: Gen V2 boards are generated on a worker isolate.
  ///
  /// **Why.** V2 Hard generation measured p50 263 ms, p95 590 ms, max 1,175 ms
  /// on the emulator — ~3.3× V1, with no wall-clock cap (by design: a work
  /// budget keeps the board device-invariant). On the UI thread that froze the
  /// screen at every level start, and a budget phone is several times slower.
  ///
  /// V2 is a pure function of (levelId, mode) — a fresh generator and a work
  /// budget — so the worker builds exactly the board [getLevel] would. V1 stays
  /// synchronous: it reads and writes the shared, persisted diversity ledger,
  /// which a worker isolate cannot see, and it is time-capped at
  /// [generationBudget].
  ///
  /// The cache lookup, the V1/V2 decision ([genV2FromLevel] is a static the
  /// worker starts without), fallback reporting and the cache write all run on
  /// the calling isolate. If the isolate cannot be spawned, generates in place.
  static Future<LevelData> getLevelAsync(int levelId,
      {DifficultyMode? mode}) async {
    final cacheKey = _servedKey(levelId, mode);
    final cached = _served.remove(cacheKey);
    if (cached != null) {
      _served[cacheKey] = cached;
      return cached;
    }
    if (generationVersionFor(levelId, mode) < 2) {
      return getLevel(levelId, mode: mode);
    }
    // A prefetch for this level may already be running: wait for it rather
    // than building the same board twice.
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    final build = _buildV2(levelId, mode, cacheKey);
    _inFlight[cacheKey] = build;
    try {
      return await build;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  /// The board already served or prefetched for (levelId, mode), or null.
  /// Lets the game screen open a cached level on its first frame instead of
  /// showing "Building level…" for a frame or two.
  static LevelData? cachedLevel(int levelId, {DifficultyMode? mode}) {
    final cacheKey = _servedKey(levelId, mode);
    final cached = _served.remove(cacheKey);
    if (cached != null) _served[cacheKey] = cached; // refresh LRU position
    return cached;
  }

  /// Starts building campaign level [levelId] in the background so it opens
  /// instantly, without "Building level…". Call it for the next level while
  /// the player is on this one.
  ///
  /// Gen V2 only: a V2 board is a pure function of (levelId, mode), so
  /// building it early gives the same board the player would get anyway. V1
  /// boards are not prefetched — generating one records it in the shared
  /// diversity ledger, which would change later boards for a level the player
  /// may never open. Does nothing if the board is cached or already building.
  static void prefetchLevel(int levelId, {DifficultyMode? mode}) {
    if (generationVersionFor(levelId, mode) < 2) return;
    final cacheKey = _servedKey(levelId, mode);
    if (_served.containsKey(cacheKey) || _inFlight.containsKey(cacheKey)) {
      return;
    }
    unawaited(getLevelAsync(levelId, mode: mode).then<void>(
      (_) {},
      onError: (Object e, StackTrace st) =>
          debugPrint('LevelManager: prefetch of $levelId failed: $e\n$st'),
    ));
  }

  /// Campaign boards being built on a worker isolate, by served-cache key.
  static final Map<String, Future<LevelData>> _inFlight = {};

  static Future<LevelData> _buildV2(
      int levelId, DifficultyMode? mode, String cacheKey) async {
    _BoardOutcome outcome;
    try {
      outcome = await Isolate.run(() => _generateV2(levelId, mode));
    } catch (_) {
      outcome = _generateV2(levelId, mode);
    }

    // Another caller may have served this level while the worker ran; keep
    // the first board so a level never changes under the player.
    final raced = _served.remove(cacheKey);
    if (raced != null) {
      _served[cacheKey] = raced;
      return raced;
    }
    final failure = outcome.failure;
    if (failure != null) {
      _reportFallback('campaign', levelId, failure);
      return outcome.level; // a fallback board is not cached
    }
    _remember(cacheKey, outcome.level);
    return outcome.level;
  }

  static void _remember(String cacheKey, LevelData level) {
    _served[cacheKey] = level;
    while (_served.length > servedCacheCapacity) {
      _served.remove(_served.keys.first);
    }
  }

  /// The V2 board for (levelId, mode), plus why it is a fallback if it is.
  /// Touches no mutable statics, so it is safe on a worker isolate.
  static _BoardOutcome _generateV2(int levelId, DifficultyMode? mode) {
    final result = LevelGenerator.neutral().generate(
      levelId,
      mode: mode,
      workBudget: genV2WorkBudget,
      generationVersion: 2,
    );
    final String failure;
    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      if (layoutMsg == null) return (level: level, failure: null);
      failure = 'invalid layout: $layoutMsg';
    } else {
      failure = _describe(result.error);
    }
    return (
      level: fallbackLevel(levelId, mode: mode ?? DifficultyMode.easy),
      failure: failure,
    );
  }

  /// How many recently served campaign boards [getLevel] remembers. Covers any
  /// realistic back-and-forth within a session; the cache is in-memory only.
  static const int servedCacheCapacity = 64;

  /// Insertion-ordered (LRU) map of `mode:id` → the board served for it.
  static final Map<String, LevelData> _served = {};

  // Keyed by generator identity too: swapping [generator] (tests, a future
  // Gen V2 switch) must never serve a board the old generator made.
  // The generator version is part of the key so a cut-over change can never
  // serve a V1 board as V2 or the reverse.
  static String _servedKey(int levelId, DifficultyMode? mode) =>
      '${identityHashCode(generator)}:${(mode ?? DifficultyMode.easy).name}:'
      'v${generationVersionFor(levelId, mode)}:$levelId';

  static bool _lastGenerationFellBack = false;

  /// Drops every remembered board. For tests and progress resets.
  static void clearServedLevels() => _served.clear();

  static LevelData _generate(int levelId, {DifficultyMode? mode}) {
    final version = generationVersionFor(levelId, mode);
    if (version >= 2) {
      // V2 is a pure function of (levelId, mode): a work budget, never the
      // wall clock, and a fresh generator, never the shared one. The shared
      // generator's diversity ledger is persisted and grows with play, so a V2
      // board generated from it changed after every app restart. Measured on
      // Hard L1-150: a fresh generator gives 90 distinct masks vs 95 with the
      // ledger, and the same back-to-back repeat rate (4). The same function
      // runs on the worker isolate in [getLevelAsync].
      final outcome = _generateV2(levelId, mode);
      final failure = outcome.failure;
      if (failure != null) {
        _reportFallback('campaign', levelId, failure);
        _lastGenerationFellBack = true;
      }
      return outcome.level;
    }
    final result = generator.generate(
      levelId,
      mode: mode,
      timeBudget: generationBudget,
    );

    final String failure;
    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      if (layoutMsg == null) {
        onDiversityLedgerChanged?.call(generator.diversityLedger.serialize());
        return level;
      }
      failure = 'invalid layout: $layoutMsg';
    } else {
      failure = _describe(result.error);
    }
    _reportFallback('campaign', levelId, failure);
    _lastGenerationFellBack = true;
    return fallbackLevel(levelId, mode: mode ?? DifficultyMode.easy);
  }

  /// One solvable board per local calendar day; same layout for every player
  /// on that date. Star progress uses [StorageService.saveDailyStars].
  ///
  /// **Prefer [getDailyChallengeAsync] from UI code.** This runs on the calling
  /// isolate, and [dailyWorkBudget] cannot preempt a single retrograde
  /// construction — so on a pathological date key it blocks for seconds. Called
  /// from a tap handler that is exactly an ANR. See [getDailyChallengeAsync].
  static LevelData getDailyChallenge([DateTime? date]) {
    final when = date ?? DateTime.now();
    final dayKey = DailyChallenge.dateKeyLocal(when);
    return _reportDaily(
        dayKey, _generateDaily(dayKey, dailyGenerationVersionFor(dayKey)));
  }

  /// [getDailyChallenge] off the calling isolate.
  ///
  /// **Why this exists.** The Daily budget (then a 400 ms `Stopwatch`, now
  /// [dailyWorkBudget]) lives *outside* the retrograde constructor, so it
  /// bounds outer attempts but cannot interrupt one construction once
  /// started. Measured on key `20260819`: 4.3 s at a 200 ms budget and 4.4 s at 400 ms — identical, and
  /// only three attempts, so the whole cost is inside a single construction.
  /// On a Pixel 8a that produced a real ANR:
  ///
  /// ```
  /// am_anr: com.adbkv.chainpop — Input dispatching timed out
  ///         (MainActivity is not responding. Waited 5001ms for MotionEvent)
  /// ```
  ///
  /// Moving the work to a worker isolate fixes the freeze for *every* date
  /// without touching generation itself, and stays correct when the in-
  /// constructor deadline is eventually added — that work makes this faster,
  /// not redundant, because a 400 ms main-thread block is still a dropped
  /// frame budget.
  ///
  /// **A second bug this closes.** [generator] is static, so the synchronous
  /// path generates the Daily from whatever session state campaign play left in
  /// the diversity ledger and silhouette tracker. Those are *inputs* (see the
  /// T0.0a closure audit), so the Daily was never actually "the same layout for
  /// every player on that date" — it depended on how much the player had
  /// played first. A worker isolate starts from fresh statics, which makes the
  /// board a pure function of `dayKey` and the doc comment above true. Today's
  /// board for a given date may therefore differ from the previous build's;
  /// nothing is keyed to board bytes (stars are stored per `dayKey`), so this
  /// is a one-time, invisible shift.
  ///
  /// Falls back to generating in place if the isolate cannot be spawned, so a
  /// platform without isolate support degrades to the old behaviour rather than
  /// to no Daily at all.
  static Future<LevelData> getDailyChallengeAsync([DateTime? date]) async {
    final when = date ?? DateTime.now();
    final dayKey = DailyChallenge.dateKeyLocal(when);
    // Resolved here: the worker isolate starts from fresh statics.
    final version = dailyGenerationVersionFor(dayKey);
    _DailyOutcome outcome;
    try {
      outcome = await Isolate.run(() => _generateDaily(dayKey, version));
    } catch (_) {
      outcome = _generateDaily(dayKey, version);
    }
    // Reported here, not inside [_generateDaily]: the worker isolate starts
    // from fresh statics, so [onGenerationFallback] is null over there.
    return _reportDaily(dayKey, outcome);
  }

  static LevelData _reportDaily(int dayKey, _DailyOutcome outcome) {
    final failure = outcome.failure;
    if (failure != null) _reportFallback('daily', dayKey, failure);
    return outcome.level;
  }

  /// The Daily board for [dayKey], plus why it is a fallback board if it is.
  static _DailyOutcome _generateDaily(int dayKey, int generationVersion) {
    // The Daily contract is `dayKey -> identical board`, for every player and
    // on every call. It is generated from a **fresh generator**, never the
    // static [generator].
    //
    // [generator] is static and its `DiversityLedger` and
    // `SilhouetteSessionTracker` are mutable session state, which the T0.0a
    // closure audit classifies as generation *inputs*. So the synchronous path
    // produced a board that depended on how much campaign play preceded it —
    // and, because each Daily call also records into that state, two calls for
    // the same date returned different boards.
    //
    // The doc on [getDailyChallengeAsync] already identified this and fixed it
    // for the async path only, by way of a worker isolate starting from fresh
    // statics. The synchronous path — the one `getDailyChallenge` uses and the
    // one the async path falls back to when `Isolate.run` throws — kept the
    // bug, and it was invisible because the novelty gate was unreachable: with
    // `isNovel` almost always false every call fell through to the same
    // last-resort candidate, so the board looked stable. T2.6/T2.7 made the
    // gate reachable and the non-determinism surfaced immediately.
    //
    // A fresh generator is the smallest change that makes the contract hold on
    // both paths, and it makes the isolate an optimisation for latency rather
    // than a correctness requirement.
    // No `timeBudget`: anything wall-clock here makes the board depend on the
    // device. See [dailyWorkBudget].
    final result = LevelGenerator.neutral().generateDailyChallenge(
      dayKey,
      workBudget: dailyWorkBudget,
      generationVersion: generationVersion,
    );

    final String failure;
    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      if (layoutMsg == null) return (level: level, failure: null);
      failure = 'invalid layout: $layoutMsg';
    } else {
      failure = _describe(result.error);
    }
    // The Daily is generated against the Expert band from a Hard config.
    return (
      level: fallbackLevel(dayKey, mode: DifficultyMode.hard),
      failure: failure,
    );
  }

  /// Used when unexpected errors occur during async loads (the caller reports
  /// the underlying failure). Same board as [fallbackLevel].
  static LevelData emergencyFallbackLevel(int levelId,
          {DifficultyMode mode = DifficultyMode.easy}) =>
      fallbackLevel(levelId, mode: mode);

  /// A real, playable board to ship when generation for [levelId] failed.
  ///
  /// Level 1 of [mode], generated from a fresh generator with no budget and
  /// relabelled as [levelId] — the cheapest level of that mode, and the most
  /// exercised one, so it is the board least likely to fail too. Only if that
  /// also fails does the player get the one-node board. It used to be the
  /// one-node board every time: a level that is won with one tap.
  @visibleForTesting
  static LevelData fallbackLevel(int levelId, {required DifficultyMode mode}) {
    try {
      final r = LevelGenerator.neutral().generate(1, mode: mode);
      if (r.isSuccess && LevelData.layoutValidationMessage(r.value) == null) {
        final l = r.value;
        return LevelData(
          levelId: levelId,
          gridWidth: l.gridWidth,
          gridHeight: l.gridHeight,
          nodes: l.nodes,
          playCells: l.playCells,
          portalPairs: l.portalPairs,
          silhouetteId: l.silhouetteId,
        );
      }
    } catch (e, st) {
      debugPrint('LevelManager: fallback generation threw: $e\n$st');
    }
    return _oneNodeBoard(levelId);
  }

  static String _describe(GenerationError e) => '${e.type}: ${e.message}';

  static void _reportFallback(String kind, int id, String reason) {
    debugPrint('LevelManager: $kind $id generation fell back — $reason');
    onGenerationFallback?.call(kind, id, reason);
  }

  /// An absolute last-resort fallback: one node pointing up in an empty grid.
  static LevelData _oneNodeBoard(int levelId) {
    return LevelData(
      levelId: levelId,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [
        NodeData(
          id: 0,
          x: 1,
          y: 3,
          dir: Direction.up,
          color: AppColors.nodeDefault,
          colorSlot: 5,
        ),
      ],
    );
  }
}

typedef _BoardOutcome = ({LevelData level, String? failure});
typedef _DailyOutcome = _BoardOutcome;
