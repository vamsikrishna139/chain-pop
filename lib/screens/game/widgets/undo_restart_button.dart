import 'package:flutter/material.dart';

/// Dual-purpose control: **tap → undo**, **hold → restart**.
///
/// Hold uses a circular progress ring (no blocking dialog). Intended to be
/// easy to gate behind a rewarded ad later.
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

class _UndoRestartButtonState extends State<UndoRestartButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 700);

  late final AnimationController _holdCtrl;
  late final AnimationController _labelCtrl;
  bool _holding = false;
  String _labelText = '';

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(vsync: this, duration: _holdDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _holding = false;
          _holdCtrl.reset();
          _showLabel('RESTART');
          widget.onRestart();
        }
      });
    _labelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _showLabel(String text) {
    setState(() => _labelText = text);
    _labelCtrl.forward(from: 0);
  }

  void _onTap() {
    if (!widget.canUndo) return;
    _showLabel('UNDO');
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
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -22,
            child: AnimatedBuilder(
              animation: _labelCtrl,
              builder: (context, _) {
                final t = _labelCtrl.value;
                final opacity = t < 0.15
                    ? (t / 0.15)
                    : t > 0.7
                        ? ((1.0 - t) / 0.3).clamp(0.0, 1.0)
                        : 1.0;
                final slide = t < 0.15 ? (1.0 - t / 0.15) * 6 : 0.0;
                if (opacity <= 0) return const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(0, slide),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _labelText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          GestureDetector(
            onTap: _onTap,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onLongPressCancel: _onLongPressCancel,
            child: AnimatedBuilder(
              animation: _holdCtrl,
              builder: (context, _) {
                final v = _holdCtrl.value;
                return Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Colors.white.withValues(alpha: hasUndo ? 0.06 : 0.03),
                      widget.accent.withValues(alpha: 0.18),
                      v,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: v > 0
                        ? [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: v * 0.4),
                              blurRadius: 12 * v,
                              spreadRadius: 2 * v,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (v > 0)
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            value: v,
                            strokeWidth: 2.5,
                            color: widget.accent,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      Transform.rotate(
                        angle: v * 2 * 3.14159265,
                        child: Icon(
                          v > 0.1
                              ? Icons.refresh_rounded
                              : Icons.undo_rounded,
                          color: Color.lerp(
                            hasUndo ? Colors.white70 : Colors.white24,
                            widget.accent,
                            v,
                          ),
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
