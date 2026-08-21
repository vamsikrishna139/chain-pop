// T1.2 — the core-quality floor, and the proof that it is a *choke point*
// rather than a check placed beside one of the escape hatches.
//
// See docs/IMPLEMENTATION_PLAN_V2.md §0.3 and §T1.2. There are two
// descending-id fallbacks in `level_enrichment.dart` — one at the end of
// `_climaxBandCoreIds`, one in `_markCoreNodes` — and both produce
// last-popped cores on exactly the adversarial boards that most need a floor.
// A test that only exercises the happy path does not test this fix, so every
// fixture below is built to force a specific selection path, and the invariant
// is asserted on all of them.
//
// **The invariant, stated exactly.** The floor cannot promise more depth than a
// board physically contains: a six-node board cannot produce a seven-tap win
// however the cores are placed. So what is asserted is
//
//     coreTapDepth >= mode floor
//       OR coreTapDepth == the board's achievable-depth ceiling
//
// i.e. the choke point either clears the floor or captures *everything the
// geometry offers*. `captureRate == 1.0` on a board that cannot reach the floor
// is a correct outcome; anything less is the selector failing, and that is what
// this test catches. The ceiling comes from `core_depth_ceiling.dart`, the same
// instrument the frozen corpus scores `captureRate` with.

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'core_depth_ceiling.dart';

LevelConfiguration _config(int levelId, DifficultyMode mode, int w, int h) =>
    LevelConfiguration(
      levelId: levelId,
      gridWidth: w,
      gridHeight: h,
      targetNodeCount: 12,
      difficulty: DifficultyParameters(
        mode: mode,
        minChainLength: 2,
        maxChainLength: 6,
        densityFactor: 0.25,
        minNodes: 4,
        maxNodes: 24,
      ),
    );

/// A column of up-pointing nodes is a *total order* of prerequisites: the node
/// at `y` is blocked by every node above it, so its closure is exactly
/// `{0..y}`. That makes closure size — the quantity T1.1's band now measures —
/// directly constructible, which is the only way to aim a fixture at a chosen
/// band slice.
List<NodeData> _column({
  required int x,
  required int length,
  required int firstId,
}) =>
    [
      for (var y = 0; y < length; y++)
        NodeData(id: firstId + y, x: x, y: y, dir: Direction.up),
    ];

LevelData _level(int id, int w, int h, List<NodeData> nodes) => LevelData(
      levelId: id,
      gridWidth: w,
      gridHeight: h,
      nodes: nodes,
    );

/// Runs `enrichLevel` and returns the core-selection record it emitted, so the
/// assertions can see which path fired and what the choke point did about it.
({CoreSelectionRecord record, LevelData enriched}) _enrich(
  LevelData level,
  DifficultyMode mode,
  DifficultyTier tier, {
  MechanicBudgetOverride? override,
}) {
  final records = <CoreSelectionRecord>[];
  CoreSelectionTelemetry.sink = records.add;
  try {
    final enriched = enrichLevel(
      level,
      _config(level.levelId, mode, level.gridWidth, level.gridHeight),
      tier,
      mechanicOverride: override,
    );
    expect(records, hasLength(1),
        reason: 'enrichLevel must make exactly one core-selection decision');
    return (record: records.single, enriched: enriched);
  } finally {
    CoreSelectionTelemetry.sink = null;
  }
}

/// The invariant. Applied to every fixture regardless of which path produced
/// the cores — that is the whole point of a choke point.
void expectFloorInvariant(
  CoreSelectionRecord record,
  LevelData enriched, {
  required String because,
}) {
  expect(record.floorRequired, greaterThan(0),
      reason: '$because: the choke point did not run — a selection path '
          'reached the board without passing `_ensureCoreQuality`');

  if (record.floorMet) return;

  final ceiling = computeCoreDepthCeiling(enriched);
  expect(ceiling.exhaustive, isTrue);
  expect(
    record.floorAchieved,
    equals(ceiling.ceilingTapDepth),
    reason: '$because: the board fell short of its floor '
        '(${record.floorAchieved} < ${record.floorRequired}) *and* left depth '
        'on the table (ceiling ${ceiling.ceilingTapDepth}). A board may only '
        'ship under the floor when its geometry cannot do better.',
  );
}

