import 'achievement_catalog.dart';

/// Thrown by a sink when the backend connection has gone stale rather than the
/// write being rejected on its merits.
///
/// Play Games reports this as `26502 CLIENT_RECONNECT_REQUIRED`. It is not a
/// failure of the achievement: the games client buffers the write locally and
/// flushes it once the connection recovers, so the data is not lost. What it
/// does mean is that every subsequent call on the same client will fail the
/// same way — and each one costs ~1.5s versus ~15ms on a healthy client — so
/// the caller should stop the batch instead of grinding through it.
///
/// Kept distinct from a generic failure so the tracker can skip crash
/// reporting for it: reporting a transient reconnect as an error buries real
/// faults under one report per level completion per user.
final class AchievementConnectionLost implements Exception {
  const AchievementConnectionLost(this.cause);

  /// The underlying platform error, kept for diagnosis.
  final Object cause;

  @override
  String toString() => 'AchievementConnectionLost($cause)';
}

/// Destination for achievement state that lives outside the device.
///
/// Deliberately narrow, and deliberately *absolute*: [setSteps] reports the
/// total, never a delta. Play Games' own `increment()` applies a delta, which
/// is not idempotent — a retry, a crash between the local write and the sync,
/// a reinstall, or a second device each inflate the remote counter with no way
/// to repair it. `setSteps` is documented to never decrease existing progress,
/// so replaying the whole queue from local state is always safe and always
/// converges.
abstract interface class AchievementSink {
  /// Whether the sink can currently reach its backend. When false the tracker
  /// keeps writing locally and defers the queue.
  bool get isAvailable;

  /// Reports absolute progress. [steps] is already clamped to the
  /// achievement's declared step count.
  Future<void> setSteps(AchievementDef def, int steps);

  /// Marks a standard (single-step) achievement earned.
  Future<void> unlock(AchievementDef def);

  /// Absolute progress the backend currently holds, keyed by [AchievementDef.id].
  ///
  /// Used to repair a sync cursor that has drifted ahead of the backend. That
  /// drift is not hypothetical: Play Games resets tester progress on
  /// unpublished titles, and a push can be acknowledged locally and then lost.
  /// Once the cursor is ahead, [setSteps] is never called again for that entry
  /// and the achievement is stranded forever.
  ///
  /// Returns null when the backend cannot be read; the caller then leaves the
  /// cursor alone rather than guessing.
  Future<Map<String, int>?> remoteProgress();

  /// Attempts to re-establish a connection reported lost via
  /// [AchievementConnectionLost]. Returns whether the sink believes it is
  /// usable again. Implementations that cannot recover return false.
  Future<bool> recover();
}

/// Sink used until Play Games is wired up, and in every test.
///
/// Reports itself unavailable, so the tracker records progress locally and
/// leaves the sync cursor untouched — meaning the first real sink to appear
/// replays the player's entire history rather than starting from now.
final class NoOpAchievementSink implements AchievementSink {
  const NoOpAchievementSink();

  @override
  bool get isAvailable => false;

  @override
  Future<void> setSteps(AchievementDef def, int steps) async {}

  @override
  Future<void> unlock(AchievementDef def) async {}

  @override
  Future<Map<String, int>?> remoteProgress() async => null;

  @override
  Future<bool> recover() async => false;
}

/// In-memory sink for tests: records calls and can simulate an outage.
final class RecordingAchievementSink implements AchievementSink {
  RecordingAchievementSink({this.available = true});

  bool available;

  final List<({String id, int steps})> stepCalls = [];
  final List<String> unlockCalls = [];

  /// What [remoteProgress] should report. Null means "backend unreadable".
  Map<String, int>? remote;

  /// When set, the next call throws it once — for exercising the retry path.
  Object? throwOnce;

  @override
  bool get isAvailable => available;

  @override
  Future<void> setSteps(AchievementDef def, int steps) async {
    _maybeThrow();
    stepCalls.add((id: def.id, steps: steps));
  }

  @override
  Future<void> unlock(AchievementDef def) async {
    _maybeThrow();
    unlockCalls.add(def.id);
  }

  @override
  Future<Map<String, int>?> remoteProgress() async => remote;

  /// How many times [recover] was called, and what it should report.
  int recoverCalls = 0;
  bool recoverSucceeds = true;

  @override
  Future<bool> recover() async {
    recoverCalls++;
    return recoverSucceeds;
  }

  void _maybeThrow() {
    final e = throwOnce;
    if (e == null) return;
    throwOnce = null;
    throw e;
  }
}
