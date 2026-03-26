import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/chain_pop_game.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../services/storage_service.dart';
import 'win_overlay.dart';

/// Full-screen game view for a single level.
///
/// Requires both [level] and [difficulty] — neither can be omitted,
/// making it impossible to open the game in an undefined state.
class GameScreen extends StatefulWidget {
  final int level;
  final DifficultyMode difficulty;

  const GameScreen({
    super.key,
    required this.level,
    required this.difficulty,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ChainPopGame _game;
  int _jamCount = 0;
  bool _hasWon = false;
  late final Stopwatch _stopwatch;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _buildGame();
  }

  void _buildGame() {
    _game = ChainPopGame(
      levelId: widget.level,
      difficulty: widget.difficulty,
      onWin: _handleWin,
      onJam: _handleJam,
    );
  }

  void _handleJam() {
    if (!_hasWon) setState(() => _jamCount++);
  }

  Future<void> _handleWin() async {
    _stopwatch.stop();
    _hasWon = true;

    final earned = widget.difficulty.starsForJams(_jamCount);

    // Persist progress.
    await StorageService.saveStars(widget.difficulty, widget.level, earned);
    await StorageService.unlockLevel(widget.difficulty, widget.level + 1);

    if (!mounted) return;

    // Show the win overlay as a modal bottom sheet.
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => WinOverlay(
        levelId: widget.level,
        difficulty: widget.difficulty,
        stars: earned,
        jamCount: _jamCount,
        timeTaken: _stopwatch.elapsed,
        onMainMenu: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        onRetry: () {
          Navigator.of(context).pop(); // close sheet
          setState(() {
            _jamCount = 0;
            _hasWon = false;
            _stopwatch
              ..reset()
              ..start();
            _buildGame();
          });
        },
        onNextLevel: () {
          Navigator.of(context).pop(); // close sheet
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GameScreen(
                level: widget.level + 1,
                difficulty: widget.difficulty,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: Stack(
        children: [
          // Difficulty board tint (very subtle)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    accent.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Game canvas
          GameWidget(game: _game),

          // ── Top HUD ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Back button
                  _HudButton(
                    icon: Icons.arrow_back_ios_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  const Spacer(),

                  // Level label
                  Text(
                    'LEVEL ${widget.level}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),

                  const Spacer(),

                  // Difficulty pill
                  _DifficultyPill(difficulty: widget.difficulty),
                ],
              ),
            ),
          ),

          // ── Bottom controls ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Jam counter
                    _JamCounter(count: _jamCount),

                    // Hint button
                    _HudButton(
                      icon: Icons.lightbulb_outline_rounded,
                      label: 'HINT',
                      accent: accent,
                      onPressed: () => _game.showHint(),
                    ),

                    // Restart button
                    _HudButton(
                      icon: Icons.refresh_rounded,
                      label: 'RESET',
                      onPressed: () {
                        setState(() {
                          _jamCount = 0;
                          _hasWon = false;
                          _stopwatch
                            ..reset()
                            ..start();
                        });
                        _game.restart();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable HUD widgets ─────────────────────────────────────────────────────

class _HudButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color? accent;
  final VoidCallback onPressed;

  const _HudButton({
    required this.icon,
    required this.onPressed,
    this.label,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (accent ?? Colors.white).withOpacity(0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent ?? Colors.white70, size: 18),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(
                label!,
                style: TextStyle(
                  color: accent ?? Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DifficultyPill extends StatelessWidget {
  final DifficultyMode difficulty;
  const _DifficultyPill({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: difficulty.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: difficulty.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(difficulty.icon, size: 14, color: difficulty.color),
          const SizedBox(width: 6),
          Text(
            difficulty.label,
            style: TextStyle(
              color: difficulty.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _JamCounter extends StatelessWidget {
  final int count;
  const _JamCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block_rounded, color: Colors.redAccent, size: 16),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
