import 'dart:async';
import 'dart:io';

import 'package:chain_pop/services/achievements/achievements_locator.dart';
import 'package:chain_pop/services/achievements/play_games_auth.dart';
import 'package:chain_pop/services/achievements/play_games_bootstrap.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:chain_pop/services/storage/storage_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart' as gs;
import 'package:hive/hive.dart';

/// Pins the wiring that decides whether achievements reach Google at all.
///
/// The original integration shipped green tests while sign-in was completely
/// broken, because nothing asserted that the sink's availability actually
/// tracks the auth stream. That is what these cover.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const player = gs.PlayerData(playerID: 'p1', displayName: 'tester');

  late StreamController<gs.PlayerData?> controller;
  late PlayGamesAuth auth;
  late HiveChainPopPersistence storage;

  /// install() kicks off refresh(), which only attaches its listener after a
  /// microtask. A broadcast controller drops events with no listener, so the
  /// test has to let that settle before pushing auth events.
  Future<void> settled() => pumpEventQueue();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_pgs_boot_');
    Hive.init(dir.path);
  });

  setUp(() async {
    // install() is a no-op off Android, which would make every case vacuous.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    storage = HiveChainPopPersistence();
    await storage.open();
    await storage.clearProgress();
    StorageLocator.install(storage);

    controller = StreamController<gs.PlayerData?>.broadcast();
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);
  });

  tearDown(() async {
    PlayGamesBootstrap.dispose();
    AchievementsLocator.uninstall();
    StorageLocator.uninstall();
    await controller.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test('sink starts unavailable, before auth has said anything', () {
    PlayGamesBootstrap.install(auth: auth);

    expect(PlayGamesBootstrap.sinkForTesting, isNotNull);
    expect(PlayGamesBootstrap.sinkForTesting!.isAvailable, isFalse);
  });

  test('sink becomes available when the player signs in', () async {
    PlayGamesBootstrap.install(auth: auth);
    await settled();

    controller.add(player);
    await pumpEventQueue();

    expect(PlayGamesBootstrap.sinkForTesting!.isAvailable, isTrue);
  });

  test('sink goes unavailable again when the player signs out', () async {
    PlayGamesBootstrap.install(auth: auth);
    await settled();

    controller.add(player);
    await pumpEventQueue();
    expect(PlayGamesBootstrap.sinkForTesting!.isAvailable, isTrue);

    controller.add(null);
    await pumpEventQueue();
    expect(PlayGamesBootstrap.sinkForTesting!.isAvailable, isFalse);
  });

  test('an auth stream error leaves the sink unavailable', () async {
    PlayGamesBootstrap.install(auth: auth);
    await settled();

    controller.addError(Exception('not signed in'));
    await pumpEventQueue();

    expect(PlayGamesBootstrap.sinkForTesting!.isAvailable, isFalse);
  });

  test('tracks locally even when Play Games never signs in', () async {
    PlayGamesBootstrap.install(auth: auth);
    await settled();

    controller.add(null);
    await pumpEventQueue();

    // Local tracking is unconditional: a signed-out player still earns
    // achievements, they simply are not published yet.
    expect(AchievementsLocator.instance.progress(), isNotEmpty);
  });

  test('dispose stops tracking auth so a late event cannot resurrect the sink',
      () async {
    PlayGamesBootstrap.install(auth: auth);
    final sink = PlayGamesBootstrap.sinkForTesting!;

    PlayGamesBootstrap.dispose();
    controller.add(player);
    await pumpEventQueue();

    expect(sink.isAvailable, isFalse);
  });
}
