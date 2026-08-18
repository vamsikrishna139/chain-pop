import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:games_services/games_services.dart' as gs;

import 'achievement_catalog.dart';
import 'achievement_sink.dart';

/// [AchievementSink] backed by Google Play Games.
///
/// Absolute-only by construction: incremental entries go through
/// `Achievements.setSteps`, which Google documents as never reducing existing
/// progress, so replaying the whole local history is safe and converges.
/// `Achievements.increment` is deliberately never called — it applies a delta,
/// and a retry, a reinstall or a second device would inflate the remote counter
/// with no way to repair it. See [AchievementSink] for the full rationale.
///
/// [isAvailable] tracks sign-in, which the caller drives from
/// [gs.GameAuth.player]. Until the player signs in the tracker keeps writing
/// locally and leaves its sync cursor untouched, so nothing is lost.
final class PlayGamesAchievementSink implements AchievementSink {
  PlayGamesAchievementSink({
    String? Function(AchievementDef)? idResolver,
    Future<void> Function()? onReconnect,
  })  : _resolveId = idResolver ?? _defaultIdResolver,
        _onReconnect = onReconnect;

  /// Re-runs the platform auth handshake. Injected by the bootstrap so the sink
  /// does not have to own the auth singleton.
  final Future<void> Function()? _onReconnect;

  static String? _defaultIdResolver(AchievementDef def) =>
      def.playGamesId ?? playGamesIds[def.id];

  /// Mirrors the tracker's own resolver so both agree on which entries are
  /// publishable. Injectable for tests.
  final String? Function(AchievementDef) _resolveId;

  bool _signedIn = false;

  /// Driven by the Play Games auth stream.
  set signedIn(bool value) => _signedIn = value;

  /// Play Games' status code for "this client handle is stale, reconnect".
  /// Matched on the message because the plugin folds the numeric status into
  /// the message and reuses a generic code per call site
  /// (`failed_to_send_achievement`, `failed_to_set_achievement_steps`).
  static bool _isConnectionLost(Object e) =>
      e is PlatformException &&
      (e.message?.contains('CLIENT_RECONNECT_REQUIRED') ?? false);

  /// Runs [action], translating a stale-client platform error into
  /// [AchievementConnectionLost] so the tracker can stop the batch and skip
  /// crash reporting.
  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (_isConnectionLost(e)) throw AchievementConnectionLost(e);
      rethrow;
    }
  }

  /// Play Games achievements are Android-only in this plugin: `setSteps` and
  /// `increment` are no-ops elsewhere, and Game Center uses a separate id
  /// namespace the catalog does not carry yet.
  static bool get _supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isAvailable => _signedIn && _supportedPlatform;

  @override
  Future<void> setSteps(AchievementDef def, int steps) async {
    final id = _resolveId(def);
    // Google rejects a step count of zero; the tracker already filters those,
    // but the sink stays defensive because a failure here is silent.
    if (id == null || steps <= 0) return;
    await _guarded(() => gs.Achievements.setSteps(
          achievement: gs.Achievement(androidID: id, steps: steps),
        ));
  }

  @override
  Future<void> unlock(AchievementDef def) async {
    final id = _resolveId(def);
    if (id == null) return;
    await _guarded(() => gs.Achievements.unlock(
          achievement: gs.Achievement(androidID: id, percentComplete: 100),
        ));
  }

  @override
  Future<bool> recover() async {
    if (_onReconnect == null) return false;
    try {
      await _onReconnect();
    } catch (e) {
      if (kDebugMode) debugPrint('[Sink] recover failed: $e');
      return false;
    }
    // Reported optimistically: re-listening to the auth stream re-runs the
    // native handshake, but the fresh player arrives asynchronously and may not
    // change the notifier's value, so there is nothing reliable to wait on. The
    // caller's single retry is the real test — if the client is still stale it
    // throws again and the batch stops, at a cost of one extra call.
    return isAvailable;
  }

  @override
  Future<Map<String, int>?> remoteProgress() async {
    try {
      // ignoreImages is mandatory, not an optimisation: the plugin's image path
      // awaits one ImageManager callback per achievement on the main dispatcher
      // with no timeout, and never returns if any of them fails to fire.
      // forceRefresh is deliberately off: on-device it left the games client in
      // a state where every subsequent write failed with
      // 26502 CLIENT_RECONNECT_REQUIRED. Cached values are good enough here —
      // rewinding a cursor too far only causes a redundant setSteps, which is
      // absolute and never reduces remote progress.
      final items = await gs.Achievements
          .loadAchievements(ignoreImages: true)
          .timeout(const Duration(seconds: 10));
      if (items == null) return null;

      // Remote is keyed by Play Console id; the cursor is keyed by catalog id.
      final byPlayId = <String, int>{
        for (final item in items)
          item.id: item.unlocked
              ? (item.totalSteps > 0 ? item.totalSteps : 1)
              : item.completedSteps,
      };

      final byCatalogId = <String, int>{};
      for (final def in kAchievementCatalog) {
        final playId = _resolveId(def);
        if (playId == null) continue;
        final steps = byPlayId[playId];
        if (steps != null) byCatalogId[def.id] = steps;
      }
      return byCatalogId;
    } catch (e) {
      if (kDebugMode) debugPrint('[Sink] remoteProgress failed: $e');
      return null;
    }
  }
}
