import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/chain_pop_game.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../game/levels/level_manager.dart';
import '../models/difficulty.dart';
import '../services/storage_service.dart';
import 'win_overlay.dart';

/// Full-screen game view for a single level.
///
/// Features:
///  • Progress bar — thin top bar showing nodes cleared/total
///  • Countdown timer — Medium: 6 s/node [60–240 s], Hard: 4 s/node [45–180 s]
///  • Ghost hints — Easy only: auto-highlights next free node after 4 s of inactivity
///  • Jam counter, Hint button, Restart button in bottom HUD
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

  // ── Progress tracking ────────────────────────────────────────────────────
  int _totalNodes = 0;
  int _removedNodes = 0;

  // ── Jam tracking (for star calculation) ─────────────────────────────────
  int _jamCount = 0;
  bool _hasWon = false;
  late final Stopwatch _stopwatch;

  // ── Countdown timer (Medium / Hard only) ─────────────────────────────────
  int? _timeLeftSec;       // null → Easy (no timer)
  int? _timeLimitSec;      // the original limit, kept for progress bar
  Timer? _countdownTimer;

  // ── Ghost hint timer (Easy only) ─────────────────────────────────────────
  Timer? _ghostHintTimer;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();

    // Pre-compute total nodes deterministically (same seed = same level).
    _totalNodes = LevelManager.getLevel(widget.level, mode: widget.difficulty)
        .nodes
        .length;

    // Compute time limit if applicable.
    _timeLimitSec = _computeTimeLimit(widget.difficulty, _totalNodes);
    _timeLeftSec = _timeLimitSec;

    _buildGame();
    _startCountdown();
    _resetGhostHintTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    super.dispose();
  }

  // ── Time limit computation ────────────────────────────────────────────────

  /// Returns the time limit in seconds for [mode], or null for Easy.
  ///
  /// - Medium: 6 s × nodeCount, clamped to [60, 240]
  /// - Hard:   4 s × nodeCount, clamped to [45, 180]
  static int? _computeTimeLimit(DifficultyMode mode, int nodeCount) {
    switch (mode) {
      case DifficultyMode.easy:   return null;
      case DifficultyMode.medium: return (nodeCount * 6).clamp(60, 240);
      case DifficultyMode.hard:   return (nodeCount * 4).clamp(45, 180);
    }
  }

  // ── Game construction ─────────────────────────────────────────────────────

  void _buildGame() {
    _game = ChainPopGame(
      levelId: widget.level,
      difficulty: widget.difficulty,
      onWin: _handleWin,
      onJam: _handleJam,
      onNodeRemoved: _handleNodeRemoved,
    );
  }

  // ── Event handlers ────────────────────────────────────────────────────────

  void _handleJam() {
    if (_hasWon) return;
    setState(() => _jamCount++);
    _resetGhostHintTimer(); // any interaction resets the ghost hint delay
  }

  void _handleNodeRemoved(int removed, int total) {
    if (!mounted) return;
    setState(() {
      _removedNodes = removed;
      _totalNodes = total;
    });
    _resetGhostHintTimer(); // successful tap resets the ghost hint delay
  }

  Future<void> _handleWin() async {
    _stopwatch.stop();
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _hasWon = true;
    setState(() {}); // update UI to show 100% progress

    final earned = widget.difficulty.starsForJams(_jamCount);
    await StorageService.saveStars(widget.difficulty, widget.level, earned);
    await StorageService.unlockLevel(widget.difficulty, widget.level + 1);

    if (!mounted) return;

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
        onMainMenu: () => Navigator.of(context).popUntil((r) => r.isFirst),
        onRetry: _startRetry,
        onNextLevel: () {
          Navigator.of(context).pop();
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

  void _handleTimeUp() {
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    if (_hasWon || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TimeUpDialog(
        difficulty: widget.difficulty,
        onRetry: () {
          Navigator.of(context).pop();
          _startRetry();
        },
        onMenu: () => Navigator.of(context).popUntil((r) => r.isFirst),
      ),
    );
  }

  void _startRetry() {
    Navigator.of(context, rootNavigator: true).pop(); // close sheet, if open
    setState(() {
      _jamCount = 0;
      _hasWon = false;
      _removedNodes = 0;
      _timeLeftSec = _timeLimitSec;
      _stopwatch
        ..reset()
        ..start();
    });
    _countdownTimer?.cancel();
    _ghostHintTimer?.cancel();
    _game.restart();
    _startCountdown();
    _resetGhostHintTimer();
  }

  // ── Countdown (Medium / Hard) ─────────────────────────────────────────────

  void _startCountdown() {
    if (_timeLimitSec == null) return; // Easy: no timer

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _hasWon) return;
      setState(() {
        _timeLeftSec = ((_timeLeftSec ?? _timeLimitSec!) - 1).clamp(0, _timeLimitSec!);
      });
      if (_timeLeftSec == 0) {
        _countdownTimer?.cancel();
        _handleTimeUp();
      }
    });
  }

  // ── Ghost hints (Easy only) ───────────────────────────────────────────────

  void _resetGhostHintTimer() {
    if (widget.difficulty != DifficultyMode.easy) return;
    _ghostHintTimer?.cancel();
    _ghostHintTimer = Timer(const Duration(seconds: 4), () {
      if (!_hasWon && mounted) _game.showHint();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;
    final progress = _totalNodes > 0 ? _removedNodes / _totalNodes : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: Stack(
        children: [
          // Ambient board tint
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [accent.withOpacity(0.05), Colors.transparent],
                ),
              ),
            ),
          ),

          // Flame canvas
          GameWidget(game: _game),

          // ── Progress bar (full width, top) ────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _ProgressBar(progress: progress, color: accent),
          ),

          // ── Top HUD ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _HudButton(
                        icon: Icons.arrow_back_ios_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      // Level + difficulty
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'LEVEL ${widget.level}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _DifficultyPill(difficulty: widget.difficulty),
                        ],
                      ),
                      const Spacer(),
                      // Timer badge (Medium/Hard) or hint button (Easy)
                      if (_timeLimitSec != null && _timeLeftSec != null)
                        _TimerBadge(
                          timeLeftSec: _timeLeftSec!,
                          timeLimitSec: _timeLimitSec!,
                          color: accent,
                        )
                      else
                        const SizedBox(width: 56),
                    ],
                  ),
                  // Node progress indicator text
                  const SizedBox(height: 4),
                  Text(
                    '$_removedNodes / $_totalNodes nodes',
                    style: TextStyle(
                      color: accent.withOpacity(0.7),
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                    _JamCounter(count: _jamCount),
                    _HudButton(
                      icon: Icons.lightbulb_outline_rounded,
                      label: 'HINT',
                      accent: accent,
                      onPressed: () {
                        _game.showHint();
                        _resetGhostHintTimer();
                      },
                    ),
                    _HudButton(
                      icon: Icons.refresh_rounded,
                      label: 'RESET',
                      onPressed: _startRetry,
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

// ── Progress bar ─────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final Color color;

  const _ProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        return Stack(
          children: [
            // Track
            Container(height: 4, color: Colors.white.withOpacity(0.06)),
            // Fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: 4,
              width: constraints.maxWidth * progress.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.7), color],
                ),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Timer badge ──────────────────────────────────────────────────────────────

class _TimerBadge extends StatelessWidget {
  final int timeLeftSec;
  final int timeLimitSec;
  final Color color;

  const _TimerBadge({
    required this.timeLeftSec,
    required this.timeLimitSec,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Turn amber at 40%, red at 20%
    final fraction = timeLimitSec > 0 ? timeLeftSec / timeLimitSec : 0.0;
    final displayColor = fraction < 0.20
        ? const Color(0xFFFF5F6D)
        : fraction < 0.40
            ? const Color(0xFFFFC371)
            : color;

    final mins = (timeLeftSec ~/ 60).toString();
    final secs = (timeLeftSec % 60).toString().padLeft(2, '0');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: displayColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: displayColor.withOpacity(0.5)),
        boxShadow: fraction < 0.20
            ? [BoxShadow(color: displayColor.withOpacity(0.4), blurRadius: 10)]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: displayColor),
          const SizedBox(width: 5),
          Text(
            '$mins:$secs',
            style: TextStyle(
              color: displayColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Time-up dialog ──────────────────────────────────────────────────────────

class _TimeUpDialog extends StatelessWidget {
  final DifficultyMode difficulty;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  const _TimeUpDialog({
    required this.difficulty,
    required this.onRetry,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final accent = difficulty.color;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withOpacity(0.3)),
      ),
      title: Column(
        children: [
          Icon(Icons.timer_off_rounded, color: accent, size: 48),
          const SizedBox(height: 12),
          const Text(
            "TIME'S UP!",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      content: Text(
        "The clock ran out. Try again?",
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withOpacity(0.6)),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: onMenu,
          child: const Text(
            'MENU',
            style: TextStyle(color: Colors.white38),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'RETRY',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared HUD widgets ────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: difficulty.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: difficulty.color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(difficulty.icon, size: 12, color: difficulty.color),
          const SizedBox(width: 5),
          Text(
            difficulty.label,
            style: TextStyle(
              color: difficulty.color,
              fontSize: 10,
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
