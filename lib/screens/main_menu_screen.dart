import 'dart:async';
import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/game_audio.dart';
import '../services/game_sfx.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import 'level_select_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen>
    with SingleTickerProviderStateMixin {
  late DifficultyMode _selected;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late GameAudioController _audio;

  @override
  void initState() {
    super.initState();
    _selected = StorageService.selectedDifficulty;
    _audio = GameAudioController(voiceCount: 2);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
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
          MaterialPageRoute(
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

  @override
  Widget build(BuildContext context) {
    final accent = _selected.color;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final horizontalPad = compact ? 18.0 : 28.0;
    final pillGutter = compact ? 2.0 : 4.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Ambient background glow that follows difficulty color
          Positioned(
            top: -100,
            left: -80,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withOpacity(0.12), Colors.transparent],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ── Logo ────────────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: child,
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [accent, accent.withOpacity(0.6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: const Text(
                        'CHAIN\nPOP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          color: Colors.white, // masked by ShaderMask
                          height: 0.9,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        letterSpacing: compact ? 2.5 : 3.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                      children: [
                        TextSpan(
                          text: 'POP · ',
                          style: TextStyle(color: Colors.white.withOpacity(0.55)),
                        ),
                        TextSpan(
                          text: 'CHAIN',
                          style: TextStyle(
                            color: accent,
                            shadows: [
                              Shadow(
                                blurRadius: 12,
                                color: accent.withOpacity(0.45),
                              ),
                            ],
                          ),
                        ),
                        TextSpan(
                          text: ' · REPEAT',
                          style: TextStyle(color: Colors.white.withOpacity(0.55)),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: compact ? 4 : 6),
                  Text(
                    'Sweet cascades. Big energy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.28),
                      fontSize: compact ? 10 : 11,
                      letterSpacing: compact ? 1.2 : 2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Difficulty selector ──────────────────────────────────
                  const Text(
                    'DIFFICULTY',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: DifficultyMode.values
                        .map((mode) => Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: pillGutter),
                                child: _DifficultyPill(
                                  mode: mode,
                                  selected: _selected == mode,
                                  compact: compact,
                                  onTap: () => _selectDifficulty(mode),
                                ),
                              ),
                            ))
                        .toList(),
                  ),

                  const Spacer(),

                  // ── Progress summary ─────────────────────────────────────
                  _ProgressRow(difficulty: _selected),

                  const SizedBox(height: 32),

                  // ── Play button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withOpacity(0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _play,
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        label: const Text(
                          'PLAY',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Reset (long-press required to prevent accidents) ───────
                  Semantics(
                    button: true,
                    label: 'Reset all progress',
                    hint: 'Long press to open confirmation',
                    child: GestureDetector(
                      onLongPress: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: AppColors.surfaceDialog,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Reset all progress?',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            content: const Text('This cannot be undone.',
                                style: TextStyle(color: Colors.white54)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: const Text('CANCEL', style: TextStyle(color: Colors.white38))),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                child: const Text('RESET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await StorageService.clearProgress();
                          if (!mounted) return;
                          setState(() => _selected = StorageService.selectedDifficulty);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Hold to reset progress',
                          style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 11),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Difficulty pill ─────────────────────────────────────────────────────────

class _DifficultyPill extends StatelessWidget {
  final DifficultyMode mode;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _DifficultyPill({
    required this.mode,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = mode.color;
    final radius = BorderRadius.circular(16);
    final vPad = compact ? 11.0 : 14.0;
    final iconSize = compact ? 20.0 : 22.0;
    final labelSize = compact ? 9.5 : 11.0;

    return Semantics(
      button: true,
      selected: selected,
      label: '${mode.label} difficulty',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: color.withOpacity(0.22),
          highlightColor: color.withOpacity(0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: EdgeInsets.symmetric(vertical: vPad),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.18) : Colors.white.withOpacity(0.05),
              borderRadius: radius,
              border: Border.all(
                color: selected ? color.withOpacity(0.7) : Colors.white12,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16)]
                  : [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(mode.icon, color: selected ? color : Colors.white38, size: iconSize),
                SizedBox(height: compact ? 5 : 6),
                Text(
                  mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? color : Colors.white38,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: compact ? 0.6 : 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Progress + star summary row ────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  final DifficultyMode difficulty;
  const _ProgressRow({required this.difficulty});

  int _totalStars(DifficultyMode mode) {
    final highest = StorageService.highestUnlocked(mode);
    int sum = 0;
    for (int i = 1; i <= highest; i++) {
      sum += StorageService.stars(mode, i);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final highest = StorageService.highestUnlocked(difficulty);
    final accent = difficulty.color;

    return Column(
      children: [
        // Current difficulty progress
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(difficulty.icon, color: accent, size: 16),
              const SizedBox(width: 8),
              Text(
                '${difficulty.label}  ·  Lvl $highest unlocked',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Star totals across all difficulties
        Row(
          children: DifficultyMode.values.map((m) {
            final stars = _totalStars(m);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: m == difficulty ? m.color.withOpacity(0.4) : Colors.white12,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 14, color: stars > 0 ? AppColors.starGold : Colors.white24),
                      const SizedBox(height: 2),
                      Text(
                        '$stars',
                        style: TextStyle(
                          color: stars > 0 ? Colors.white70 : Colors.white24,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        m.label,
                        style: TextStyle(
                          color: m == difficulty ? m.color : Colors.white24,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
