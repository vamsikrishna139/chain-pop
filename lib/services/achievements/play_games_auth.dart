import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:games_services/games_services.dart' as gs;

import '../crash_reporting.dart';

enum PlayGamesAuthState { unknown, signedOut, signedIn }

/// Outcome of an interactive sign-in attempt.
///
/// Carries the plugin's error code deliberately: that code is the only thing
/// that distinguishes a misconfigured OAuth client from a declined consent
/// dialog from a missing tester allowlist. A bare `bool` throws it away, which
/// is what made the original failure undiagnosable.
class PlayGamesSignInResult {
  const PlayGamesSignInResult({
    required this.success,
    this.code = '',
    this.message = '',
  });

  const PlayGamesSignInResult.ok() : this(success: true);

  final bool success;

  /// The plugin's `PluginError` code, or `unknown` for a non-platform throw.
  final String code;
  final String message;

  /// Short enough for a snackbar, specific enough to act on.
  String get displayText => message.isEmpty ? code : '$code: $message';

  @override
  String toString() => success
      ? 'PlayGamesSignInResult(ok)'
      : 'PlayGamesSignInResult($code, $message)';
}

/// Singleton owner of the games_services authentication stream.
///
/// The plugin's Android `Auth.onListen` runs its `isAuthenticated` check exactly
/// once per platform subscription, and the Dart side only opens that
/// subscription when its broadcast controller's listener count goes 0 -> 1. So
/// this class must be the SOLE subscriber to [gs.GameAuth.player] across the
/// whole app: any concurrent listener holds the count above zero and silently
/// turns [refresh] into a no-op that replays a stale cached value.
///
/// Enforced by test/play_games_isolation_test.dart.
class PlayGamesAuth extends ValueNotifier<PlayGamesAuthState> {
  PlayGamesAuth({Stream<gs.PlayerData?> Function()? authStreamFactory})
      : _authStreamFactory = authStreamFactory ?? (() => gs.GameAuth.player),
        super(PlayGamesAuthState.unknown);

  static final PlayGamesAuth instance = PlayGamesAuth();

  final Stream<gs.PlayerData?> Function() _authStreamFactory;
  StreamSubscription<gs.PlayerData?>? _sub;

  /// Cancels the current subscription and re-subscribes, forcing the plugin's
  /// 0 -> 1 listener transition so the native `isAuthenticated` check re-runs.
  ///
  /// The cancel is awaited because the platform `EventChannel` delivers
  /// `cancel` and `listen` as separate async messages: re-listening before the
  /// cancel lands can leave the native side without an event sink.
  Future<void> refresh() async {
    final previous = _sub;
    _sub = null;
    await previous?.cancel();
    _sub = _authStreamFactory().listen(
      (player) {
        _log('auth stream emitted player=${player?.displayName ?? 'null'}');
        value = player != null
            ? PlayGamesAuthState.signedIn
            : PlayGamesAuthState.signedOut;
      },
      onError: (Object error) {
        // The plugin reports "not signed in" as a stream error, so this is an
        // expected state rather than a fault: log it, don't report it.
        _log('auth stream error: $error');
        value = PlayGamesAuthState.signedOut;
      },
    );
  }

  /// Runs the interactive (account-picker) sign-in flow.
  ///
  /// Only ever called from an explicit user action: an unprompted call at
  /// bootstrap is what made the account chooser appear on every cold start.
  Future<PlayGamesSignInResult> signInInteractive() async {
    try {
      await gs.GameAuth.signIn();
      // The native sink pushes the new player, but re-subscribing guarantees we
      // observe it even if that push raced our subscription.
      await refresh();
      return const PlayGamesSignInResult.ok();
    } on PlatformException catch (e, stack) {
      final failure = PlayGamesSignInResult(
        success: false,
        code: e.code,
        message: e.message ?? '',
      );
      _log('interactive sign-in failed: $failure');
      recordNonFatal(e, stack);
      return failure;
    } catch (e, stack) {
      final failure = PlayGamesSignInResult(
        success: false,
        code: 'unknown',
        message: e.toString(),
      );
      _log('interactive sign-in failed: $failure');
      recordNonFatal(e, stack);
      return failure;
    }
  }

  /// Logs in every build mode. Debug-only logging is what kept the original
  /// sign-in failure invisible in the field.
  static void _log(String message) => debugPrint('[PlayGamesAuth] $message');

  /// Releases the platform subscription and returns to [PlayGamesAuthState.unknown].
  ///
  /// Dropping the last listener is what lets the plugin re-run its native check
  /// on the next [refresh], so this is also the teardown production code wants.
  Future<void> stop() async {
    final previous = _sub;
    _sub = null;
    await previous?.cancel();
    value = PlayGamesAuthState.unknown;
  }

  @visibleForTesting
  void disposeTesting() => unawaited(stop());
}
