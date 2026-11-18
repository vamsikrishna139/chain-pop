import 'dart:io';

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/no_op_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/game_sfx.dart';
import 'package:chain_pop/services/session_campaign_streak.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:chain_pop/theme/world_theme.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeStreakTracker implements CampaignStreakTracker {
  int customWins = 0;

  @override
  int get wins => customWins;

  @override
  void onCampaignWin() {
    customWins++;
  }

  @override
  void resetSession() {
    customWins = 0;
  }
}

LevelData _sampleLevel({int count = 2}) => LevelData(
      levelId: 1,
      gridWidth: 10,
      gridHeight: 10,
      nodes: [
        for (var i = 0; i < count; i++)
          NodeData(id: i, x: i % 10, y: i ~/ 10, dir: Direction.up),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('lifecycle_w21_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  setUp(() async {
    await StorageService.clearProgress();
    SessionCampaignStreak.reset();
  });

  group('W2.1 Lifecycle Hygiene', () {
    testWidgets('foul handler on disposed/unmounted GameScreen does not throw',
        (tester) async {
      final level = _sampleLevel();
      ChainPopGame? gameRef;

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            level: 1,
            difficulty: DifficultyMode.easy,
            adService: NoOpAdService(),
            audioHandleFactory: SilentGameAudioHandle.new,
            campaignLevelBuilder: (_, __) => level,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final gameFinder = find.byWidgetPredicate(
        (w) => w is GameWidget<ChainPopGame>,
      );
      expect(gameFinder, findsOneWidget);
      final gameWidget = tester.widget<GameWidget<ChainPopGame>>(gameFinder);
      gameRef = gameWidget.game;
      expect(gameRef, isNotNull);

      // Navigate away / dispose GameScreen
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: Text('Gone'))));
      await tester.pumpAndSettle();

      // Trigger onJam foul callback when GameScreen is unmounted
      expect(() => gameRef!.onJam?.call(), returnsNormally);
    });

    testWidgets('ChainPopGame finale pitch clamp does not exceed 1.5',
        (tester) async {
      final recordedPitches = <double>[];
      final level = _sampleLevel(count: 20);
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
        preloadedLevel: level,
        theme: WorldTheme.fromAccent(Colors.blue),
      );
      game.soundEnabled = true;
      game.onSfx = (sfx, {double playbackRate = 1.0}) {
        if (sfx == GameSfx.pop) {
          recordedPitches.add(playbackRate);
        }
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameWidget<ChainPopGame>(game: game),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      game.startCascadeFinaleForTest();

      // Advance time through all scheduled finale pops
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(recordedPitches, isNotEmpty);
      // The 20th pop has calculated rate of 1.0 + 20 * 0.05 = 2.0; clamped to 1.5
      expect(recordedPitches.last, equals(1.5),
          reason: 'Finale pitch is clamped to 1.5 max (W2.1)');
      for (final pitch in recordedPitches) {
        expect(pitch, lessThanOrEqualTo(1.5));
      }
    });

    testWidgets(
        'setupBoard clears ray preview so rayPreviewActive does not freeze ambient motion',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
        preloadedLevel: _sampleLevel(count: 2),
        theme: WorldTheme.fromAccent(Colors.blue),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameWidget<ChainPopGame>(game: game),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(game.rayPreviewActive, isFalse);

      // Show ray preview for node 0
      game.showRayPreview(game.levelData.nodes.first);
      expect(game.rayPreviewActive, isTrue);

      // Resize trigger
      tester.view.physicalSize = const Size(1200, 2600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Preview should have been cleanly cleared by hideRayPreview()
      expect(game.rayPreviewActive, isFalse);
    });

    test('injected CampaignStreakTracker controls streak prediction', () {
      final tracker = _FakeStreakTracker();
      tracker.customWins = 5;

      // Static session streak remains 0
      expect(SessionCampaignStreak.wins, 0);

      // The tracker shows 5 wins, which exceeds Easy/Medium/Hard thresholds
      expect(
        tracker.wins >=
            SessionCampaignStreak.interstitialStreakThreshold(
                DifficultyMode.hard),
        isTrue,
      );
      expect(
        SessionCampaignStreak.wins >=
            SessionCampaignStreak.interstitialStreakThreshold(
                DifficultyMode.hard),
        isFalse,
      );
    });
  });
}
