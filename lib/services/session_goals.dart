/// One lightweight, session-long goal that gives mid-session purpose beyond
/// "next level". Derived entirely from counters the game already tracks (wins,
/// extraction streak, surges) — no economy, no persistence. v1 minimal.
enum SessionGoalKind { winThree, comboSix, clearSurge }

extension SessionGoalKindX on SessionGoalKind {
  int get target => switch (this) {
        SessionGoalKind.winThree => 3,
        SessionGoalKind.comboSix => 6,
        SessionGoalKind.clearSurge => 1,
      };

  String get label => switch (this) {
        SessionGoalKind.winThree => 'Win 3 levels',
        SessionGoalKind.comboSix => 'Reach a ×6 combo',
        SessionGoalKind.clearSurge => 'Clear a SURGE',
      };
}

/// Static session state (mirrors [SessionCampaignStreak] / [SessionPacing]).
/// Inject [SessionGoalsController] for deterministic tests.
abstract final class SessionGoals {
  SessionGoals._();

  static int _rotation = 0;
  static SessionGoalKind? _active;
  static int _progress = 0;
  static bool _done = false;

  static SessionGoalKind get active {
    return _active ??=
        SessionGoalKind.values[_rotation % SessionGoalKind.values.length];
  }

  static int get progress => _progress;
  static bool get isComplete => _done;

  static void resetSession() {
    if (_active != null) _rotation++;
    _active = null;
    _progress = 0;
    _done = false;
  }

  /// Records a win (and whether it was a surge level). Returns true iff this
  /// call *completes* the active goal (fires once).
  static bool recordWin({required bool surge}) {
    if (_done) return false;
    switch (active) {
      case SessionGoalKind.winThree:
        _progress++;
      case SessionGoalKind.clearSurge:
        if (surge) _progress++;
      case SessionGoalKind.comboSix:
        break;
    }
    return _checkDone();
  }

  /// Records the current extraction streak. Returns true iff it completes the
  /// active goal.
  static bool recordStreak(int streak) {
    if (_done) return false;
    if (active == SessionGoalKind.comboSix && streak > _progress) {
      _progress = streak;
    }
    return _checkDone();
  }

  static bool _checkDone() {
    if (!_done && _progress >= active.target) {
      _done = true;
      return true;
    }
    return false;
  }
}

/// Injectable façade so [GameScreen] tests observe goals without the static.
abstract interface class SessionGoalsController {
  SessionGoalKind get activeGoal;
  int get progress;
  int get target;
  bool get isComplete;
  bool recordWin({required bool surge});
  bool recordStreak(int streak);
  void resetSession();
}

final class DefaultSessionGoalsController implements SessionGoalsController {
  const DefaultSessionGoalsController();

  @override
  SessionGoalKind get activeGoal => SessionGoals.active;
  @override
  int get progress => SessionGoals.progress.clamp(0, activeGoal.target);
  @override
  int get target => SessionGoals.active.target;
  @override
  bool get isComplete => SessionGoals.isComplete;
  @override
  bool recordWin({required bool surge}) => SessionGoals.recordWin(surge: surge);
  @override
  bool recordStreak(int streak) => SessionGoals.recordStreak(streak);
  @override
  void resetSession() => SessionGoals.resetSession();
}

const SessionGoalsController defaultSessionGoalsController =
    DefaultSessionGoalsController();
