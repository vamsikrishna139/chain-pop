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
        fsr: 0.30,
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
        fsr: 0.30,
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard rejects opening below 4 first-legals', () {
      final m = _metrics(
        nodeCount: 24,
        waveDepth: 6,
        avgBF: 4.0,
        firstLegal: 2,
        cud: 5,
        fsr: 0.30,
      );
      expect(DifficultyProfile.hard.passes(m), isFalse);
    });

    test('Hard skips tier FSR band but keeps universal cap', () {
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
        firstLegal: 6,
        cud: 5,
        fsr: 0.30,
        tempoProfile: const [8, 7, 6, 4, 2, 1, 1, 2, 1, 6, 8, 10],
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
        firstLegal: 3,
        cud: 6,
        fsr: 0.32,
        tempoProfile: const [2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
      );
      expect(DifficultyProfile.expert.passes(m), isTrue);
    });
  });

  group('FSR-vs-nodeCount cap (§6)', () {
    test('large boards reject FSR > 0.40 regardless of tier', () {
      final m = _metrics(
        nodeCount: 35,
        waveDepth: 7,
        avgBF: 3.0,
        firstLegal: 2,
        cud: 6,
        fsr: 0.45,
      );
      expect(DifficultyProfile.passesFsrCap(m), isFalse);
      expect(DifficultyProfile.hard.passes(m), isFalse,
          reason: 'universal FSR cap fires for large boards');
    });

    test('small boards are unaffected by the cap', () {
      final m = _metrics(
        nodeCount: 20,
        waveDepth: 5,
        avgBF: 3.0,
        firstLegal: 2,
        cud: 4,
        fsr: 0.39,
      );
      expect(DifficultyProfile.passesFsrCap(m), isTrue);
    });
  });
}
