import 'package:flutter/material.dart';

/// Lightweight win feedback for fast clears: a pill that slides in, shows stars
/// + the level cleared + the running session streak, then the screen
/// auto-advances. Replaces the full [WinPanel] + confetti so flow state isn't
/// broken every level. Non-interactive (advance is timer-driven).
class QuickWinBanner extends StatefulWidget {
  final int stars;
  final String levelLabel;
  final String? directiveLabel;
  final int sessionWins;
  final Color accent;

  const QuickWinBanner({
    super.key,
    required this.stars,
    required this.levelLabel,
    this.directiveLabel,
    required this.sessionWins,
    required this.accent,
  });

  @override
  State<QuickWinBanner> createState() => _QuickWinBannerState();
}

class _QuickWinBannerState extends State<QuickWinBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  late final Animation<double> _in = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutBack,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.55),
        child: FadeTransition(
          opacity: _c,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.6),
              end: Offset.zero,
            ).animate(_in),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.28),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Icon(
                          i < widget.stars
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 22,
                          color:
                              i < widget.stars ? widget.accent : Colors.white24,
                        ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.levelLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (widget.directiveLabel != null)
                            Text(
                              widget.directiveLabel!,
                              style: TextStyle(
                                color: widget.accent.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          if (widget.sessionWins > 1)
                            Text(
                              '${widget.sessionWins} in a row',
                              style: TextStyle(
                                color: widget.accent.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
