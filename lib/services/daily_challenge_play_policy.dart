import '../game/daily_challenge.dart';
import 'ads/ad_debug_log.dart';
import 'storage_service.dart';

/// Resolves whether a calendar day’s puzzle may be started.
///
/// **Free window:** **today** only (local date). Today’s board is always available;
/// stars remain per [dayKey].
///
/// **Earlier days in the month:** require a one-time rewarded unlock per [dayKey]
/// when [showRewardedAd] is set. A successful watch calls
/// [StorageService.markDailyUnlockedViaAd].
///
/// Without [showRewardedAd], days before today in the month are not playable
/// unless already marked unlocked in storage.
class DailyChallengePlayPolicy {
  const DailyChallengePlayPolicy({this.showRewardedAd});

  /// `true` if the user finished watching a rewarded ad (or cancelled → `false`).
  final Future<bool> Function()? showRewardedAd;

  /// Default: no rewarded path — only [isInFreeCalendarWindow] (today) is playable.
  static const DailyChallengePlayPolicy standard = DailyChallengePlayPolicy();

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  /// Whether [day] is playable without an ad (local **today** only).
  bool isInFreeCalendarWindow(DateTime day, DateTime now) {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;
    return d == today;
  }

  /// Past days before [now] that still need a rewarded unlock (not today, not yet stored).
  ///
  /// Use this to show an explanatory dialog **before** calling [ensureCanStart], which
  /// presents the ad immediately.
  bool needsRewardedUnlockBeforePlay(DateTime day, DateTime now) {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;
    if (isInFreeCalendarWindow(d, now)) return false;
    final dayKey = DailyChallenge.dateKeyLocal(d);
    if (StorageService.isDailyUnlockedViaAd(dayKey)) return false;
    return showRewardedAd != null;
  }

  /// Whether [day] may appear as tappable (today, already ad-unlocked, or ads wired).
  bool mayBePlayable(DateTime day, DateTime now) {
    final d = _dateOnly(day);
    final today = _dateOnly(now);
    if (d.isAfter(today)) return false;
    if (isInFreeCalendarWindow(d, now)) return true;
    if (StorageService.isDailyUnlockedViaAd(DailyChallenge.dateKeyLocal(d))) {
      return true;
    }
    return showRewardedAd != null;
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

    adDebug('daily-calendar: showing rewarded for unlock dayKey=$dayKey');
    final watched = await ad();
    adDebug('daily-calendar: rewarded unlock result=$watched dayKey=$dayKey');
    if (watched) await StorageService.markDailyUnlockedViaAd(dayKey);
    return watched;
  }
}
