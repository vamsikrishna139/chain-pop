import 'achievement_catalog.dart';

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
}

/// In-memory sink for tests: records calls and can simulate an outage.
final class RecordingAchievementSink implements AchievementSink {
  RecordingAchievementSink({this.available = true});

  bool available;

  final List<({String id, int steps})> stepCalls = [];
  final List<String> unlockCalls = [];

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

  void _maybeThrow() {
    final e = throwOnce;
    if (e == null) return;
    throwOnce = null;
    throw e;
  }
}
