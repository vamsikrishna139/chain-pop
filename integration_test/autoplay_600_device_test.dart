// On-device playtest: 600 campaign levels, split across all three modes, played
// through the real app on a real device/emulator.
//
// This is the device counterpart to `test/dev/autoplay_600_test.dart`. That one
// drives `ChainPopGame` headlessly and is fast enough to run per-commit; this
// one boots an actual `GameScreen` per level, so everything the headless harness
// cannot see is in the loop: level loading through `LevelManager`, board layout
// and cell sizing, `NodeComponent` extraction with its pop/jam animation gates,
// the HUD, the countdown, and the win flow. A level that generates fine but
// cannot be *laid out* or *tapped* on a 1080x2400 screen fails here and only
// here.
//
// It uses the app's own playtest hook — `ChainPopGame.autoSolveStep()`, the same
// call `GameScreen(autoplay: true)` ticks on a timer — but drives the tick from
// the test instead of a `Timer.periodic`, so progress is tied to pumped frames
// rather than wall-clock and a slow emulator cannot be mistaken for a stuck
// board.
//
//   flutter test integration_test/autoplay_600_device_test.dart \
//       -d emulator-5554 --dart-define=MOCK_ADS=true
// ignore_for_file: avoid_print

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/main.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/recording_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/storage/storage_locator.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// 200 levels per mode x 3 modes = 600 plays, strided so each mode covers the
/// whole 1..600 range rather than clustering in the easy opening sectors.
const int _kPerMode = int.fromEnvironment('PER_MODE', defaultValue: 200);
const int _kStride = 3;

/// Frames allowed for the level to load and lay its board out before the first
/// extraction is expected to succeed.
const int _kWarmupFrames = 240;

/// Frames of slack per extraction, so one slow pop cannot look like a stall.
const int _kFramesPerTap = 12;

const Duration _kFrame = Duration(milliseconds: 32);

ChainPopGame? _findGame(WidgetTester tester) {
  final matches = find.byWidgetPredicate((w) => w is GameWidget);
  if (matches.evaluate().isEmpty) return null;
  final widget = tester.widget(matches.first) as GameWidget;
  final game = widget.game;
  return game is ChainPopGame ? game : null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await bootstrapChainPop();

    // Mark the Hard/Daily "Extra hints" coach as already seen.
    //
    // Load-bearing for the Hard leg. The coach is pushed from `initState`
    // whenever `hardOrDailyFeatures` is set, but its `seen` flag is only
    // written *after* `showDialog` returns — i.e. after a human taps "Got it".
    // This harness drives the engine directly and never taps, so without this
    // every Hard level stacks another modal route: by level 200 there are ~200
    // dialogs and barriers rebuilding every frame, which degrades the run
    // superlinearly and eventually ANRs the app. Pre-setting the flag is what
    // a returning player's storage already looks like.
    await StorageLocator.instance.setHintRewardAdCoachSeen();
  });

  testWidgets('600 campaign levels play to completion on device',
      (tester) async {
    final failures = <String>[];
    var totalWon = 0;
    var totalPlayed = 0;

    for (final mode in DifficultyMode.values) {
      var won = 0;
      var stranded = 0;
      var neverLoaded = 0;
      var totalTaps = 0;
      final sw = Stopwatch()..start();

      for (var i = 0; i < _kPerMode; i++) {
        final id = 1 + i * _kStride;
        totalPlayed++;

        // A fresh key per level is load-bearing, not cosmetic. `GameScreen`
        // builds its engine in `initState` and has no `didUpdateWidget`, so a
        // keyless re-pump of the same widget type updates the element in place:
        // `initState` never re-runs, the board stays on the first level for the
        // whole sweep, and the header counts up over a stale, already-won
        // board. Changing the key forces dispose + initState, i.e. a real
        // level load.
        await tester.pumpWidget(
          MaterialApp(
            home: GameScreen(
              key: ValueKey('${mode.name}-$id'),
              level: id,
              difficulty: mode,
              autoplay: true,
              adService: RecordingAdService(),
              audioHandleFactory: SilentGameAudioHandle.new,
            ),
          ),
        );

        // Warm up until the engine will actually accept an extraction: the
        // board has to be generated, mounted and laid out first, and
        // `autoSolveStep` reports "not yet" the same way it reports "stuck".
        ChainPopGame? game;
        var started = false;
        for (var f = 0; f < _kWarmupFrames && !started; f++) {
          await tester.pump(_kFrame);
          game ??= _findGame(tester);
          if (game != null && game.autoSolveStep()) started = true;
        }

        if (!started) {
          neverLoaded++;
          failures.add('${mode.name} L$id: board never became playable '
              '(${game == null ? "no game widget" : "no legal first tap"})');
          continue;
        }

        var taps = 1;
        final tapBudget = (game!.levelData.nodes.length + 4);
        var framesSinceTap = 0;
        while (!game.hasWon && taps < tapBudget) {
          await tester.pump(_kFrame);
          if (game.autoSolveStep()) {
            taps++;
            framesSinceTap = 0;
          } else if (++framesSinceTap > _kFramesPerTap) {
            break;
          }
        }

        // Let the win settle (cascade finale on core-win levels pops the
        // remainder over ~1.2s before `onWin` fires).
        for (var f = 0; f < 60 && !game.hasWon; f++) {
          await tester.pump(_kFrame);
        }

        if (game.hasWon) {
          won++;
          totalWon++;
          totalTaps += taps;
        } else {
          stranded++;
          failures.add('${mode.name} L$id: STRANDED with '
              '${game.activeNodes.length}/${game.levelData.nodes.length} '
              'nodes left after $taps taps');
        }

        if ((i + 1) % 25 == 0) {
          print('  ${mode.name}: ${i + 1}/$_kPerMode played, '
              '$won won, ${sw.elapsed.inSeconds}s');
        }
      }
      sw.stop();

      print('\n=== ${mode.name.toUpperCase()} (on device) ===');
      print('  played      : $_kPerMode  (ids 1..${1 + (_kPerMode - 1) * _kStride} '
          'stride $_kStride)');
      print('  won         : $won');
      print('  stranded    : $stranded');
      print('  never loaded: $neverLoaded');
      print('  taps        : avg '
          '${won == 0 ? 0 : (totalTaps / won).toStringAsFixed(1)}');
      print('  wall clock  : ${sw.elapsed.inSeconds}s');
    }

    print('\nTOTAL: $totalWon/$totalPlayed levels completed on device');
    if (failures.isNotEmpty) {
      print('FAILURES (${failures.length}):');
      for (final f in failures.take(50)) {
        print('  $f');
      }
    }

    expect(failures, isEmpty,
        reason: '${failures.length} of $totalPlayed device play-throughs '
            'did not complete');
  }, timeout: const Timeout(Duration(hours: 3)));
}
