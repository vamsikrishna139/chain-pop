import 'package:flutter/material.dart';

import '../game/daily_challenge.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level_manager.dart';
import '../models/difficulty.dart';
import '../services/daily_challenge_play_policy.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'game_screen.dart';

/// Month grid for the **current local month**: days 1 → last, with days after today
/// locked. In-range days use [DailyChallengePlayPolicy] (free through today;
/// older days later via rewarded ads + [StorageService.isDailyUnlockedViaAd]).
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
  Future<void> _openDay(DateTime day) async {
    final now = DateTime.now();
    final allowed = await widget.policy.ensureCanStart(day, now);
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This puzzle needs a rewarded ad to unlock — hook up ads here.',
          ),
        ),
      );
      return;
    }

    final dayKey = DailyChallenge.dateKeyLocal(day);
    final level = LevelManager.getDailyChallenge(day);
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
          DailyChallenge.monthYearTitle(y, m),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Daily challenges',
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final dayNum = index - leading + 1;
              if (index < leading || dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day = DateTime(y, m, dayNum);
              final isFuture = day.isAfter(today);
              final stars = StorageService.dailyStarsForDayKey(
                DailyChallenge.dateKeyLocal(day),
              );
              final isToday = day == today;
              final inFree = widget.policy.isInFreeCalendarWindow(day, now);
              final adOk = StorageService.isDailyUnlockedViaAd(
                DailyChallenge.dateKeyLocal(day),
              );
              final lockedOutside = !inFree && !adOk;

              return _DayCell(
                day: dayNum,
                accent: accent,
                stars: stars,
                isToday: isToday,
                isFuture: isFuture,
                lockedOutside: lockedOutside,
                onTap: (isFuture || lockedOutside)
                    ? null
                    : () => _openDay(day),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final Color accent;
  final int stars;
  final bool isToday;
  final bool isFuture;
  final bool lockedOutside;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.accent,
    required this.stars,
    required this.isToday,
    required this.isFuture,
    required this.lockedOutside,
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
            opacity: isFuture || lockedOutside ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                      ] else if (lockedOutside) ...[
                        const SizedBox(width: 2),
                        Icon(Icons.ondemand_video_rounded, size: 12, color: accent),
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
