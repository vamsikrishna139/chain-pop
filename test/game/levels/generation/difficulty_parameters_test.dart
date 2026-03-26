import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';

void main() {
  group('DifficultyParameters', () {
    group('fromLevelId with explicit mode', () {
      test('returns correct parameters for easy mode', () {
        final params = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);

        expect(params.mode, equals(DifficultyMode.easy));
        expect(params.minChainLength, equals(2));
        expect(params.maxChainLength, equals(4));
        expect(params.densityFactor, equals(0.25));
        expect(params.minNodes, equals(4));
        expect(params.maxNodes, equals(12));
      });

      test('returns correct parameters for medium mode', () {
        final params = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);

        expect(params.mode, equals(DifficultyMode.medium));
        expect(params.minChainLength, equals(3));
        expect(params.maxChainLength, equals(6));
        expect(params.densityFactor, equals(0.45));
        expect(params.minNodes, equals(10));
        expect(params.maxNodes, equals(30));
      });

      test('returns correct parameters for hard mode', () {
        final params = DifficultyParameters.fromLevelId(50, mode: DifficultyMode.hard);

        expect(params.mode, equals(DifficultyMode.hard));
        expect(params.minChainLength, equals(5));
        expect(params.maxChainLength, equals(10));
        expect(params.densityFactor, equals(0.40)); // tuned down from 0.65 to prevent single-row fallback
        expect(params.minNodes, equals(15));
        expect(params.maxNodes, equals(60));
      });
    });

    group('fromLevelId without mode (auto-derive)', () {
      test('auto-derives easy mode for level 0-9', () {
        final params0 = DifficultyParameters.fromLevelId(0);
        final params5 = DifficultyParameters.fromLevelId(5);
        final params9 = DifficultyParameters.fromLevelId(9);

        expect(params0.mode, equals(DifficultyMode.easy));
        expect(params5.mode, equals(DifficultyMode.easy));
        expect(params9.mode, equals(DifficultyMode.easy));
      });

      test('auto-derives medium mode for level 10-29', () {
        final params10 = DifficultyParameters.fromLevelId(10);
        final params15 = DifficultyParameters.fromLevelId(15);
        final params29 = DifficultyParameters.fromLevelId(29);

        expect(params10.mode, equals(DifficultyMode.medium));
        expect(params15.mode, equals(DifficultyMode.medium));
        expect(params29.mode, equals(DifficultyMode.medium));
      });

      test('auto-derives hard mode for level 30+', () {
        final params30 = DifficultyParameters.fromLevelId(30);
        final params50 = DifficultyParameters.fromLevelId(50);
        final params100 = DifficultyParameters.fromLevelId(100);

        expect(params30.mode, equals(DifficultyMode.hard));
        expect(params50.mode, equals(DifficultyMode.hard));
        expect(params100.mode, equals(DifficultyMode.hard));
      });
    });

    group('difficulty progression', () {
      test('easy mode has lower node counts than medium', () {
        final easy = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);
        final medium = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.medium);

        expect(easy.minNodes, lessThan(medium.minNodes));
        expect(easy.maxNodes, lessThan(medium.maxNodes));
      });

      test('easy mode has lower density than medium', () {
        final easy = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);
        final medium = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.medium);

        expect(easy.densityFactor, lessThan(medium.densityFactor));
      });

      test('medium mode has lower node counts than hard', () {
        final medium = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);
        final hard = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.hard);

        expect(medium.minNodes, lessThan(hard.minNodes));
        expect(medium.maxNodes, lessThan(hard.maxNodes));
      });

      // Note: Hard difficulty comes from larger grid size and more nodes (absolute count),
      // not from density alone. Hard density (0.40) is intentionally lower than Medium (0.45)
      // so the backward-generation algorithm has room to find valid directions.
      test('hard mode has higher absolute node counts than medium', () {
        final medium = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);
        final hard = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.hard);

        expect(hard.maxNodes, greaterThan(medium.maxNodes),
            reason: 'Hard allows more nodes than medium overall');
      });
    });

    group('parameters stay within reasonable bounds', () {
      test('easy mode parameters are reasonable', () {
        final params = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);

        expect(params.minChainLength, greaterThan(0));
        expect(params.maxChainLength, greaterThan(params.minChainLength));
        expect(params.densityFactor, greaterThan(0.0));
        expect(params.densityFactor, lessThanOrEqualTo(1.0));
        expect(params.minNodes, greaterThan(0));
        expect(params.maxNodes, greaterThan(params.minNodes));
      });

      test('medium mode parameters are reasonable', () {
        final params = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);

        expect(params.minChainLength, greaterThan(0));
        expect(params.maxChainLength, greaterThan(params.minChainLength));
        expect(params.densityFactor, greaterThan(0.0));
        expect(params.densityFactor, lessThanOrEqualTo(1.0));
        expect(params.minNodes, greaterThan(0));
        expect(params.maxNodes, greaterThan(params.minNodes));
      });

      test('hard mode parameters are reasonable', () {
        final params = DifficultyParameters.fromLevelId(50, mode: DifficultyMode.hard);

        expect(params.minChainLength, greaterThan(0));
        expect(params.maxChainLength, greaterThan(params.minChainLength));
        expect(params.densityFactor, greaterThan(0.0));
        expect(params.densityFactor, lessThanOrEqualTo(1.0));
        expect(params.minNodes, greaterThan(0));
        expect(params.maxNodes, greaterThan(params.minNodes));
      });

      test('all modes have density factor between 0 and 1', () {
        final easy = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);
        final medium = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);
        final hard = DifficultyParameters.fromLevelId(50, mode: DifficultyMode.hard);

        expect(easy.densityFactor, inInclusiveRange(0.0, 1.0));
        expect(medium.densityFactor, inInclusiveRange(0.0, 1.0));
        expect(hard.densityFactor, inInclusiveRange(0.0, 1.0));
      });

      test('chain lengths increase with difficulty', () {
        final easy = DifficultyParameters.fromLevelId(5, mode: DifficultyMode.easy);
        final medium = DifficultyParameters.fromLevelId(15, mode: DifficultyMode.medium);
        final hard = DifficultyParameters.fromLevelId(50, mode: DifficultyMode.hard);

        expect(easy.minChainLength, lessThan(medium.minChainLength));
        expect(medium.minChainLength, lessThan(hard.minChainLength));
        expect(easy.maxChainLength, lessThan(medium.maxChainLength));
        expect(medium.maxChainLength, lessThan(hard.maxChainLength));
      });
    });
  });
}
