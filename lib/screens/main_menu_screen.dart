import 'dart:async';

import 'package:flutter/material.dart';

import '../game/daily_challenge.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../game/levels/tutorial_levels.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../utils/progress_format.dart';
import 'daily_challenge_calendar_screen.dart';
import 'game_screen.dart';
import 'level_select_screen.dart';

/// Home hub: Material 3 surfaces, segmented difficulty, clear progression.
///
/// Progress model (unchanged in storage): [StorageService.highestUnlocked] is the
/// highest **level index you may play** on that track; we surface it as the
/// player's "frontier" and pair it with star mastery for motivation.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  late DifficultyMode _selected;
  late GameAudioController _audio;

  @override
  void initState() {
    super.initState();
    _selected = StorageService.selectedDifficulty;
    _audio = GameAudioController(voiceCount: 2);
  }

  @override
  void dispose() {
    unawaited(_audio.dispose());
    super.dispose();
  }

  Future<void> _selectDifficulty(DifficultyMode mode) async {
    if (_selected != mode && StorageService.gameSettings.soundEnabled) {
      unawaited(_audio.play(GameSfx.uiTap, playbackRate: 1.1));
    }
    await StorageService.setSelectedDifficulty(mode);
    if (!mounted) return;
    setState(() => _selected = mode);
  }

  void _play() {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(_audio.play(GameSfx.uiTap));
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => LevelSelectScreen(initialDifficulty: _selected),
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _selected = StorageService.selectedDifficulty;
          });
        });
  }

  void _openTutorial() {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(_audio.play(GameSfx.uiTap));
    }
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => GameScreen(
              level: 1,
              difficulty: DifficultyMode.easy,
              fixedLevel: tutorialLevels.first,
              isTutorial: true,
              tutorialIndex: 0,
            ),
          ),
        )
        .then((_) {
          if (!mounted) return;
          setState(() {});
        });
  }

  void _openDailyChallenge() {
    if (StorageService.gameSettings.soundEnabled) {
      unawaited(_audio.play(GameSfx.uiTap));
    }
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const DailyChallengeCalendarScreen(),
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  int _totalStarsForMode(DifficultyMode mode) {
    final frontier = StorageService.highestUnlocked(mode);
    var sum = 0;
    for (var i = 1; i <= frontier; i++) {
      sum += StorageService.stars(mode, i);
    }
    return sum;
  }

  Future<void> _confirmReset() async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.restart_alt_rounded, color: scheme.error),
        title: const Text('Reset all progress?'),
        content: const Text(
          'All stars, unlocks, and difficulty progress on this device will be cleared. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.clearProgress();
      if (!mounted) return;
      setState(() => _selected = StorageService.selectedDifficulty);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _selected.color;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: AppColors.background,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: scheme,
        splashFactory: InkSparkle.splashFactory,
      ),
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: cs.surface,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(cs.surface, accent, 0.08)!,
                    cs.surface,
                    Color.lerp(cs.surface, cs.surfaceContainerHighest, 0.35)!,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
              child: SafeArea(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _MainMenuHero(accent: accent),
                          const SizedBox(height: 28),
                          Text(
                            'Difficulty',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _DifficultySegmented(
                            selected: _selected,
                            onChanged: _selectDifficulty,
                          ),
                          const SizedBox(height: 20),
                          _ProgressionCard(
                            mode: _selected,
                            totalStars: _totalStarsForMode(_selected),
                          ),
                          const SizedBox(height: 12),
                          _CrossTrackStarsRow(
                            selected: _selected,
                            totalStarsFor: _totalStarsForMode,
                            onSelectMode: (m) => unawaited(_selectDifficulty(m)),
                          ),
                          const SizedBox(height: 20),
                          _DailyChallengeCard(
                            dayKey: DailyChallenge.dateKeyLocal(DateTime.now()),
                            starsToday: StorageService.dailyStarsForDayKey(
                              DailyChallenge.dateKeyLocal(DateTime.now()),
                            ),
                            onTap: _openDailyChallenge,
                          ),
                          const SizedBox(height: 28),
                          if (!StorageService.tutorialCompleted) ...[
                            FilledButton.icon(
                              onPressed: _openTutorial,
                              icon: const Icon(Icons.school_rounded, size: 26),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'Tutorial',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.tertiary,
                                foregroundColor: cs.onTertiary,
                                elevation: 2,
                                shadowColor: cs.tertiary.withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ] else ...[
                            Semantics(
                              button: true,
                              label: 'Replay tutorial',
                              excludeSemantics: true,
                              child: OutlinedButton.icon(
                                onPressed: _openTutorial,
                                icon: Icon(
                                  Icons.school_outlined,
                                  size: 22,
                                  color: cs.onSurfaceVariant,
                                ),
                                label: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    'Replay tutorial',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.onSurfaceVariant,
                                  side: BorderSide(
                                    color: cs.outline.withValues(alpha: 0.65),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton.icon(
                            onPressed: _play,
                            icon: const Icon(Icons.play_arrow_rounded, size: 26),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'Play',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.black,
                              elevation: 2,
                              shadowColor: accent.withValues(alpha: 0.45),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Semantics(
                              button: true,
                              label: 'Reset all progress',
                              hint: 'Long press to confirm',
                              child: InkWell(
                                onLongPress: _confirmReset,
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'Hold to reset all progress',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

class _MainMenuHero extends StatelessWidget {
  final Color accent;

  const _MainMenuHero({required this.accent});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'CHAIN POP',
          style: tt.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            height: 1.05,
            color: accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Clear the board in the right order.',
          style: tt.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tap arrows. No jams. Chain the pops.',
          style: tt.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Daily challenge (compact grid, global daily seed; leaderboard TBD) ─────

class _DailyChallengeCard extends StatelessWidget {
  final int dayKey;
  final int starsToday;
  final VoidCallback onTap;

  const _DailyChallengeCard({
    required this.dayKey,
    required this.starsToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = DifficultyMode.medium.color;

    return Card(
      elevation: 1,
      shadowColor: Colors.black54,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily challenge',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DailyChallenge.compactDateLabelFromKey(dayKey),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(3, (i) {
                        final on = i < starsToday;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            on
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 20,
                            color: on ? AppColors.starGold : Colors.white24,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Segmented difficulty (Material 3) ─────────────────────────────────────

class _DifficultySegmented extends StatelessWidget {
  final DifficultyMode selected;
  final Future<void> Function(DifficultyMode) onChanged;

  const _DifficultySegmented({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<DifficultyMode>(
      segments: [
        ButtonSegment<DifficultyMode>(
          value: DifficultyMode.easy,
          icon: Icon(DifficultyMode.easy.icon, size: 18),
          label: const Text('Easy'),
        ),
        ButtonSegment<DifficultyMode>(
          value: DifficultyMode.medium,
          icon: Icon(DifficultyMode.medium.icon, size: 18),
          label: const Text('Med'),
        ),
        ButtonSegment<DifficultyMode>(
          value: DifficultyMode.hard,
          icon: Icon(DifficultyMode.hard.icon, size: 18),
          label: const Text('Hard'),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (set) {
        if (set.isNotEmpty) unawaited(onChanged(set.first));
      },
      multiSelectionEnabled: false,
      emptySelectionAllowed: false,
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        ),
        shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ── Progression card ───────────────────────────────────────────────────────
//
// High levels (1000+): show comma-separated frontier, stretch bar aligned to the
// 20-level map pages, and compact lifetime stats — not "2847 / 3000" mastery.

class _ProgressionCard extends StatelessWidget {
  final DifficultyMode mode;
  final int totalStars;

  const _ProgressionCard({
    required this.mode,
    required this.totalStars,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final frontier = StorageService.highestUnlocked(mode);
    final accent = mode.color;
    final window = ProgressFormat.stretchWindow(frontier);
    final stretch = ProgressFormat.stretchStars(mode, frontier);
    final stretchFrac =
        stretch.cap > 0 ? (stretch.earned / stretch.cap).clamp(0.0, 1.0) : 0.0;
    final avg = ProgressFormat.avgStarsPerClearedStage(totalStars, frontier);

    return Card(
      elevation: 1,
      shadowColor: Colors.black54,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(mode.icon, color: accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${mode.label} track',
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              ProgressFormat.level(frontier),
              style: tt.headlineLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.05,
                color: accent,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Deepest stage you can open',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The map groups levels in pages of 20 — same as this bar.',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This stretch',
                    style: tt.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Levels ${ProgressFormat.level(window.start)} – ${ProgressFormat.level(window.end)}',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Stars here',
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${ProgressFormat.starsCompact(stretch.earned)} / ${stretch.cap} ★',
                        style: tt.labelMedium?.copyWith(
                          color: AppColors.starGold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: stretchFrac,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color.lerp(AppColors.starGold, accent, 0.35)!,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    label: 'Lifetime ★',
                    value: ProgressFormat.starsCompact(totalStars),
                    cs: cs,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatChip(
                    label: 'Avg / stage',
                    value: avg != null ? '${avg.toStringAsFixed(1)} ★' : '—',
                    cs: cs,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _StatChip({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Other tracks at a glance ─────────────────────────────────────────────────

class _CrossTrackStarsRow extends StatelessWidget {
  final DifficultyMode selected;
  final int Function(DifficultyMode) totalStarsFor;
  final void Function(DifficultyMode) onSelectMode;

  const _CrossTrackStarsRow({
    required this.selected,
    required this.totalStarsFor,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: DifficultyMode.values.map((m) {
        final stars = totalStarsFor(m);
        final isSel = m == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: isSel
                  ? m.color.withValues(alpha: 0.14)
                  : cs.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onSelectMode(m),
                borderRadius: BorderRadius.circular(14),
                splashColor: m.color.withValues(alpha: 0.2),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSel
                          ? m.color.withValues(alpha: 0.45)
                          : cs.outline.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: stars > 0 ? AppColors.starGold : cs.outline,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ProgressFormat.starsCompact(stars),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isSel ? m.color : cs.onSurface,
                        ),
                      ),
                      Text(
                        m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
