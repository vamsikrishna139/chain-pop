import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_colors.dart';

class UndoRestartButton extends StatefulWidget {
  final Color accent;
  final bool canUndo;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  const UndoRestartButton({
    super.key,
    required this.accent,
    required this.canUndo,
    required this.onUndo,
    required this.onRestart,
  });

  @override
  State<UndoRestartButton> createState() => _UndoRestartButtonState();
}

class _UndoRestartButtonState extends State<UndoRestartButton> with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 700);

  late final AnimationController _holdCtrl;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _holding = false;
          _holdCtrl.reset();
          widget.onRestart();
        }
      });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!widget.canUndo) return;
    widget.onUndo();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _holding = true;
    _holdCtrl.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (_holding) {
      _holding = false;
      _holdCtrl.reverse();
    }
  }

  void _onLongPressCancel() {
    if (_holding) {
      _holding = false;
      _holdCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUndo = widget.canUndo;
    return GestureDetector(
      onTap: _onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: AnimatedBuilder(
        animation: _holdCtrl,
        builder: (context, _) {
          final v = _holdCtrl.value;
          return Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (v > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: v,
                        child: Container(color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (v > 0)
                      Transform.rotate(
                        angle: v * 2 * 3.14159265,
                        child: const Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 16),
                      )
                    else
                      Icon(Icons.undo_rounded, color: hasUndo ? Colors.white70 : Colors.white24, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      v > 0.2 ? 'HOLD TO RESTART' : 'UNDO',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: hasUndo ? Colors.white70 : Colors.white24,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
