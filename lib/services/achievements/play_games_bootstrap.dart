import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'achievement_tracker.dart';
import 'achievements_locator.dart';
import 'play_games_achievement_sink.dart';
import 'play_games_auth.dart';

/// Wires the achievement tracker to Google Play Games.
abstract final class PlayGamesBootstrap {
  PlayGamesBootstrap._();

  static _ResumeSyncObserver? _observer;
  static PlayGamesAchievementSink? _sink;
  static PlayGamesAuth _auth = PlayGamesAuth.instance;

  @visibleForTesting
  static PlayGamesAchievementSink? get sinkForTesting => _sink;

  /// Play Games is Android-only here: the catalog carries no Game Center ids,
  /// and the plugin's step APIs are Android-only.
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Installs the tracker, and listens for the background auto sign-in.
  static void install({PlayGamesAuth? auth}) {
    if (!_supported) {
      AchievementsLocator.install(AchievementTracker());
      return;
    }

    _auth = auth ?? PlayGamesAuth.instance;

    // recover() re-runs the platform auth handshake, which is what re-opens the
    // games client after a 26502.
    final sink = PlayGamesAchievementSink(onReconnect: () => _auth.refresh());
    _sink = sink;

    AchievementsLocator.install(AchievementTracker(sink: sink));

    // Drive the sink's availability off the single auth owner.
    _auth.addListener(_onAuthChanged);

    // Kick off the initial native check. Never awaited: cold start must not
    // block on a platform round trip.
    unawaited(_auth.refresh());

    _observer = _ResumeSyncObserver();
    WidgetsBinding.instance.addObserver(_observer!);
  }

  static void _onAuthChanged() {
    final state = _auth.value;
    final signedIn = state == PlayGamesAuthState.signedIn;

    _sink?.signedIn = signedIn;

    if (signedIn) {
      // Failures in either step are swallowed and retried next time.
      unawaited(_syncThenReconcile());
    }
  }

  /// Flushes the queue, then repairs the cursor.
  ///
  /// Order matters, and it is the opposite of what it looks like it should be.
  /// `reconcile()` reads through `Achievements.loadAchievements`, and on-device
  /// that read leaves the games client needing a reconnect: measured on a
  /// Pixel 8a, every write issued after it failed with 26502 and took ~1.5s to
  /// do so, while the identical batch with the read skipped succeeded in ~15ms
  /// a call. Dropping `forceRefresh` reduced the problem but did not remove it.
  ///
  /// So writes go first, against the clean client the sign-in just produced.
  /// Reconcile still runs — a cursor ahead of the backend strands achievements
  /// permanently — but it runs last, where poisoning the client only defers the
  /// next sync rather than losing this one. That next sync recovers on its own:
  /// the sink latches the dead connection and [AchievementTracker.sync] retries
  /// after a reconnect.
  /// Reconcile runs at most once per process. It repairs cursor drift, which
  /// happens rarely (a Play Games tester reset, a lost acknowledgement) and
  /// never mid-session — but its read costs a poisoned client every time, and
  /// recovery re-enters this path through the auth stream. Left ungated it
  /// re-poisons after every recovery, so each level completion pays a failed
  /// write plus a reconnect forever.
  static bool _reconciledThisProcess = false;

  static Future<void> _syncThenReconcile() async {
    final tracker = AchievementsLocator.instance;
    await tracker.sync();
    if (_reconciledThisProcess) return;
    _reconciledThisProcess = true;
    await tracker.reconcile();
  }

  /// Tests only.
  @visibleForTesting
  static void dispose() {
    _auth.removeListener(_onAuthChanged);
    unawaited(_auth.stop());
    _sink = null;
    _reconciledThisProcess = false;
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
  }
}

class _ResumeSyncObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final authState = PlayGamesBootstrap._auth.value;
      if (authState == PlayGamesAuthState.signedOut ||
          authState == PlayGamesAuthState.unknown) {
        // Only refresh when we aren't already confident of a working
        // connection: tearing down a live stream on every foreground costs a
        // platform round trip and reopens the cancel/listen race for nothing.
        unawaited(PlayGamesBootstrap._auth.refresh());
      } else if (authState == PlayGamesAuthState.signedIn) {
        unawaited(AchievementsLocator.instance.sync());
      }
    }
  }
}
