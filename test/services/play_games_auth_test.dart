import 'dart:async';

import 'package:chain_pop/services/achievements/play_games_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_services/games_services.dart' as gs;

/// The plugin only re-runs its native `isAuthenticated` check when its stream
/// listener count goes 0 -> 1, so [PlayGamesAuth.refresh] must genuinely drop
/// and reopen the subscription. These tests pin that, plus the state mapping,
/// through the injected stream factory.
void main() {
  const player = gs.PlayerData(playerID: 'p1', displayName: 'tester');

  late PlayGamesAuth auth;

  tearDown(() => auth.disposeTesting());

  test('starts unknown before the stream says anything', () {
    auth = PlayGamesAuth(
      authStreamFactory: () => const Stream<gs.PlayerData?>.empty(),
    );
    expect(auth.value, PlayGamesAuthState.unknown);
  });

  test('a player on the stream means signed in', () async {
    final controller = StreamController<gs.PlayerData?>.broadcast();
    addTearDown(controller.close);
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);

    await auth.refresh();
    controller.add(player);
    await pumpEventQueue();

    expect(auth.value, PlayGamesAuthState.signedIn);
  });

  test('a null player means signed out', () async {
    final controller = StreamController<gs.PlayerData?>.broadcast();
    addTearDown(controller.close);
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);

    await auth.refresh();
    controller.add(null);
    await pumpEventQueue();

    expect(auth.value, PlayGamesAuthState.signedOut);
  });

  test('a stream error means signed out, not a crash', () async {
    final controller = StreamController<gs.PlayerData?>.broadcast();
    addTearDown(controller.close);
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);

    await auth.refresh();
    controller.addError(Exception('not signed in'));
    await pumpEventQueue();

    expect(auth.value, PlayGamesAuthState.signedOut);
  });

  test('signing out after being signed in flips back', () async {
    final controller = StreamController<gs.PlayerData?>.broadcast();
    addTearDown(controller.close);
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);

    await auth.refresh();
    controller.add(player);
    await pumpEventQueue();
    expect(auth.value, PlayGamesAuthState.signedIn);

    controller.add(null);
    await pumpEventQueue();
    expect(auth.value, PlayGamesAuthState.signedOut);
  });

  test('refresh drops the old subscription and opens a new one', () async {
    // The whole point of refresh(): without a genuine 0 -> 1 transition the
    // plugin never re-checks and replays a stale cached value instead.
    var subscriptions = 0;
    var cancels = 0;

    auth = PlayGamesAuth(
      authStreamFactory: () {
        subscriptions++;
        final controller = StreamController<gs.PlayerData?>();
        controller.onCancel = () => cancels++;
        return controller.stream;
      },
    );

    await auth.refresh();
    expect(subscriptions, 1);
    expect(cancels, 0);

    await auth.refresh();
    expect(subscriptions, 2, reason: 'must re-subscribe');
    expect(cancels, 1, reason: 'must cancel the previous subscription first');
  });

  test('stop() releases the subscription and returns to unknown', () async {
    final controller = StreamController<gs.PlayerData?>.broadcast();
    addTearDown(controller.close);
    auth = PlayGamesAuth(authStreamFactory: () => controller.stream);

    await auth.refresh();
    controller.add(player);
    await pumpEventQueue();
    expect(auth.value, PlayGamesAuthState.signedIn);

    await auth.stop();
    expect(auth.value, PlayGamesAuthState.unknown);

    // No longer listening, so later events must not move the state.
    controller.add(player);
    await pumpEventQueue();
    expect(auth.value, PlayGamesAuthState.unknown);
  });
}
