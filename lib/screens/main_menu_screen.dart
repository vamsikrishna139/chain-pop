import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../game/daily_challenge.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/ads/ad_service_factory.dart';
import '../services/game_audio_scope.dart';
import '../services/game_sfx.dart';
import '../game/levels/tutorial_levels.dart';
import '../services/storage/storage_locator.dart';
import '../theme/app_colors.dart';
import '../utils/progress_format.dart';
import 'achievements_screen.dart';
import 'daily_challenge_calendar_screen.dart';
import 'game_screen.dart';
import 'level_select_screen.dart';
import 'widgets/home_settings_sheet.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  late DifficultyMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = StorageLocator.instance.selectedDifficulty;
  }

  Future<void> _selectDifficulty(DifficultyMode mode) async {
    if (_selected != mode && StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(
        ChainPopAudioScope.of(context).play(GameSfx.uiTap, playbackRate: 1.1),
      );
    }
    await StorageLocator.instance.setSelectedDifficulty(mode);
    if (!mounted) return;
    setState(() => _selected = mode);
  }

  void _play() {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap));
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
            _selected = StorageLocator.instance.selectedDifficulty;
          });
        });
  }

  void _openTutorial() {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap));
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
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap));
    }
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DailyChallengeCalendarScreen(
          policy: createDailyChallengePlayPolicy(),
        ),
      ),
    )
        .then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  int _totalStarsForMode(DifficultyMode mode) {
    final frontier = StorageLocator.instance.highestUnlocked(mode);
    var sum = 0;
    for (var i = 1; i <= frontier; i++) {
      sum += StorageLocator.instance.stars(mode, i);
    }
    return sum;
  }

  Future<void> _confirmReset() async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDialog,
        icon: Icon(Icons.restart_alt_rounded, color: scheme.error),
        title: Text('Reset all progress?', style: GoogleFonts.rajdhani(fontWeight: FontWeight.bold)),
        content: Text(
          'All stars, unlocks, and difficulty progress on this device will be cleared. This cannot be undone.',
          style: GoogleFonts.rajdhani(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.rajdhani(color: Colors.white70)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text('Reset', style: GoogleFonts.rajdhani(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageLocator.instance.clearProgress();
      if (!mounted) return;
      setState(() => _selected = StorageLocator.instance.selectedDifficulty);
    }
  }

  void _openLevelSelect() {
    if (StorageLocator.instance.gameSettings.soundEnabled) {
      unawaited(ChainPopAudioScope.of(context).play(GameSfx.uiTap));
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
            _selected = StorageLocator.instance.selectedDifficulty;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final accent = _selected.color;
    final isHard = _selected == DifficultyMode.hard;
    final isMedium = _selected == DifficultyMode.medium;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top App Bar & Difficulty Temperature Switcher
              _buildTopBar(accent),
              const SizedBox(height: 12),
              _buildDifficultySwitcher(),
              
              // 2. Main Center Hero Progression Card & Play CTA
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildProgressionCard(accent, isHard, isMedium),
                    const SizedBox(height: 16),
                    _buildPlayButton(accent),
                  ],
                ),
              ),

              // 3. Bottom Cards: Daily Incident & Tutorial
              _buildDailyCard(),
              const SizedBox(height: 12),
              _buildTutorialCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: accent, blurRadius: 12),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'UNBOUND',
              style: GoogleFonts.rajdhani(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
                color: Colors.white,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _buildIconButton(
              icon: Icons.emoji_events_rounded,
              color: AppColors.starGold,
              onTap: () => openAchievements(context),
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.calendar_today_rounded,
              color: AppColors.accentEasy,
              onTap: _openDailyChallenge,
            ),
            const SizedBox(width: 8),
            _buildIconButton(
              icon: Icons.tune_rounded,
              color: Colors.white70,
              onTap: () {
                showHomeSettingsSheet(
                  context: context,
                  accent: _selected.color,
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIconButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  Widget _buildDifficultySwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: DifficultyMode.values.map((mode) {
          final isSelected = _selected == mode;
          final color = mode.color;
          return Expanded(
            child: GestureDetector(
              onTap: () => unawaited(_selectDifficulty(mode)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: -2)]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  mode.label.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.black : Colors.white54,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProgressionCard(Color accent, bool isHard, bool isMedium) {
    final frontier = StorageLocator.instance.highestUnlocked(_selected);
    final totalStars = _totalStarsForMode(_selected);
    final maxStars = frontier * 3;
    final progressFrac = maxStars > 0 ? (totalStars / maxStars).clamp(0.0, 1.0) : 0.0;
    
    final avg = ProgressFormat.avgStarsPerClearedStage(totalStars, frontier);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 30, spreadRadius: -10),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background Glow
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHard ? 'HARD · GATEWAY' : isMedium ? 'MEDIUM · SECTOR' : 'EASY · CAMPAIGN',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          letterSpacing: 1.5,
                          color: Colors.white54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$frontier',
                            style: GoogleFonts.chakraPetch(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'FRONTIER',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.starGold, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$totalStars / $maxStars',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.starGold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'AVG ${avg != null ? avg.toStringAsFixed(1) : "0.0"} ★',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Progress Bar
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: (progressFrac * 100).toInt(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [BoxShadow(color: accent, blurRadius: 10)],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 100 - (progressFrac * 100).toInt(),
                      child: const SizedBox(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Browse levels shortcut
              InkWell(
                onTap: _openLevelSelect,
                child: Container(
                  padding: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.grid_view_rounded, size: 14, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            'Browse All Levels',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(Color accent) {
    final frontier = StorageLocator.instance.highestUnlocked(_selected);
    return InkWell(
      onTap: _play,
      onLongPress: _confirmReset,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 28, spreadRadius: -4),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
            const SizedBox(width: 8),
            Text(
              'PLAY FRONTIER $frontier',
              style: GoogleFonts.chakraPetch(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyCard() {
    final dayKey = DailyChallenge.dateKeyLocal(DateTime.now());
    final starsToday = StorageLocator.instance.dailyStarsForDayKey(dayKey);
    final isCompleted = starsToday > 0;
    
    return InkWell(
      onTap: _openDailyChallenge,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentEasy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accentEasy.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.bolt_rounded, size: 16, color: AppColors.accentEasy),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Daily Incident',
                          style: GoogleFonts.rajdhani(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: isCompleted ? Colors.green.withValues(alpha: 0.2) : AppColors.accentMedium.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isCompleted ? 'COMPLETED' : 'FREE',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: isCompleted ? Colors.greenAccent : AppColors.accentMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DailyChallenge.compactDateLabelFromKey(dayKey),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialCard() {
    final tutorialCompleted = StorageLocator.instance.tutorialCompleted;
    
    return InkWell(
      onTap: _openTutorial,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tutorialCompleted ? Colors.transparent : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tutorialCompleted ? Colors.white.withValues(alpha: 0.1) : AppColors.accentEasy.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: tutorialCompleted ? Colors.white.withValues(alpha: 0.05) : AppColors.accentEasy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.explore_rounded,
                    size: 16,
                    color: tutorialCompleted ? Colors.white54 : AppColors.accentEasy,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tutorial: Fundamentals',
                      style: GoogleFonts.rajdhani(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: tutorialCompleted ? Colors.white70 : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tutorialCompleted ? 'Mastered' : 'Learn directional extraction rules',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Icon(
              tutorialCompleted ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: tutorialCompleted ? Colors.greenAccent : AppColors.accentEasy,
            ),
          ],
        ),
      ),
    );
  }
}
