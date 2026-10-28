import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local (device-scheduled) reminders. There is no push/FCM in this app —
/// nothing is ever delivered from a server, so no notification token, topic or
/// payload ever leaves the device.
///
/// Two schedules, which is the shape almost every daily-puzzle game ships:
///
///  * **Daily reminder** — fires every day at [_reminderHour] local time and
///    points at the day's Network Incident. Repeats via
///    [DateTimeComponents.time] so a single schedule survives indefinitely.
///  * **Inactivity nudge** — a single shot [_idleNudgeDays] days after the last
///    time the player actually opened the game. Re-armed on every resume, so it
///    only ever fires for someone who has genuinely lapsed.
///
/// Scheduling deliberately uses [AndroidScheduleMode.inexactAllowWhileIdle].
/// Exact alarms would need `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`, which
/// Google Play restricts to alarm-clock and calendar apps; requesting either
/// from a puzzle game is a policy violation. A reminder that lands within the
/// system's batching window is the correct trade.
class NotificationService {
  static final NotificationService instance = NotificationService._internal();

  factory NotificationService() => instance;

  NotificationService._internal();

  static const _boxName = 'settings';
  static const _enabledKey = 'notifications_enabled';
  static const _lastActiveKey = 'notifications_last_active_ms';

  /// Local hour-of-day for the daily reminder. Evening, when a puzzle player is
  /// most likely to have a free minute and the day's incident is still open.
  static const int _reminderHour = 20;

  /// Days of silence before the re-engagement nudge fires.
  static const int _idleNudgeDays = 3;

  static const int _dailyReminderId = 0;
  static const int _idleNudgeId = 1;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationsEnabled = false;

  /// False when the platform has no notification support (web, desktop) or the
  /// plugin is not registered (unit tests). Every public method degrades to a
  /// no-op rather than throwing.
  bool _available = false;

  bool get notificationsEnabled => _notificationsEnabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final box = await Hive.openBox(_boxName);
    _notificationsEnabled = box.get(_enabledKey, defaultValue: false) as bool;

    if (kIsWeb || !Platform.isAndroid) return;

    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Falls back to UTC. The reminder still fires daily, just anchored to a
      // UTC wall clock; better than no reminder at all.
      debugPrint('NotificationService: timezone lookup failed: $e');
    }

    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _available = true;
    } catch (e) {
      debugPrint('NotificationService: plugin unavailable: $e');
      return;
    }

    // Re-arm on every cold start: reschedules survive reboot via the boot
    // receiver, but a reinstall, a timezone change or a revoked permission all
    // leave stale or missing schedules behind.
    if (_notificationsEnabled) {
      await _rescheduleAll();
    }
  }

  /// Requests the Android 13+ runtime notification permission. Returns whether
  /// the user granted it; enables reminders as a side effect when they do.
  Future<bool> requestPermissions() async {
    if (!_available) return false;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission() ?? false;

    if (granted) {
      await setNotificationsEnabled(true);
    }
    return granted;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final box = await Hive.openBox(_boxName);
    await box.put(_enabledKey, enabled);

    if (!_available) return;
    if (enabled) {
      await _rescheduleAll();
    } else {
      await cancelAllNotifications();
    }
  }

  /// Records that the player opened the game, and pushes the inactivity nudge
  /// back out to [_idleNudgeDays] from now. Call on resume.
  Future<void> noteActivity() async {
    final box = await Hive.openBox(_boxName);
    await box.put(_lastActiveKey, DateTime.now().millisecondsSinceEpoch);

    if (!_available || !_notificationsEnabled) return;
    await _scheduleIdleNudge();
  }

  Future<void> cancelAllNotifications() async {
    if (!_available) return;
    await _plugin.cancelAll();
  }

  Future<void> _rescheduleAll() async {
    await _plugin.cancelAll();
    await scheduleDailyReminder();
    await _scheduleIdleNudge();
  }

  Future<void> scheduleDailyReminder() async {
    if (!_available || !_notificationsEnabled) return;

    final copy = _dailyCopy(DateTime.now());
    await _plugin.zonedSchedule(
      _dailyReminderId,
      copy.$1,
      copy.$2,
      _nextInstanceOfHour(_reminderHour),
      _details(
        channelId: 'daily_challenge',
        channelName: 'Daily Challenge',
        channelDescription:
            'A once-a-day reminder that the new Network Incident is live.',
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_challenge',
    );
  }

  Future<void> _scheduleIdleNudge() async {
    if (!_available || !_notificationsEnabled) return;

    await _plugin.cancel(_idleNudgeId);

    final fireAt = _nextInstanceOfHour(
      _reminderHour,
      fromDay: tz.TZDateTime.now(tz.local).add(
        const Duration(days: _idleNudgeDays),
      ),
    );

    final copy = _idleCopy(DateTime.now());
    await _plugin.zonedSchedule(
      _idleNudgeId,
      copy.$1,
      copy.$2,
      fireAt,
      _details(
        channelId: 'comeback',
        channelName: 'Come back',
        channelDescription:
            'An occasional nudge if you have not played for a few days.',
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'comeback',
    );
  }

  NotificationDetails _details({
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
      ),
    );
  }

  /// The next occurrence of [hour]:00 local time, strictly in the future.
  static tz.TZDateTime _nextInstanceOfHour(int hour, {tz.TZDateTime? fromDay}) {
    final now = tz.TZDateTime.now(tz.local);
    final anchor = fromDay ?? now;
    var scheduled = tz.TZDateTime(
      tz.local,
      anchor.year,
      anchor.month,
      anchor.day,
      hour,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Day-seeded copy rotation, matching the day-key idiom used elsewhere in the
  /// app. The same device sees the same line on a given day, and a different
  /// line the next — so the reminder does not read like a stuck string.
  static (String, String) _dailyCopy(DateTime day) {
    const pool = <(String, String)>[
      ('A new incident is live', "Today's board is open. Find the order."),
      ('The grid reset', 'A fresh Network Incident just came online.'),
      ("Today's incident is waiting", 'One board. One clean solve.'),
      ('New board on the grid', "Today's incident is ready when you are."),
      ('Incident available', 'Clear it before the day rolls over.'),
    ];
    return pool[_dayIndex(day) % pool.length];
  }

  static (String, String) _idleCopy(DateTime day) {
    const pool = <(String, String)>[
      ('Your frontier is waiting', 'You left the board mid-run. Pick it up.'),
      ('Still unsolved', 'The next stage has not moved since you left.'),
      ('Come back to the grid', 'Your progress is exactly where you left it.'),
    ];
    return pool[_dayIndex(day) % pool.length];
  }

  static int _dayIndex(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
