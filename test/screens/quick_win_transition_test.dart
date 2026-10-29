// Quick-win flow-preserving transition + surge label, driven through a real
// [GameScreen] with a recording ad service (mirrors the campaign interstitial
// regression harness). Hive writes happen on win — wrap with runAsync.

import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:chain_pop/models/game_settings.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/screens/game/widgets/quick_win_banner.dart';
import 'package:chain_pop/screens/game/widgets/win_celebration_overlay.dart';
import 'package:chain_pop/services/ads/campaign_interstitial_frustration_gate.dart';
import '../services/ads/recording_ad_service.dart';
import '../services/subscription/test_subscription_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/session_campaign_streak.dart';
import 'package:chain_pop/services/session_pacing.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:chain_pop/services/subscription/subscription_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakePacing implements SessionPacingController {
  _FakePacing(this.surge);
  final SurgeKind? surge;
  int wins = 0;

  @override
  void onCampaignWin() => wins++;
  @override
  void resetSession() => wins = 0;
  @override
  int get winsThisSession => wins;
  @override
  SurgeKind? surgeForUpcomingLevel() => surge;
}

/// Seeds the session streak so the next Easy win lands on the interstitial
/// threshold (4).
void _seedStreakToInterstitialThreshold() {
  SessionCampaignStreak.onWin();
  SessionCampaignStreak.onWin();
  SessionCampaignStreak.onWin();
}

/// The win countdown runs on real timers (they are created inside the
/// runAsync win), so wait in real time and then rebuild.
Future<void> _waitReal(WidgetTester tester, Duration d) async {
  await tester.runAsync(() => Future<void>.delayed(d));
  await tester.pump();
}

void _setLifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpEasyCampaign(
  WidgetTester tester, {
  required int level,
  RecordingAdService? ads,
  SessionPacingController? pacing,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(
        level: level,
        difficulty: DifficultyMode.easy,
        fixedLevel: tutorialLevels[0],
        adService: ads ?? RecordingAdService(),
        sessionPacing: pacing,
        audioHandleFactory: SilentGameAudioHandle.new,
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_quickwin_');
    Hive.init(dir.path);
    await StorageService.init();
  });

  setUp(() async {
    SessionCampaignStreak.reset();
    SessionPacing.reset();
    CampaignInterstitialFrustrationGate.resetForTests();
    await StorageService.clearProgress();
    await StorageService.saveGameSettings(
      const GameSettings(soundEnabled: false, hapticsEnabled: false),
    );
    await StorageService.seedLifetimeEngagementGateForTests();
  });

  testWidgets('fast clear shows the quick banner, not the full celebration',
      (tester) async {
    await _pumpEasyCampaign(tester, level: 1);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));

    await tester.runAsync(() => state.debugSimulateWinForTest());
    await _settle(tester);

    expect(find.byType(QuickWinBanner), findsOneWidget);
    expect(find.byType(WinCelebrationOverlay), findsNothing);
  });

  testWidgets('when an interstitial is due, the full celebration shows',
      (tester) async {
    // Easy threshold is 4; pre-seed so this win lands on the streak.
    _seedStreakToInterstitialThreshold();

    await _pumpEasyCampaign(tester, level: 1);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));

    await tester.runAsync(() => state.debugSimulateWinForTest());
    await _settle(tester);

    expect(find.byType(QuickWinBanner), findsNothing);
    expect(find.byType(WinCelebrationOverlay), findsOneWidget);
  });

  testWidgets('premium users never count as interstitial-due', (tester) async {
    final subs = TestSubscriptionService()..setPremium(true);
    SubscriptionLocator.install(subs);
    addTearDown(SubscriptionLocator.uninstall);
    _seedStreakToInterstitialThreshold();

    await _pumpEasyCampaign(tester, level: 1);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));

    await tester.runAsync(() => state.debugSimulateWinForTest());
    await _settle(tester);

    // Same streak as above, but no interstitial can show, so the fast clear
    // keeps the quick banner.
    expect(find.byType(QuickWinBanner), findsOneWidget);
    expect(find.byType(WinCelebrationOverlay), findsNothing);
  });

  testWidgets('win countdown holds while the app is in the background',
      (tester) async {
    addTearDown(() => _setLifecycle(tester, [AppLifecycleState.resumed]));
    _seedStreakToInterstitialThreshold(); // full panel with a countdown

    await _pumpEasyCampaign(tester, level: 1);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));

    await tester.runAsync(() => state.debugSimulateWinForTest());
    await _settle(tester);
    expect(find.text('Next level in 5s'), findsOneWidget);

    // e.g. Rate opened the Play Store over the app.
    _setLifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await _waitReal(tester, const Duration(milliseconds: 2900));
    expect(find.text('Next level in 5s'), findsOneWidget);

    _setLifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await _waitReal(tester, const Duration(milliseconds: 1300));
    expect(find.text('Next level in 5s'), findsNothing);
  });

  testWidgets('a surge level shows the SURGE header label', (tester) async {
    await _pumpEasyCampaign(
      tester,
      level: 5,
      pacing: _FakePacing(SurgeKind.timed),
    );
    expect(find.text('⚡ SURGE'), findsOneWidget);
  });

  testWidgets('a calm level shows no SURGE label', (tester) async {
    await _pumpEasyCampaign(
      tester,
      level: 5,
      pacing: _FakePacing(null),
    );
    expect(find.text('⚡ SURGE'), findsNothing);
  });
}
