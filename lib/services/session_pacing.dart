/// In-session escalation variants layered on top of a normally generated level.
/// v1 ships only [timed]; [relayStorm] / [blackout] are reserved for later.
enum SurgeKind {
  /// A tighter countdown than the level would normally get — a brief spike.
  timed,
}

/// Per-session gameplay pacing — drives the build→spike→relief rhythm that
/// per-level difficulty alone can't produce.
///
/// Mirrors [SessionCampaignStreak]'s isolate-static model **deliberately**, but
/// is kept entirely separate: ad cadence (interstitials) must never couple to
/// gameplay cadence (surges). Counts only **campaign** wins.
///
/// **Isolates / tests:** `_wins` is isolate-static. The default test runner is
/// single-isolate sequential, so the count accumulates across cases in a file;
/// inject a [SessionPacingController] for deterministic tests rather than
/// depending on the static. Surge only tightens the countdown + shows a label,
/// so suites that don't assert those are unaffected by leakage.
abstract final class SessionPacing {
  SessionPacing._();

  /// Every Nth consecutive campaign win this session makes the next level a
  /// surge.
  static const int surgeInterval = 4;

  /// Multiplier applied to a surge level's normal countdown (a 30% squeeze).
  static const double timedSurgeFactor = 0.7;

  /// Floor so a tightened countdown never becomes unwinnable.
  static const int timedSurgeFloorSec = 20;

  static int _wins = 0;

  static int get wins => _wins;

  static void reset() => _wins = 0;

  static void onWin() => _wins++;

  /// Pure surge rule — surge when the running win count lands on the interval.
  static SurgeKind? surgeForWinCount(int wins) =>
      (wins > 0 && wins % surgeInterval == 0) ? SurgeKind.timed : null;

  /// The surge (if any) for the level about to be played, given wins so far.
  static SurgeKind? surgeForUpcomingLevel() => surgeForWinCount(_wins);
}

/// Injectable façade so [GameScreen] tests observe pacing without the static.
abstract interface class SessionPacingController {
  void onCampaignWin();

  void resetSession();

  int get winsThisSession;

  /// Surge for the level about to be played (read at level start).
  SurgeKind? surgeForUpcomingLevel();
}

final class DefaultSessionPacingController implements SessionPacingController {
  const DefaultSessionPacingController();

  @override
  void onCampaignWin() => SessionPacing.onWin();

  @override
  void resetSession() => SessionPacing.reset();

  @override
  int get winsThisSession => SessionPacing.wins;

  @override
  SurgeKind? surgeForUpcomingLevel() => SessionPacing.surgeForUpcomingLevel();
}

const SessionPacingController defaultSessionPacingController =
    DefaultSessionPacingController();
