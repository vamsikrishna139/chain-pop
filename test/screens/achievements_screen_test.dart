import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/screens/achievements_screen.dart';
import 'package:chain_pop/services/achievements/achievement_catalog.dart';
import 'package:chain_pop/services/achievements/achievement_tracker.dart';
import 'package:chain_pop/services/achievements/achievements_locator.dart';
import 'package:chain_pop/services/achievements/game_event.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:chain_pop/services/achievements/play_games_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:hive/hive.dart';

CampaignLevelWon _win({int nodes = 10, int stars = 1}) => CampaignLevelWon(
      mode: DifficultyMode.easy,
      levelId: 1,
      starsEarned: stars,
      directive: LevelDirective.swift,
      jamCount: 0,
      undosUsed: 0,
      hintsUsed: 0,
      networkIntegrity: 100,
      nodeCount: nodes,
      coreCount: 0,
      lockCount: 0,
      relayCount: 0,
      phaseGateCount: 0,
      portalPairCount: 0,
      dayKey: 20260814,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveChainPopPersistence storage;
  late AchievementTracker tracker;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_ach_ui_test_');
    Hive.init(dir.path);
  });

  setUp(() async {
    storage = HiveChainPopPersistence();
    await storage.open();
    await storage.clearProgress();
    tracker = AchievementTracker(storage: storage);
    AchievementsLocator.install(tracker);
  });

  tearDown(() async {
    AchievementsLocator.uninstall();
    PlayGamesAuth.instance.disposeTesting();
    await tracker.dispose();
  });

  /// Gives the test a viewport tall enough to hold all 48 rows at once.
  ///
  /// The list builds lazily, so on a phone-sized surface most entries are
  /// genuinely absent from the widget tree and `find` reports false negatives.
  /// Scrolling to each one is far more fragile than simply rendering the whole
  /// catalog, which is what these tests are actually about.
  void useTallViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1000, 8000);
    addTearDown(tester.view.reset);
  }

  /// Mounts a *fresh* screen.
  ///
  /// [AchievementsScreen] snapshots the tracker in `initState`, which is right
  /// for production (Navigator builds a new State on every push) but means
  /// re-pumping an identical widget would reuse the old State and show stale
  /// data. Unmounting first forces the re-read the test is asking for.
  /// Auth is injected so the screen never reaches the real platform channel:
  /// [AchievementsScreen] re-runs the native check on open, which throws
  /// MissingPluginException under `flutter test`. A never-emitting stream holds
  /// it at [PlayGamesAuthState.unknown] — the signed-out/offline path these
  /// tests are about.
  Future<void> pumpScreen(WidgetTester tester) async {
    final auth = PlayGamesAuth(
      authStreamFactory: () => const Stream<gs.PlayerData?>.empty(),
    );
    addTearDown(auth.disposeTesting);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(home: AchievementsScreen(auth: auth)));
    await tester.pumpAndSettle();
  }

  /// Runs Hive-backed work outside the fake-async zone.
  ///
  /// `testWidgets` bodies execute under `FakeAsync`, where Hive's real file I/O
  /// never completes — awaiting a tracker write directly inside a test hangs it
  /// forever rather than failing.
  Future<void> realAsync(WidgetTester tester, Future<void> Function() body) =>
      tester.runAsync(body).then((_) {});

  testWidgets('renders the whole catalog on a fresh install', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    useTallViewport(tester);
    await pumpScreen(tester);

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(
      find.textContaining('/ ${kAchievementCatalog.length}'),
      findsOneWidget,
    );
    expect(find.text('0 pts'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows every track section', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    useTallViewport(tester);
    await pumpScreen(tester);

    for (final track in AchievementTrack.values) {
      expect(
        find.text(track.label.toUpperCase()),
        findsOneWidget,
        reason: track.name,
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('conceals a hidden achievement until it is earned',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    useTallViewport(tester);
    await pumpScreen(tester);

    expect(find.text('Hidden achievement'), findsOneWidget);
    expect(find.text('Chain Reaction'), findsNothing);

    await realAsync(tester, () => tracker.record(const ComboReached(5)));
    await pumpScreen(tester);

    expect(find.text('Chain Reaction'), findsOneWidget);
    expect(find.text('Hidden achievement'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reflects earned achievements in the summary', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    useTallViewport(tester);
    await realAsync(tester, () async {
      await storage.unlockLevel(DifficultyMode.easy, 2);
      await tracker.record(_win(nodes: 120, stars: 3));
    });

    await pumpScreen(tester);

    // Cold Start (5) + Hundred Down (15) + Swift Solver (15) = 35.
    expect(find.text('35 pts'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows a progress bar for a partially earned tier',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    useTallViewport(tester);
    await realAsync(tester, () => tracker.record(_win(nodes: 40)));

    await pumpScreen(tester);
    expect(find.text('40/100'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
