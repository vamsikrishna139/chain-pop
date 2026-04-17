import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../game_screen_constants.dart';

/// Full-screen confetti burst + fall for level completion (casual puzzle
/// games often pair a short SFX with particles; this stays lightweight and
/// respects [IgnorePointer] so [WinPanel] stays interactive).
class WinCelebrationOverlay extends StatefulWidget {
  final Color accent;

  const WinCelebrationOverlay({super.key, required this.accent});

  @override
  State<WinCelebrationOverlay> createState() => _WinCelebrationOverlayState();
}

class _WinCelebrationOverlayState extends State<WinCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_Particle>? _particles;
  Size? _lastGenSize;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: GameScreenConstants.winConfettiDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Particle> _generate(Size size) {
    final r = math.Random(
      Object.hash(widget.accent.hashCode, size.width.round(), size.height.round()),
    );
    final w = size.width;
    final h = size.height;
    final m = w < h ? w : h;
    final colors = <Color>[
      widget.accent,
      AppColors.starGold,
      const Color(0xFF7CF8C2),
      const Color(0xFFFF7AB8),
      const Color(0xFFB8A4FF),
      Colors.white.withValues(alpha: 0.92),
    ];
    const n = GameScreenConstants.winConfettiParticleCount;
    final list = <_Particle>[];

    for (var i = 0; i < n; i++) {
      final c = colors[r.nextInt(colors.length)];
      final burst = r.nextDouble() < 0.42;
      final ax = burst ? (w * (0.38 + r.nextDouble() * 0.24)) : r.nextDouble() * w;
      final ay = burst ? (h * (0.12 + r.nextDouble() * 0.14)) : (-m * (0.04 + r.nextDouble() * 0.18));
      final angle = burst
          ? (math.pi * 0.55 + (r.nextDouble() - 0.5) * math.pi * 1.15)
          : (r.nextDouble() - 0.5) * 0.55;
      final sp = burst
          ? (m * (0.52 + r.nextDouble() * 0.85))
          : (m * (0.35 + r.nextDouble() * 0.55));
      final vx = burst ? (math.cos(angle) * sp) : (math.sin(angle) * m * 0.45);
      final vy = burst ? (math.sin(angle) * sp * 0.85 + m * 0.12) : (m * (0.42 + r.nextDouble() * 0.55));

      list.add(
        _Particle(
          x0: ax,
          y0: ay,
          vx: vx,
          vy: vy,
          gravity: GameScreenConstants.winConfettiGravity * m,
          rot0: r.nextDouble() * math.pi * 2,
          rotSpeed: (r.nextDouble() - 0.5) * 7.5,
          width: 5 + r.nextDouble() * 7,
          height: 4 + r.nextDouble() * 9,
          color: c,
          swayPhase: r.nextDouble() * math.pi * 2,
          swayAmp: m * (0.012 + r.nextDouble() * 0.028),
          depth: r.nextDouble(),
        ),
      );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) return const SizedBox.shrink();
        final resized = _lastGenSize != null &&
            (size.width - _lastGenSize!.width).abs() +
                    (size.height - _lastGenSize!.height).abs() >
                120;
        if (_particles == null || resized) {
          _particles = _generate(size);
          _lastGenSize = size;
        }
        final specs = _particles!;
        final tMax =
            GameScreenConstants.winConfettiDuration.inMilliseconds / 1000.0;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: size,
              painter: _ConfettiPainter(
                progress: _controller.value,
                particles: specs,
                durationSeconds: tMax,
              ),
            );
          },
        );
      },
    );
  }
}

class _Particle {
  final double x0;
  final double y0;
  final double vx;
  final double vy;
  final double gravity;
  final double rot0;
  final double rotSpeed;
  final double width;
  final double height;
  final Color color;
  final double swayPhase;
  final double swayAmp;
  /// 0 = back, 1 = front — affects opacity and size slightly.
  final double depth;

  const _Particle({
    required this.x0,
    required this.y0,
    required this.vx,
    required this.vy,
    required this.gravity,
    required this.rot0,
    required this.rotSpeed,
    required this.width,
    required this.height,
    required this.color,
    required this.swayPhase,
    required this.swayAmp,
    required this.depth,
  });
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.progress,
    required this.particles,
    required this.durationSeconds,
  });

  final double progress;
  final List<_Particle> particles;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * durationSeconds;
    for (final p in particles) {
      final sway = math.sin(p.swayPhase + t * 4.2) * p.swayAmp;
      final x = p.x0 + p.vx * t + sway;
      final y = p.y0 + p.vy * t + 0.5 * p.gravity * t * t;
      if (y < -40 || y > size.height + 60 || x < -40 || x > size.width + 40) {
        continue;
      }
      final rot = p.rot0 + p.rotSpeed * t;
      final fadeIn = Curves.easeOut.transform((progress * 1.4).clamp(0.0, 1.0));
      final fadeOut = progress < 0.82 ? 1.0 : (1.0 - Curves.easeIn.transform(((progress - 0.82) / 0.18).clamp(0.0, 1.0)));
      final a = (0.55 + p.depth * 0.45) * fadeIn * fadeOut;
      _drawPiece(canvas, Offset(x, y), rot, p.width, p.height, p.color.withValues(alpha: a));
    }
  }

  void _drawPiece(Canvas canvas, Offset c, double rot, double w, double h, Color color) {
    final paint = Paint()..color = color;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.durationSeconds != durationSeconds;
}
