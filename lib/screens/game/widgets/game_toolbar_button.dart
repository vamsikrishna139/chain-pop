import 'package:flutter/material.dart';

/// Icon button used on the in-game bottom toolbar (hint, guides, zoom).
class GameToolbarButton extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  const GameToolbarButton({
    super.key,
    required this.icon,
    required this.accent,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withOpacity(0.18)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                color: selected ? accent : Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}