void main() {
  tearDown(() => CoreSelectionTelemetry.sink = null);

  group('T1.2 floor — all four selection paths converge on one choke point',
      () {
    test('strict band arc: two parallel chains, cores one per band third', () {
      // Two eight-long chains three columns apart. Closure sizes run 1..8 in
      // each, so each third of the strict band has candidates in both columns
      // and the `spreadOk >= 2` rule can always be satisfied by switching
      // column — the conditions pass 1 was designed for.
      final level = _level(2600, 6, 8, [
        ..._column(x: 0, length: 8, firstId: 0),
        ..._column(x: 3, length: 8, firstId: 8),
      ]);

      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);
      expect(r.record.path, CoreSelectionPath.strictBandArc);
      expect(r.record.repickRungs, 0,
          reason: 'a healthy board must not enter the repick loop at all');
      expectFloorInvariant(r.record, r.enriched, because: 'strict band arc');
    });

    test('relaxed band: a single chain, where spread forces the widened band',
        () {
      // One twelve-long chain. Every candidate is in the same column, so the
      // Manhattan spread rule rejects neighbours and the strict band cannot
      // seat three cores — pass 3 has to widen.
      final level = _level(2601, 4, 12, _column(x: 0, length: 12, firstId: 0));

      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);
      expect(r.record.path, CoreSelectionPath.relaxedBand);
      expectFloorInvariant(r.record, r.enriched, because: 'relaxed band');
    });

    test('hatch #1 — legacy fallback inside the band selector', () {
      // Six nodes: after the spread rule there are never three in-band guarded
      // candidates, so `_climaxBandCoreIds` clears its picks and returns the
      // three highest ids — the last-popped cores that are F1 itself.
      final level = _level(2602, 4, 6, _column(x: 0, length: 6, firstId: 0));

      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);
      expect(r.record.path, CoreSelectionPath.legacyFallback,
          reason: 'this fixture exists to force hatch #1');
      expectFloorInvariant(r.record, r.enriched, because: 'hatch #1');
    });

    test('no depth at all — every node exits immediately', () {
      // Eight left-pointing nodes, one per row: no ray crosses another node, so
      // every closure is a singleton and percentile bands are meaningless.
      // `_markCoreNodes` short-circuits to the legacy picks — and the choke
      // point must still run on them.
      final level = _level(2603, 6, 8, [
        for (var y = 0; y < 8; y++)
          NodeData(id: y, x: 0, y: y, dir: Direction.left),
      ]);

      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);
      expect(r.record.path, CoreSelectionPath.legacyNoWaveDepth);
      expect(r.record.floorMet, isFalse,
          reason: 'a board with no prerequisite structure cannot reach a '
              'seven-tap floor — the point is that it is not silently ignored');
      expectFloorInvariant(r.record, r.enriched, because: 'no wave depth');
    });
  });

  group('T1.2 escalation — the declared behaviour for boards that fall short',
      () {
    test('a flat Medium board gains a core rather than shipping trivially', () {
      // Four short chains: the deepest single node is only three taps deep, so
      // no *one* core can reach a Medium floor. Two or three can. This is the
      // T0.4§d "geometrically unfixable at the nominal count" case, and the
      // declared remedy is one extra core, not a silent "best seen".
      final level = _level(2604, 8, 4, [
        ..._column(x: 0, length: 3, firstId: 0),
        ..._column(x: 2, length: 3, firstId: 3),
        ..._column(x: 4, length: 3, firstId: 6),
        ..._column(x: 6, length: 3, firstId: 9),
      ]);

      final r = _enrich(
        level,
        DifficultyMode.medium,
        DifficultyTier.medium,
        override: const MechanicBudgetOverride(coreCount: 1),
      );

      expect(r.record.requested, 1);
      expect(r.record.escalated, isTrue,
          reason: 'one core cannot reach the floor on this geometry');
      expect(r.record.selected, greaterThan(1));
      expect(r.record.floorMet, isTrue);
      expectFloorInvariant(r.record, r.enriched, because: 'escalation');
    });

    test('escalation never fires when the nominal count already clears', () {
      final level = _level(2605, 6, 8, [
        ..._column(x: 0, length: 8, firstId: 0),
        ..._column(x: 3, length: 8, firstId: 8),
      ]);

      final r = _enrich(
        level,
        DifficultyMode.medium,
        DifficultyTier.medium,
        override: const MechanicBudgetOverride(coreCount: 1),
      );

      expect(r.record.escalated, isFalse);
      expect(r.record.selected, 1);
      expect(r.record.floorMet, isTrue);
    });

    test('Hard can never escalate — its nominal count is already the cap', () {
      final level = _level(2606, 4, 6, _column(x: 0, length: 6, firstId: 0));
      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);
      expect(r.record.requested, 3);
      expect(r.record.escalated, isFalse);
      expect(r.record.selected, 3,
          reason: 'P1 must not change how many cores Hard ships');
    });
  });

  group('T1.1 — the band measures tap depth, not wave depth', () {
    test('cores land mid-chain, not at the end', () {
      final level = _level(2607, 4, 12, _column(x: 0, length: 12, firstId: 0));
      final r = _enrich(level, DifficultyMode.hard, DifficultyTier.hard);

      final coreIds = [
        for (final n in r.enriched.nodes)
          if (n.isCore) n.id,
      ]..sort();

      // In an up-pointing column, id == y == depth - 1, so "the cores are the
      // last-popped nodes" is literally `coreIds == [9, 10, 11]`. That is what
      // the pre-T1.1 fallback produced on this board.
      expect(coreIds, isNot(equals([9, 10, 11])));
      expect(coreIds.last, lessThan(11),
          reason: 'the deepest core must not be the final node of the chain');
    });
  });
}
