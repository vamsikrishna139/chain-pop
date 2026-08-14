import 'package:flutter/material.dart';

import '../services/achievements/achievement_catalog.dart';
import '../services/achievements/achievement_rules.dart';
import '../services/achievements/achievements_locator.dart';
import '../theme/app_colors.dart';

/// Local achievements browser.
///
/// Reads the tracker's own evaluation, so it shows exactly what has been earned
/// on this device whether or not Play Games is signed in — which is the point
/// of the local-first design, and what makes the whole catalog playable and
/// verifiable before any Play Console setup exists.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late List<AchievementProgress> _entries;

  @override
  void initState() {
    super.initState();
    _entries = AchievementsLocator.instance.progress();
  }

  int get _earnedCount => _entries.where((e) => e.unlocked).length;

  int get _earnedPoints => _entries
      .where((e) => e.unlocked)
      .fold(0, (sum, e) => sum + e.def.points);

  @override
  Widget build(BuildContext context) {
    final grouped = <AchievementTrack, List<AchievementProgress>>{};
    for (final e in _entries) {
      grouped.putIfAbsent(e.def.track, () => []).add(e);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Achievements'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _SummaryCard(
            earned: _earnedCount,
            total: _entries.length,
            points: _earnedPoints,
            maxPoints: kAchievementTotalPoints,
          ),
          const SizedBox(height: 24),
          for (final track in AchievementTrack.values)
            if (grouped[track] case final rows?) ...[
              _TrackHeader(
                label: track.label,
                earned: rows.where((r) => r.unlocked).length,
                total: rows.length,
              ),
              const SizedBox(height: 8),
              for (final row in rows) _AchievementRow(entry: row),
              const SizedBox(height: 20),
            ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.earned,
    required this.total,
    required this.points,
    required this.maxPoints,
  });

  final int earned;
  final int total;
  final int points;
  final int maxPoints;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : earned / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$earned',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              Text(
                ' / $total',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const Spacer(),
              Text(
                '$points pts',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.starGold,
                ),
              ),
              Text(
                ' / $maxPoints',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: const AlwaysStoppedAnimation(AppColors.nodeDefault),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  const _TrackHeader({
    required this.label,
    required this.earned,
    required this.total,
  });

  final String label;
  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          Text(
            '$earned/$total',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.entry});

  final AchievementProgress entry;

  @override
  Widget build(BuildContext context) {
    final def = entry.def;
    final unlocked = entry.unlocked;

    // A hidden achievement stays hidden only until it is earned — the whole
    // point is the surprise, not permanent concealment.
    final concealed = def.hidden && !unlocked;
    final title = concealed ? 'Hidden achievement' : def.name;
    final subtitle =
        concealed ? 'Keep playing to reveal this one.' : def.description;

    final showBar = !concealed &&
        !unlocked &&
        def.kind == AchievementKind.incremental &&
        entry.current > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? AppColors.nodeDefault.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(
              unlocked
                  ? Icons.check_circle
                  : (concealed ? Icons.help_outline : Icons.circle_outlined),
              size: 20,
              color: unlocked
                  ? AppColors.nodeDefault
                  : Colors.white.withValues(alpha: 0.22),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: unlocked
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    Text(
                      '${def.points}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: unlocked
                            ? AppColors.starGold
                            : Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                if (showBar) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: entry.fraction,
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.07),
                            valueColor: AlwaysStoppedAnimation(
                              AppColors.nodeDefault.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.current}/${entry.target}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
