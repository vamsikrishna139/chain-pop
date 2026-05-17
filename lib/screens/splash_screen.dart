import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Animated splash screen shown on app launch.
///
/// Shows the Chain Pop logo with a glowing chevron animation,
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
  late final AnimationController _glowController;
  late final AnimationController _textController;
  late final AnimationController _fadeOutController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _glowPulse;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _fadeOut;

  // Particle system for floating arrow shapes
  late final List<_FloatingParticle> _particles;
  late final AnimationController _particleController;

  @override
  void initState() {
    super.initState();

    // ── Logo entrance ──
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );
    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );

    // ── Glow pulse ──
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _glowPulse = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // ── Text slide in ──
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    // ── Fade out transition ──
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeInCubic),
    );

    // ── Floating particles ──
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    final rng = Random(42);
    _particles = List.generate(12, (_) => _FloatingParticle(rng));

    // ── Choreography ──
    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    _glowController.repeat(reverse: true);

    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    _fadeOutController.forward().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.nextScreen,
          transitionDuration: const Duration(milliseconds: 400),
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
    _glowController.dispose();
    _textController.dispose();
    _fadeOutController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeOut,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeOut.value,
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                // Floating particle background
                AnimatedBuilder(
                  animation: _particleController,
                  builder: (context, _) {
                    return CustomPaint(
                      size: MediaQuery.of(context).size,
                      painter: _ParticlePainter(
                        _particles,
                        _particleController.value,
                      ),
                    );
                  },
                ),

                // Radial glow behind logo
                Center(
                  child: AnimatedBuilder(
                    animation: _glowPulse,
                    builder: (context, _) {
                      return Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.accentEasy.withValues(
                                alpha: 0.12 * _glowPulse.value,
                              ),
                              AppColors.accentEasy.withValues(
                                alpha: 0.04 * _glowPulse.value,
                              ),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Logo + text
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Chevron icon
                      AnimatedBuilder(
                        animation: _logoController,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _logoOpacity.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: child,
                            ),
                          );
                        },
                        child: _buildChevronLogo(),
                      ),

                      const SizedBox(height: 32),

                      // Title text
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: Column(
                            children: [
                              Text(
                                'CHAIN POP',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: AppColors.accentEasy
                                          .withValues(alpha: 0.5),
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Clear the board. Chain the pops.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.5,
                                  color:
                                      Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildChevronLogo() {
    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(100, 100),
          painter: _ChevronPainter(glow: _glowPulse.value),
        );
      },
    );
  }
}

// ── Chevron painter ──────────────────────────────────────────────────────────

class _ChevronPainter extends CustomPainter {
  final double glow;

  _ChevronPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 100;

    final glowPaint = Paint()
      ..color = AppColors.accentEasy.withValues(alpha: 0.3 * glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * scale);

    final mainPaint = Paint()
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.accentEasy,
          AppColors.accentEasy.withValues(alpha: 0.7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // First chevron
    final path1 = Path()
      ..moveTo(cx - 22 * scale, cy - 24 * scale)
      ..lineTo(cx + 2 * scale, cy)
      ..lineTo(cx - 22 * scale, cy + 24 * scale);

    // Second chevron
    final path2 = Path()
      ..moveTo(cx, cy - 24 * scale)
      ..lineTo(cx + 24 * scale, cy)
      ..lineTo(cx, cy + 24 * scale);

    // Draw glow
    canvas.drawPath(path1, glowPaint);
    canvas.drawPath(path2, glowPaint);

    // Draw main
    canvas.drawPath(path1, mainPaint);
    canvas.drawPath(path2, mainPaint);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.glow != glow;
}

// ── Floating particles ───────────────────────────────────────────────────────

class _FloatingParticle {
  final double x;
  final double y;
  final double speed;
  final double size;
  final double opacity;
  final int colorIndex;

  _FloatingParticle(Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        speed = 0.2 + rng.nextDouble() * 0.6,
        size = 3 + rng.nextDouble() * 6,
        opacity = 0.06 + rng.nextDouble() * 0.12,
        colorIndex = rng.nextInt(AppColors.nodePalette.length);
}

class _ParticlePainter extends CustomPainter {
  final List<_FloatingParticle> particles;
  final double time;

  _ParticlePainter(this.particles, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final py = ((p.y + time * p.speed) % 1.2) * size.height - 0.1 * size.height;
      final px = p.x * size.width +
          sin((time + p.y) * pi * 2) * 20;

      final paint = Paint()
        ..color = AppColors.nodePalette[p.colorIndex]
            .withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(px, py), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
