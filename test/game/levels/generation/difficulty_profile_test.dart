import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

LevelMetrics _metrics({
  required int nodeCount,
  required int waveDepth,
  required double avgBF,
  required int firstLegal,
  required int cud,
  required double fsr,
  List<int> tempoProfile = const [],
  List<int> wavePeelingProfile = const [4],
}) {
  return LevelMetrics(
    nodeCount: nodeCount,
    waveDepth: waveDepth,
    averageBranchingFactor: avgBF,
    firstLegalMoveCount: firstLegal,
    criticalUnlockDepth: cud,
    forcedSequenceRatio: fsr,
    frontierVariance: 0.0,
    tempoProfile: tempoProfile,
    viablePathCount: -1,
    viablePathCountCapped: false,
    wavePeelingProfile: wavePeelingProfile,
  );
}

void main() {
  group('DifficultyProfile.tierFromMode', () {
    test('maps the three legacy modes', () {
      expect(DifficultyProfile.tierFromMode(DifficultyMode.easy),
          equals(DifficultyTier.easy));
      expect(DifficultyProfile.tierFromMode(DifficultyMode.medium),
          equals(DifficultyTier.medium));
      expect(DifficultyProfile.tierFromMode(DifficultyMode.hard),
          equals(DifficultyTier.hard));
    });
  });

  group('DifficultyProfile.passes (§6 bands)', () {
    test('Hard band accepts a textbook in-range level', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 5,
        fsr: 0.55,
      );
      expect(DifficultyProfile.hard.passes(m), isTrue);
    });

    test('Hard rejects BF below 3 (immersive opening band)', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 2.5,
        firstLegal: 5,
        cud: 5,
        fsr: 0.55,
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard rejects waveZeroWidth above 11 (honest opening band)', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 9,
        cud: 5,
        fsr: 0.55,
        wavePeelingProfile: const [12, 3, 2],
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard accepts waveZeroWidth up to 11', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 11,
        cud: 5,
        fsr: 0.55,
        wavePeelingProfile: const [11, 3, 2],
      );
      expect(DifficultyProfile.hard.passes(m), isTrue);
    });

    test('Hard rejects opening below 3 first-legals', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 2,
        cud: 5,
        fsr: 0.55,
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard rejects FSR below tier minimum', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 5,
        fsr: 0.30,
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard accepts FSR within tier band and below universal cap', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 5,
        fsr: 0.50,
      );
      expect(DifficultyProfile.hard.passes(m), isTrue);
    });

    test('Easy rejects an Expert-like FSR', () {
      final m = _metrics(
        nodeCount: 12,
        waveDepth: 2,
        avgBF: 6.0,
        firstLegal: 6,
        cud: 1,
        fsr: 0.5,
      );
      expect(DifficultyProfile.easy.passes(m), isFalse);
    });

    test('Hard dramatic tempo accepts rise-then-release profile with arc', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 4,
        cud: 5,
        fsr: 0.55,
        tempoProfile: const [8, 7, 6, 4, 2, 1, 1, 2, 1, 6, 8, 10],
        wavePeelingProfile: const [4],
      );
      expect(DifficultyProfile.hard.passes(m), isTrue);
    });

    test('passesTemporalArc rejects flat tempo without crunch', () {
      expect(
        DifficultyProfile.hard.passesTemporalArc(
          const [6, 6, 6, 6, 6, 6, 6, 6, 6, 6],
        ),
        isFalse,
      );
    });

    test('passesTemporalArc accepts flow-crunch-release arc', () {
      expect(
        DifficultyProfile.hard.passesTemporalArc(
          const [8, 7, 6, 4, 2, 1, 1, 2, 1, 6, 8, 10],
        ),
        isTrue,
      );
    });

    test('passesTemporalArc rejects short sequences', () {
      expect(
        DifficultyProfile.hard.passesTemporalArc(const [5, 4, 3, 2, 1]),
        isFalse,
      );
    });

    test('Expert passes flat tempo when other bands match', () {
      final m = _metrics(
        nodeCount: 26,
        waveDepth: 7,
        avgBF: 3.0,
        firstLegal: 4,
        cud: 6,
        fsr: 0.60,
        tempoProfile: const [2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
      );
      expect(DifficultyProfile.expert.passes(m), isTrue);
    });
  });

  group('FSR-vs-nodeCount node-banded cap (§6)', () {
    test('small boards (≤28 nodes) are unaffected by the cap', () {
      final m = _metrics(
        nodeCount: 20,
        waveDepth: 5,
        avgBF: 3.0,
        firstLegal: 2,
        cud: 4,
        fsr: 0.90,
      );
      expect(DifficultyProfile.passesFsrCap(m), isTrue);
      expect(DifficultyProfile.fsrCapForNodeCount(20), equals(1.0));
      expect(DifficultyProfile.fsrCapForNodeCount(28), equals(1.0));
    });

    test('cap interpolates linearly between threshold and ceiling', () {
      // At 28 nodes: uncapped (1.0)
      expect(DifficultyProfile.fsrCapForNodeCount(28), equals(1.0));
      // At 29 nodes: just past threshold, close to fsrCapAtThreshold (0.65)
      final cap29 = DifficultyProfile.fsrCapForNodeCount(29);
      expect(cap29, closeTo(0.65 + (0.35 - 0.65) * (1 / 27), 1e-6));
      // Midpoint (node ~41): roughly midway between 0.65 and 0.35
      final capMid = DifficultyProfile.fsrCapForNodeCount(41);
      expect(capMid, closeTo(0.65 + (0.35 - 0.65) * (13 / 27), 1e-6));
      // At 55 nodes: cap reaches minimum
      expect(DifficultyProfile.fsrCapForNodeCount(55), equals(0.35));
    });

    test('above ceiling, cap stays at fsrCapAtCeiling', () {
      expect(DifficultyProfile.fsrCapForNodeCount(60), equals(0.35));
      expect(DifficultyProfile.fsrCapForNodeCount(100), equals(0.35));
    });

    test('Expert@29 nodes with FSR 0.55 is now feasible (was impossible)', () {
      // Expert FSR floor is 0.50; at 29 nodes the banded cap is ~0.639.
      // Old flat cap of 0.40 made FSR ≥ 0.50 impossible above 28 nodes.
      final m = _metrics(
        nodeCount: 29,
        waveDepth: 7,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 7,
        fsr: 0.55,
      );
      expect(DifficultyProfile.passesFsrCap(m), isTrue,
          reason: 'banded cap at 29 nodes should allow FSR 0.55');
      expect(DifficultyProfile.expert.passes(m), isTrue,
          reason: 'Expert band should accept 29-node level with FSR 0.55');
    });

    test('Hard@40 nodes with FSR 0.50 is feasible', () {
      final m = _metrics(
        nodeCount: 40,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 6,
        fsr: 0.50,
      );
      expect(DifficultyProfile.passesFsrCap(m), isTrue,
          reason: 'banded cap at 40 nodes (~0.517) should allow FSR 0.50');
      expect(DifficultyProfile.hard.passes(m), isTrue,
          reason: 'Hard band should accept 40-node level with FSR 0.50');
    });

    test('very large boards reject high FSR via the cap', () {
      final m = _metrics(
        nodeCount: 55,
        waveDepth: 7,
        avgBF: 3.0,
        firstLegal: 5,
        cud: 6,
        fsr: 0.45,
      );
      expect(DifficultyProfile.passesFsrCap(m), isFalse,
          reason: 'at 55 nodes cap is 0.35, FSR 0.45 exceeds it');
      expect(DifficultyProfile.hard.passes(m), isFalse,
          reason: 'FSR cap fires for large boards');
    });
  });

  group('Declared band max feasibility', () {
    test('Hard nodeCount.max is feasible at its FSR floor', () {
      final maxNodes = DifficultyProfile.hard.nodeCount.max;
      final fsrFloor = DifficultyProfile.hard.forcedSequenceRatio.min;
      final cap = DifficultyProfile.fsrCapForNodeCount(maxNodes);
      expect(cap, greaterThan(fsrFloor),
          reason: 'Hard max ($maxNodes nodes): cap $cap must exceed '
              'FSR floor $fsrFloor for real headroom');

      // Full band pass at the declared max.
      final m = _metrics(
        nodeCount: maxNodes,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 6,
        fsr: fsrFloor,
      );
      expect(DifficultyProfile.hard.passes(m), isTrue,
          reason: 'Hard should pass at nodeCount.max with FSR floor');
    });

    test('Expert nodeCount.max is feasible at its FSR floor', () {
      final maxNodes = DifficultyProfile.expert.nodeCount.max;
      final fsrFloor = DifficultyProfile.expert.forcedSequenceRatio.min;
      final cap = DifficultyProfile.fsrCapForNodeCount(maxNodes);
      expect(cap, greaterThan(fsrFloor),
          reason: 'Expert max ($maxNodes nodes): cap $cap must exceed '
              'FSR floor $fsrFloor for real headroom');

      // Full band pass at the declared max.
      final m = _metrics(
        nodeCount: maxNodes,
        waveDepth: 7,
        avgBF: 4.0,
        firstLegal: 5,
        cud: 7,
        fsr: fsrFloor,
      );
      expect(DifficultyProfile.expert.passes(m), isTrue,
          reason: 'Expert should pass at nodeCount.max with FSR floor');
    });
  });

  group('topologySoftScore (B3)', () {
    test('Hard rewards 1–2 choke points and in-band critical path', () {
      const profile = DifficultyProfile.hard;
      final ideal = profile.topologySoftScore(
        chokePointCount: 2,
        criticalPathLength: 8,
        maxHubInDegree: 3,
      );
      final flat = profile.topologySoftScore(
        chokePointCount: 0,
        criticalPathLength: 3,
        maxHubInDegree: 6,
      );
      expect(ideal, greaterThan(flat));
    });

    test('Easy tier returns zero topology score', () {
      expect(
        DifficultyProfile.easy.topologySoftScore(
          chokePointCount: 2,
          criticalPathLength: 8,
          maxHubInDegree: 3,
        ),
        equals(0),
      );
    });
  });
}
