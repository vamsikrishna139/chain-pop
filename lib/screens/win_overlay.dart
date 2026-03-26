import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';

/// Animated star row + stats bottom sheet shown when the player wins a level.
///
/// Shows 1–3 animated stars, time taken, jams made, and navigation buttons.
class WinOverlay extends StatefulWidget {
  final int levelId;
  final DifficultyMode difficulty;
  final int stars;
  final int jamCount;
  final Duration timeTaken;
  final VoidCallback onMainMenu;
  final VoidCallback onRetry;
  final VoidCallback onNextLevel;

  const WinOverlay({
    super.key,
    required this.levelId,
    required this.difficulty,
    required this.stars,
    required this.jamCount,
    required this.timeTaken,
    required this.onMainMenu,
    required this.onRetry,
    required this.onNextLevel,
  });

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<WinOverlay> with TickerProviderStateMixin {
  late final List<AnimationController> _starControllers;
  late final List<Animation<double>> _starScales;

  @override
  void initState() {
    super.initState();

    // One controller per star, staggered 120ms apart.
    _starControllers = List.generate(3, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
      Future.delayed(Duration(milliseconds: 200 + i * 140), ctrl.forward);
      return ctrl;
    });

    _starScales = _starControllers.map((ctrl) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.elasticOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _starControllers) c.dispose();
    super.dispose();
  }

  String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.difficulty.color;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: accent.withOpacity(0.25), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),

          // Level label
          Text(
            'LEVEL ${widget.levelId} · ${widget.difficulty.label}',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Complete!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 28),

          // Stars row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final earned = i < widget.stars;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ScaleTransition(
                  scale: _starScales[i],
                  child: Icon(
                    earned ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 52,
                    color: earned ? const Color(0xFFFFC371) : Colors.white24,
                    shadows: earned
                        ? [Shadow(color: const Color(0xFFFFC371).withOpacity(0.6), blurRadius: 16)]
                        : [],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(label: 'TIME', value: _formatTime(widget.timeTaken)),
              const SizedBox(width: 20),
              _StatChip(label: 'JAMS', value: '${widget.jamCount}'),
            ],
          ),
          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: _OutlineButton(
                  label: 'MENU',
                  icon: Icons.home_rounded,
                  color: Colors.white38,
                  onPressed: widget.onMainMenu,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OutlineButton(
                  label: 'RETRY',
                  icon: Icons.refresh_rounded,
                  color: Colors.white38,
                  onPressed: widget.onRetry,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _FilledButton(
                  label: 'NEXT',
                  icon: Icons.arrow_forward_rounded,
                  color: accent,
                  onPressed: widget.onNextLevel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _OutlineButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.4)),
        ),
      ),
    );
  }
}

class _FilledButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _FilledButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 8,
        shadowColor: color.withOpacity(0.5),
      ),
    );
  }
}
