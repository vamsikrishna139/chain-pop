import 'package:chain_pop/game/levels/generation/diversity_ledger.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

LevelMetrics _metrics({
  required int waveDepth,
  required double avgBF,
  required int firstLegal,
  required int cud,
  required double fsr,
}) {
  return LevelMetrics(
    nodeCount: 18,
    waveDepth: waveDepth,
    averageBranchingFactor: avgBF,
    firstLegalMoveCount: firstLegal,
    criticalUnlockDepth: cud,
    forcedSequenceRatio: fsr,
    frontierVariance: 0.0,
    tempoProfile: const [],
    viablePathCount: -1,
    viablePathCountCapped: false,
  );
}

LevelData _level({
  required List<NodeData> nodes,
  int gridWidth = 6,
  int gridHeight = 6,
}) {
  return LevelData(
    levelId: 0,
    gridWidth: gridWidth,
    gridHeight: gridHeight,
    nodes: nodes,
  );
}

void main() {
  group('LevelFingerprint bit layout', () {
    test('silhouetteId occupies the low 3 bits', () {
      final m = _metrics(
        waveDepth: 1,
        avgBF: 1.0,
        firstLegal: 1,
        cud: 1,
        fsr: 0.0,
      );
      final level = _level(nodes: []);
      for (final s in SilhouetteId.values) {
        final fp = computeLevelFingerprint(
          level: level,
          metrics: m,
          silhouette: s,
        );
        expect(fp.bits & 0x07, equals(s.index));
      }
    });

    test('distanceTo uses Hamming distance on the packed integer', () {
      const a = LevelFingerprint(0);
      const b = LevelFingerprint(0x07); // 3 low bits set
      expect(a.distanceTo(b), equals(3));
    });

    test('directionHistogram bit fires when a direction exceeds 30%', () {
      // 5 nodes; 4 point up (80%), 1 left.
      final nodes = <NodeData>[
        for (var i = 0; i < 4; i++)
          NodeData(id: i, x: i, y: 0, dir: Direction.up),
        NodeData(id: 4, x: 4, y: 0, dir: Direction.left),
      ];
      final level = _level(nodes: nodes, gridWidth: 5, gridHeight: 1);
      final m = _metrics(
        waveDepth: 1,
        avgBF: 1.0,
        firstLegal: 1,
        cud: 1,
        fsr: 0.0,
      );
      final fp = computeLevelFingerprint(
        level: level,
        metrics: m,
        silhouette: SilhouetteId.rectangle,
      );
      // Up bit at offset 10 + Direction.up.index.
      final upBit = 1 << (10 + Direction.up.index);
      expect(fp.bits & upBit, isNot(equals(0)));
    });
  });

  group('DiversityLedger rejection window', () {
    test('isNovel returns false for an exact match in the window', () {
      final ledger = DiversityLedger();
      const fp = LevelFingerprint(0xabc123);
      ledger.record(fp);
      expect(ledger.isNovel(fp), isFalse);
    });

    test('isNovel returns false when Hamming distance < threshold', () {
      final ledger = DiversityLedger(hammingThreshold: 3);
      const a = LevelFingerprint(0x000000);
      const b = LevelFingerprint(0x000003); // distance 2
      ledger.record(a);
      expect(ledger.isNovel(b), isFalse);
    });

    test('isNovel returns true once distance ≥ threshold', () {
      final ledger = DiversityLedger(
        hammingThreshold: 3,
        sameVisualFamilyHammingMargin: 0,
      );
      const a = LevelFingerprint(0x000000);
      const b = LevelFingerprint(0x000007); // distance 3
      ledger.record(a);
      expect(ledger.isNovel(b), isTrue);
    });

    test('window evicts oldest beyond windowSize', () {
      final ledger = DiversityLedger(
        windowSize: 2,
        hammingThreshold: 1,
        sameVisualFamilyHammingMargin: 0,
      );
      ledger.record(const LevelFingerprint(0x001));
      ledger.record(const LevelFingerprint(0x002));
      // 0x001 now in window; 0x003 is distance 2 from 0x002 and distance 2
      // from 0x001 → novel.
      expect(
          ledger.isNovel(const LevelFingerprint(0x004)), isTrue);
      // Push a third in → 0x001 evicted.
      ledger.record(const LevelFingerprint(0x008));
      expect(
          ledger.isNovel(const LevelFingerprint(0x001)), isTrue);
    });

    test('serialize / restore round-trips the historical tail', () {
      final ledger = DiversityLedger(windowSize: 2, historicalCap: 4);
      for (var i = 0; i < 4; i++) {
        ledger.record(LevelFingerprint(i + 1));
      }
      final bytes = ledger.serialize();
      final clone = DiversityLedger(windowSize: 2, historicalCap: 4);
      clone.restore(bytes);
      expect(clone.historical.map((f) => f.bits).toList(),
          equals(bytes));
    });
  });
}
