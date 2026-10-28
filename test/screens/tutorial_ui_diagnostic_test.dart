import 'dart:io';

import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/no_op_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('chain_pop_tutorial_diag_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  Widget buildStep(int i) => MaterialApp(
        home: GameScreen(
          level: i + 1,
          difficulty: DifficultyMode.easy,
          fixedLevel: tutorialLevels[i],
          isTutorial: true,
          tutorialIndex: i,
          adService: NoOpAdService(),
          audioHandleFactory: SilentGameAudioHandle.new,
        ),
      );

  for (final (w, h, dpr, label) in [
    (1080.0, 2400.0, 3.0, 'tall phone'),
    (640.0, 1136.0, 2.0, 'small phone'),
    (750.0, 1334.0, 2.0, 'medium phone'),
  ]) {
    for (var i = 0; i < tutorialLevels.length; i++) {
      testWidgets('step $i on $label: gameplay, win, pause render clean',
          (tester) async {
        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildStep(i));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'gameplay step $i');

        // Pause overlay
        final state = tester.state<GameScreenState>(find.byType(GameScreen));
        await tester.tap(find.byIcon(Icons.pause_rounded), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'pause step $i');

        // Win overlay. The final step's win path awaits a real Hive write
        // (setTutorialCompleted); runAsync drives that real I/O on the real
        // event loop instead of deadlocking against the test's fake-async zone
        // (which would otherwise hang until the 10-minute per-test timeout).
        await tester.runAsync(() => state.debugSimulateWinForTest());
        if (i == tutorialLevels.length - 1) {
          // The final step schedules a 3-second tutorialExitTimer to return to menu.
          // Pump past it so it fires and clears from the event queue.
          await tester.pump(const Duration(seconds: 4));
        } else {
          await tester.pump(const Duration(milliseconds: 600));
        }
        expect(tester.takeException(), isNull, reason: 'win step $i');
      });
    }
  }
}
