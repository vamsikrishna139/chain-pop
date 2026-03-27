import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/storage_service.dart';
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

  @override
  void initState() {
    super.initState();
    _selected = StorageService.selectedDifficulty;

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
    super.dispose();
  }

  Future<void> _selectDifficulty(DifficultyMode mode) async {
    await StorageService.setSelectedDifficulty(mode);
    setState(() => _selected = mode);
  }

  void _play() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => LevelSelectScreen(initialDifficulty: _selected),
          ),
        )
        .then((_) => setState(() {
              _selected = StorageService.selectedDifficulty;
            }));
  }

  @override
  Widget build(BuildContext context) {
    final accent = _selected.color;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
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
              padding: const EdgeInsets.symmetric(horizontal: 28),
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

                  const SizedBox(height: 8),
                  const Text(
                    'EXTRACT · SOLVE · WIN',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w600,
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
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: _DifficultyPill(
                                  mode: mode,
                                  selected: _selected == mode,
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
                  GestureDetector(
                    onLongPress: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A22),
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
  final VoidCallback onTap;

  const _DifficultyPill({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = mode.color;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
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
            Icon(mode.icon, color: selected ? color : Colors.white38, size: 22),
            const SizedBox(height: 6),
            Text(
              mode.label,
              style: TextStyle(
                color: selected ? color : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
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
                style: TextStyle(color: Colors.white70, fontSize: 13),
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
                          size: 14, color: stars > 0 ? const Color(0xFFFFC371) : Colors.white24),
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

