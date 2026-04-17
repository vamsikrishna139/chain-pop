import '../game/daily_challenge.dart';
import 'storage_service.dart';

/// Resolves whether a calendar day’s puzzle may be started.
///
/// **Free window:** the current local month from the 1st through today (inclusive).
/// Same board is always available for those days; stars remain per [dayKey].
///
/// **Older / other months (future UI):** when [showRewardedAd] is wired to a real
/// rewarded placement, a successful completion calls
/// [StorageService.markDailyUnlockedViaAd] so the day stays unlocked offline.
/// Until then, days outside the free window return false from [ensureCanStart]
/// unless already unlocked via storage.
class DailyChallengePlayPolicy {
  const DailyChallengePlayPolicy({this.showRewardedAd});

  /// `true` if the user finished watching a rewarded ad (or cancelled → `false`).
  final Future<bool> Function()? showRewardedAd;

  /// Default: no ad SDK — free window only; extend with `showRewardedAd:` at the app shell.
  static const DailyChallengePlayPolicy standard = DailyChallengePlayPolicy();

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Whether [day] lies in \[first of [now]'s month], [today]\] (local).
  bool isInFreeCalendarWindow(DateTime day, DateTime now) {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;
    final monthStart = DateTime(now.year, now.month, 1);
    return !d.isBefore(monthStart);
  }

  /// Whether this policy can ever allow [day] without leaving the app (free or already unlocked).
  bool mayBePlayable(DateTime day, DateTime now) {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;
    if (isInFreeCalendarWindow(d, now)) return true;
    return StorageService.isDailyUnlockedViaAd(DailyChallenge.dateKeyLocal(d));
  }

  /// Call before pushing [GameScreen] for a daily. Handles ad + persistence when needed.
  Future<bool> ensureCanStart(DateTime day, DateTime now) async {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;

    if (isInFreeCalendarWindow(d, now)) return true;

    final dayKey = DailyChallenge.dateKeyLocal(d);
    if (StorageService.isDailyUnlockedViaAd(dayKey)) return true;

    final ad = showRewardedAd;
    if (ad == null) return false;

    final watched = await ad();
    if (watched) await StorageService.markDailyUnlockedViaAd(dayKey);
    return watched;
  }
}
