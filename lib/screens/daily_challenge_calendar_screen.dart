import 'dart:async';

import 'package:flutter/material.dart';

import '../game/daily_challenge.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level.dart';
import '../game/levels/level_manager.dart';
import '../models/difficulty.dart';
import '../services/ads/ad_placements.dart';
import '../services/ads/ads_locator.dart';
import '../services/analytics/analytics_locator.dart';
import '../services/daily_challenge_play_policy.dart';
import '../services/storage/storage_locator.dart';
import '../theme/app_colors.dart';
import 'game/widgets/game_dialogs.dart';
import 'game_screen.dart';

/// Month grid for the **current local month**: future days are locked; **today** is
/// free. Earlier days replay after a one-time rewarded unlock per day when
/// [DailyChallengePlayPolicy.showRewardedAd] is set ([StorageLocator.instance.isDailyUnlockedViaAd]).
class DailyChallengeCalendarScreen extends StatefulWidget {
  final DailyChallengePlayPolicy policy;

  const DailyChallengeCalendarScreen({
    super.key,
    this.policy = DailyChallengePlayPolicy.standard,
  });

  @override
  State<DailyChallengeCalendarScreen> createState() =>
      _DailyChallengeCalendarScreenState();
}

class _DailyChallengeCalendarScreenState
    extends State<DailyChallengeCalendarScreen> {
  /// Day currently being generated, or null. Doubles as the re-entrancy guard:
  /// generation is now awaited, so without it a second tap during the wait
  /// would spawn a second isolate and push a second route.
  DateTime? _loadingDay;

  @override
  void initState() {
    super.initState();
    AnalyticsLocator.instance
        .logDailyOpen(dateStr: DateTime.now().toIso8601String());
    if (widget.policy.showRewardedAd != null) {
      unawaited(
        AdsLocator.instance.preloadRewarded(AdPlacements.dailyUnlockPast),
      );
    }
  }

  Future<void> _openDay(DateTime day) async {
    if (_loadingDay != null) return;
    final now = DateTime.now();

    if (widget.policy.needsRewardedUnlockBeforePlay(day, now)) {
      final accent = DifficultyMode.medium.color;
      final dateLabel = DailyChallenge.compactDateLabelFromKey(
          DailyChallenge.dateKeyLocal(day));
      final watch = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => PastDailyUnlockDialog(
          accent: accent,
          puzzleDateLabel: dateLabel,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          onWatchAd: () => Navigator.of(dialogContext).pop(true),
        ),
      );
      if (!mounted || watch != true) return;
    }

    final allowed = await widget.policy.ensureCanStart(day, now);
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.policy.showRewardedAd == null
                ? 'This day is locked.'
                : 'Watch the full ad to unlock this day, or try again if the ad did not load.',
          ),
        ),
      );
      return;
    }

    final dayKey = DailyChallenge.dateKeyLocal(day);

    // Generated on a worker isolate. The synchronous call that used to sit here
    // blocked the UI thread inside this tap handler, and on a pathological date
    // key that is measured in seconds, not milliseconds — key 20260819 takes
    // 4.4 s regardless of `dailyGenerationBudget`, because the budget cannot
    // preempt a single retrograde construction. Android's input-dispatch
    // timeout is 5 s, so the tap produced a real "Unbound isn't responding"
    // dialog. See [LevelManager.getDailyChallengeAsync].
    setState(() => _loadingDay = day);
    final LevelData level;
    try {
      level = await LevelManager.getDailyChallengeAsync(day);
    } finally {
      if (mounted) setState(() => _loadingDay = null);
    }
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          level: 0,
          difficulty: DifficultyMode.medium,
          isDailyChallenge: true,
          dailyDayKey: dayKey,
          fixedLevel: level,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final today = DateTime(y, m, now.day);
    final monthStart = DateTime(y, m, 1);
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final firstWeekday = monthStart.weekday;
    final leading = firstWeekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    final accent = DifficultyMode.medium.color;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    const weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Network Incidents · ${DailyChallenge.monthYearTitle(y, m)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Text(
                        'Network incidents',
                        style: tt.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Each day is a critical incident. Today is free. Earlier days replay after a short ad unlock.',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: weekLabels
                            .map(
                              (w) => Expanded(
                                child: Center(
                                  child: Text(
                                    w,
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: totalCells,
                        itemBuilder: (context, index) {
                          final dayNum = index - leading + 1;
                          if (index < leading ||
                              dayNum < 1 ||
                              dayNum > daysInMonth) {
                            return const SizedBox.shrink();
                          }
                          final day = DateTime(y, m, dayNum);
                          final isFuture = day.isAfter(today);
                          final stars =
                              StorageLocator.instance.dailyStarsForDayKey(
                            DailyChallenge.dateKeyLocal(day),
                          );
                          final isToday = day == today;
                          final inFree =
                              widget.policy.isInFreeCalendarWindow(day, now);
                          final adOk =
                              StorageLocator.instance.isDailyUnlockedViaAd(
                            DailyChallenge.dateKeyLocal(day),
                          );
                          final playable =
                              widget.policy.mayBePlayable(day, now);
                          final needsVideoBadge =
                              playable && !isFuture && !inFree && !adOk;

                          final enabled = playable && !isFuture;

                          return Semantics(
                            button: enabled,
                            label: _dayCellAccessibilityLabel(
                              dayNum: dayNum,
                              isToday: isToday,
                              isFuture: isFuture,
                              stars: stars,
                              needsVideoBadge: needsVideoBadge,
                              playable: playable,
                            ),
                            child: _DayCell(
                              day: dayNum,
                              accent: accent,
                              stars: stars,
                              isToday: isToday,
                              isFuture: isFuture,
                              needsVideoBadge: needsVideoBadge,
                              dimmed: isFuture || !playable,
                              onTap: enabled ? () => _openDay(day) : null,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                AdsLocator.instance.buildDailyChallengeBanner(context),
              ],
            ),
            // Generation is now awaited, so the tap no longer freezes the UI —
            // but on a slow date key it can still take seconds, and a tap that
            // visibly does nothing for that long reads as a broken app. The
            // veil also blocks further taps while the isolate works.
            if (_loadingDay != null)
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.background.withValues(alpha: 0.72),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: accent),
                        const SizedBox(height: 16),
                        Text(
                          'Building incident…',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _dayCellAccessibilityLabel({
  required int dayNum,
  required bool isToday,
  required bool isFuture,
  required int stars,
  required bool needsVideoBadge,
  required bool playable,
}) {
  final buf = StringBuffer('Day $dayNum');
  if (isToday) buf.write(', today');
  if (isFuture) buf.write(', locked future day');
  if (!playable) buf.write(', not playable');
  if (needsVideoBadge) buf.write(', unlock with video ad');
  buf.write(', $stars of 3 stars');
  return buf.toString();
}

class _DayCell extends StatelessWidget {
  final int day;
  final Color accent;
  final int stars;
  final bool isToday;
  final bool isFuture;
  final bool needsVideoBadge;
  final bool dimmed;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.accent,
    required this.stars,
    required this.isToday,
    required this.isFuture,
    required this.needsVideoBadge,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final border = isToday
        ? Border.all(color: accent, width: 2)
        : Border.all(color: Colors.white12);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: enabled
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.02),
            border: border,
          ),
          child: Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: isToday ? accent : Colors.white,
                        ),
                      ),
                      if (isFuture) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.lock_outline, size: 12, color: accent),
                      ] else if (needsVideoBadge) ...[
                        const SizedBox(width: 2),
                        Tooltip(
                          message: 'Unlock with a short ad',
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: accent.withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      final on = i < stars;
                      return Icon(
                        on ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 12,
                        color: on ? AppColors.starGold : Colors.white24,
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
