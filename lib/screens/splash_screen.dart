import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated splash screen shown on app launch.
///
/// Shows the "Escaping Arrow" Unbound logo,
/// then smoothly transitions to [nextScreen] after a short delay.
class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _breathController;
  late final AnimationController _fadeOutController;

  late final Animation<double> _sparkOpacity;
  late final Animation<double> _boxDraw;
  late final Animation<double> _arrowDraw;

  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleSpacing;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _sloganOpacity;
  late final Animation<double> _breathSpacing;
  late final Animation<double> _fadeOut;

  late final List<_FloatingDust> _particles;
  late final AnimationController _particleController;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _sparkOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
      ),
    );

    _boxDraw = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.12, 0.55, curve: Curves.easeInOutCubic),
      ),
    );

    _arrowDraw = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.48, 0.92, curve: Curves.easeOutCubic),
      ),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      ),
    );
    _titleSpacing = Tween<double>(begin: 1.0, end: 6.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _sloganOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _breathSpacing = Tween<double>(begin: 5.5, end: 7.5).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeInCubic),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    final rng = Random(42);
    _particles = List.generate(18, (_) => _FloatingDust(rng));

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;
    _textController.forward();
    _breathController.repeat(reverse: true);

    await Future.delayed(const Duration(milliseconds: 2300));
    if (!mounted) return;

    _fadeOutController.forward().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.nextScreen,
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _breathController.dispose();
    _fadeOutController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_fadeOut, _breathController]),
      builder: (context, child) {
        final letterSpacing = _textController.isCompleted
            ? _breathSpacing.value
            : _titleSpacing.value;

        return Opacity(
          opacity: _fadeOut.value,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: MediaQuery.of(context).size,
                      painter: _DustPainter(
                        _particles,
                        _particleController.value,
                      ),
                    );
                  },
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _logoController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(128, 128),
                            painter: _EscapingArrowPainter(
                              sparkOpacity: _sparkOpacity.value,
                              boxDraw: _boxDraw.value,
                              arrowDraw: _arrowDraw.value,
                              accentColor: AppColors.accentEasy,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 44),
                      AnimatedBuilder(
                        animation: _textController,
                        builder: (context, child) {
                          return SlideTransition(
                            position: _titleSlide,
                            child: Column(
                              children: [
                                Opacity(
                                  opacity: _titleOpacity.value,
                                  child: Text(
                                    'UNBOUND',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: letterSpacing,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: AppColors.accentEasy
                                              .withValues(alpha: 0.35),
                                          blurRadius: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Opacity(
                                  opacity: _sloganOpacity.value,
                                  child: Text(
                                    'Find the path. Free the board.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.8,
                                      color:
                                          Colors.white.withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Escaping Arrow Painter ───────────────────────────────────────────────────

class _EscapingArrowPainter extends CustomPainter {
  final double sparkOpacity;
  final double boxDraw;
  final double arrowDraw;
  final Color accentColor;

  _EscapingArrowPainter({
    required this.sparkOpacity,
    required this.boxDraw,
    required this.arrowDraw,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const maxHalf = 36.0;
    const strokeWidth = 3.5;
    const cornerGap = 14.0;

    // 1. Spark — fades as the boundary begins to form
    if (sparkOpacity > 0) {
      final sparkAlpha = sparkOpacity * (1.0 - boxDraw * 0.85);
      if (sparkAlpha > 0.01) {
        final sparkGlow = Paint()
          ..color = accentColor.withValues(alpha: sparkAlpha * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        final sparkCore = Paint()
          ..color = accentColor.withValues(alpha: sparkAlpha);
        canvas.drawCircle(Offset(cx, cy), 5, sparkGlow);
        canvas.drawCircle(Offset(cx, cy), 2.5, sparkCore);
      }
    }

    final half = maxHalf * boxDraw;
    if (half < 0.5) return;

    final bl = Offset(cx - half, cy + half);
    final tl = Offset(cx - half, cy - half);
    final tr = Offset(cx + half, cy - half);
    final br = Offset(cx + half, cy + half);
    final topEnd = Offset(tr.dx - cornerGap, tr.dy);
    final rightStart = Offset(tr.dx, tr.dy + cornerGap);

    // 2. Square boundary — thin, muted, with a gap at the top-right corner
    final boxPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28 * boxDraw)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final boundary = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(tl.dx, tl.dy)
      ..lineTo(topEnd.dx, topEnd.dy)
      ..moveTo(rightStart.dx, rightStart.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(bl.dx, bl.dy);

    canvas.drawPath(boundary, boxPaint);

    // 3. Arrow breaking out through the top-right gap
    if (arrowDraw <= 0) return;

    final arrowStart = Offset(cx - half * 0.15, cy + half * 0.15);
    final arrowEnd = Offset(
      cx + half + cornerGap * 0.6,
      cy - half - cornerGap * 0.6,
    );

    final arrowBody = Path()
      ..moveTo(arrowStart.dx, arrowStart.dy)
      ..lineTo(arrowEnd.dx, arrowEnd.dy);

    final metrics = arrowBody.computeMetrics().first;
    final drawnArrow = metrics.extractPath(0, metrics.length * arrowDraw);

    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.45 * arrowDraw)
      ..strokeWidth = strokeWidth + 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final arrowPaint = Paint()
      ..color = accentColor
      ..strokeWidth = strokeWidth + 0.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(drawnArrow, glowPaint);
    canvas.drawPath(drawnArrow, arrowPaint);

    if (arrowDraw > 0.72) {
      final headT = ((arrowDraw - 0.72) / 0.28).clamp(0.0, 1.0);
      const headLen = 11.0;
      const dir = Offset(1, -1);
      final mag = dir.distance;
      final unit = Offset(dir.dx / mag, dir.dy / mag);
      final tip = arrowEnd;
      final wingA = tip - unit * headLen + Offset(-unit.dy, unit.dx) * headLen * 0.55;
      final wingB = tip - unit * headLen - Offset(-unit.dy, unit.dx) * headLen * 0.55;

      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(lerpDouble(wingA.dx, tip.dx, headT)!, lerpDouble(wingA.dy, tip.dy, headT)!)
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(lerpDouble(wingB.dx, tip.dx, headT)!, lerpDouble(wingB.dy, tip.dy, headT)!);

      canvas.drawPath(head, glowPaint);
      canvas.drawPath(head, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(_EscapingArrowPainter old) =>
      old.sparkOpacity != sparkOpacity ||
      old.boxDraw != boxDraw ||
      old.arrowDraw != arrowDraw ||
      old.accentColor != accentColor;
}

// ── Subtle floating dust ─────────────────────────────────────────────────────

class _FloatingDust {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double opacity;
  final double swayOffset;

  _FloatingDust(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.08 + rng.nextDouble() * 0.14,
        size = 1 + rng.nextDouble() * 2,
        opacity = 0.04 + rng.nextDouble() * 0.1,
        swayOffset = rng.nextDouble() * pi * 2;
}

class _DustPainter extends CustomPainter {
  final List<_FloatingDust> particles;
  final double time;

  _DustPainter(this.particles, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final py = size.height -
          ((p.y * size.height + time * size.height * p.speed) % size.height);
      final px = p.x * size.width + sin(time * pi * 2 + p.swayOffset) * 12;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_DustPainter old) => old.time != time;
}
