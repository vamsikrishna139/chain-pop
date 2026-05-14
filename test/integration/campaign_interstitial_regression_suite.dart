// Shared campaign between-level interstitial flows — VM tests + `integration_test/`.
//
// Uses [tutorialLevels] as fixed boards (fast/safe under Flame in tests).
//
// Important: Hive writes such as seeding the lifetime gate run in group [setUp];
// [debugSimulateWinForTest] awaits Storage writes — wrap with [WidgetTester.runAsync].

import 'dart:async';
import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:chain_pop/models/game_settings.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/campaign_interstitial_frustration_gate.dart';
import 'package:chain_pop/services/ads/recording_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/session_campaign_streak.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// [Navigator.pushReplacement] can keep two routes in the tree briefly.
Future<void> _waitOutRouteTransitions(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

GameScreen _topGameScreenWidget(WidgetTester tester) =>
    tester.widgetList<GameScreen>(find.byType(GameScreen)).last;

Future<void> _pumpEasyCampaign(
  WidgetTester tester,
  RecordingAdService ads,
  int level,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(
        level: level,
        difficulty: DifficultyMode.easy,
        fixedLevel: tutorialLevels[0],
        adService: ads,
        audioHandleFactory: SilentGameAudioHandle.new,
      ),
    ),
  );
  await _settle(tester);
}

void registerCampaignInterstitialRegressionTests() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_campaign_');
    Hive.init(dir.path);
    await StorageService.init();
  });

  group('Easy campaign interstitial regressions', () {
    group(
      'single interstitial when go-next is invoked twice while show is pending',
      () {
        late RecordingAdService ads;
        late Completer<void> hang;

        setUp(() async {
          SessionCampaignStreak.reset();
          CampaignInterstitialFrustrationGate.resetForTests();
          await StorageService.clearProgress();
          await StorageService.saveGameSettings(
            const GameSettings(soundEnabled: false, hapticsEnabled: false),
          );

          await StorageService.seedLifetimeEngagementGateForTests();
          SessionCampaignStreak.onWin();
          SessionCampaignStreak.onWin();
          SessionCampaignStreak.onWin();

          hang = Completer<void>();
          ads = RecordingAdService(
            beforeInterstitialReturns: () => hang.future,
          );
        });

        tearDown(() {
          if (!hang.isCompleted) hang.complete();
        });

        testWidgets('dedupes pending next while interstitial awaits', (
          tester,
        ) async {
          await _pumpEasyCampaign(tester, ads, 1);

          final state = tester.state<GameScreenState>(find.byType(GameScreen));
          await tester.runAsync(() => state.debugSimulateWinForTest());
          await _settle(tester);
          expect(SessionCampaignStreak.wins, 4);

          unawaited(state.debugGoNextLevelForTest());
          await tester.pump();
          unawaited(state.debugGoNextLevelForTest());
          await tester.pump();

          expect(ads.betweenLevelsInterstitialShows, 1);

          hang.complete();
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 16));
          });
          await _waitOutRouteTransitions(tester);

          expect(ads.betweenLevelsInterstitialShows, 1);
          expect(_topGameScreenWidget(tester).level, 2);
        });
      },
    );

    group('two full easy streaks with lifetime gate seeded in setUp', () {
      setUp(() async {
        SessionCampaignStreak.reset();
        CampaignInterstitialFrustrationGate.resetForTests();
        await StorageService.clearProgress();
        await StorageService.saveGameSettings(
          const GameSettings(soundEnabled: false, hapticsEnabled: false),
        );
        await StorageService.seedLifetimeEngagementGateForTests();
      });

      testWidgets('second interstitial after levels 1–8', (tester) async {
        final ads = RecordingAdService();

        for (var lv = 1; lv <= 8; lv++) {
          await _pumpEasyCampaign(tester, ads, lv);

          final state = tester.state<GameScreenState>(find.byType(GameScreen));
          await tester.runAsync(() => state.debugSimulateWinForTest());
          await _settle(tester);

          unawaited(state.debugGoNextLevelForTest());
          await _waitOutRouteTransitions(tester);
        }

        expect(ads.betweenLevelsInterstitialShows, 2);
        expect(_topGameScreenWidget(tester).level, 9);
      });
    });
  });
}
