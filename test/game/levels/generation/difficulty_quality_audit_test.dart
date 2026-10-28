import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Option A (2026-06): honest [3,11] opening band for Hard/Expert. The original
  // [3,5] target was structurally unreachable — see OPENING_BAND_DECISION.md.
  const openingMax = 11;

  group('Difficulty Quality Audit Tests', () {
    test('Hard campaign levels (L30-59) have high in-band rate (>= 90%)', () {
      final gen = LevelGenerator();
      var inBandCount = 0;
      const totalLevels = 30;
      const startId = 30;

      for (var id = startId; id < startId + totalLevels; id++) {
        final r = gen.generate(id, mode: DifficultyMode.hard);
        expect(r.isSuccess, isTrue, reason: 'Level $id failed to generate');
        final level = r.value;
        final metrics = LevelMetrics.compute(level);
        expect(
          metrics.firstLegalMoveCount,
          lessThanOrEqualTo(openingMax),
          reason: 'Hard L$id opening ceiling ($openingMax)',
        );
        expect(
          metrics.waveZeroWidth,
          lessThanOrEqualTo(openingMax),
          reason: 'Hard L$id wave-zero ceiling ($openingMax)',
        );
        final passes = DifficultyProfile.hard.passes(metrics);
        if (passes) {
          inBandCount++;
        } else {
          // ignore: avoid_print
          print('Hard L$id out-of-band: '
              'nodes=${metrics.nodeCount}, '
              'opening=${metrics.firstLegalMoveCount}, '
              'waveZero=${metrics.waveZeroWidth}, '
              'BF=${metrics.averageBranchingFactor.toStringAsFixed(2)}, '
              'CUD=${metrics.criticalUnlockDepth}, '
              'FSR=${(metrics.forcedSequenceRatio * 100).toStringAsFixed(0)}%');
        }
      }

      final rate = inBandCount / totalLevels;
      // ignore: avoid_print
      print(
          'Hard Campaign In-Band Rate: ${(rate * 100).toStringAsFixed(1)}% ($inBandCount/$totalLevels)');
      expect(rate, greaterThanOrEqualTo(0.90),
          reason: 'In-band rate for Hard campaign levels must be at least 90%');
    });

    test('Daily challenge sample week levels have high in-band rate (>= 90%)',
        () {
      var inBandCount = 0;
      const dates = [
        '2026-06-13',
        '2026-06-14',
        '2026-06-15',
        '2026-06-16',
        '2026-06-17',
        '2026-06-18',
        '2026-06-19',
        '2026-06-20',
        '2026-06-21',
        '2026-06-22',
      ];

      for (final dateStr in dates) {
        final date = DateTime.parse(dateStr);
        final level = LevelManager.getDailyChallenge(date);
        final metrics = LevelMetrics.compute(level);
        expect(
          metrics.firstLegalMoveCount,
          lessThanOrEqualTo(openingMax),
          reason: 'Daily $dateStr opening ceiling ($openingMax)',
        );
        expect(
          metrics.waveZeroWidth,
          lessThanOrEqualTo(openingMax),
          reason: 'Daily $dateStr wave-zero ceiling ($openingMax)',
        );
        final passes = DifficultyProfile.expert.passes(metrics);
        if (passes) {
          inBandCount++;
        } else {
          // ignore: avoid_print
          print('Daily $dateStr out-of-band: '
              'nodes=${metrics.nodeCount}, '
              'opening=${metrics.firstLegalMoveCount}, '
              'waveZero=${metrics.waveZeroWidth}, '
              'BF=${metrics.averageBranchingFactor.toStringAsFixed(2)}, '
              'CUD=${metrics.criticalUnlockDepth}, '
              'FSR=${(metrics.forcedSequenceRatio * 100).toStringAsFixed(0)}%');
        }
      }

      final rate = inBandCount / dates.length;
      // ignore: avoid_print
      print(
          'Daily Challenge In-Band Rate: ${(rate * 100).toStringAsFixed(1)}% ($inBandCount/${dates.length})');
      expect(rate, greaterThanOrEqualTo(0.90),
          reason:
              'In-band rate for Daily challenge levels must be at least 90%');
    });
  });
}
