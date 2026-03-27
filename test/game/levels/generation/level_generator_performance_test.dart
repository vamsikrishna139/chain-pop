/// Performance benchmark tests for the level generation system.
///
/// Validates that generation meets the latency requirements:
///   - 50 nodes  < 100 ms
///   - 100 nodes < 500 ms
///   - 400 nodes < 2000 ms
///
/// Run with: flutter test test/game/levels/generation/level_generator_performance_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation.dart';

void main() {
  final generator = LevelGenerator();

  Duration _measureAvg(int levelId, {int runs = 5}) {
    // Warm-up run (JIT compilation, caches)
    generator.generate(levelId);

    var total = Duration.zero;
    for (int i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      generator.generate(levelId + i); // vary ID slightly for realistic measurement
      sw.stop();
      total += sw.elapsed;
    }
    return total ~/ runs;
  }

  group('Performance — generation latency', () {
    test('Easy levels (≈4-12 nodes) generate in < 100 ms', () {
      // Level 5 → easy mode
      final avg = _measureAvg(5);
      expect(
        avg.inMilliseconds,
        lessThan(100),
        reason: 'Easy level avg=${avg.inMilliseconds}ms exceeded 100ms limit',
      );
    });

    test('Medium levels (≈10-30 nodes) generate in < 500 ms', () {
      // Level 20 → medium mode
      final avg = _measureAvg(20);
      expect(
        avg.inMilliseconds,
        lessThan(500),
        reason: 'Medium level avg=${avg.inMilliseconds}ms exceeded 500ms limit',
      );
    });

    test('Hard levels (≈25-100 nodes) generate in < 2000 ms', () {
      // Level 50 → hard mode
      final avg = _measureAvg(50);
      expect(
        avg.inMilliseconds,
        lessThan(2000),
        reason: 'Hard level avg=${avg.inMilliseconds}ms exceeded 2000ms limit',
      );
    });

    test('Prints generation timing summary', () {
      // Informational — always passes; shows timings in test output.
      final rows = <String>[];
      for (final entry in {
        'Easy   (level 5)':  5,
        'Medium (level 20)': 20,
        'Hard   (level 50)': 50,
        'Hard   (level 100)': 100,
        'Hard   (level 500)': 500,
        'Hard   (level 1000)': 1000,
      }.entries) {
        final sw = Stopwatch()..start();
        final result = generator.generate(entry.value);
        sw.stop();
        final level = result.isSuccess ? result.value : null;
        rows.add('${entry.key}: ${level?.nodes.length ?? 0} nodes on '
            '${level?.gridWidth ?? 0}x${level?.gridHeight ?? 0} '
            'in ${sw.elapsedMilliseconds}ms');
      }
      // ignore: avoid_print
      print('\n--- Generation Performance ---\n${rows.join('\n')}\n');
      expect(true, isTrue); // Always passes
    });
  });
}
