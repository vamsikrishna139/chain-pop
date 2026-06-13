import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../theme/world_theme.dart';
import '../chain_pop_game.dart';

/// Screen-space ambient layer behind the board (priority -200).
///
/// Replaces the dead void with low-contrast life, without ever competing with
/// arrow legibility:
///  • static accent-tinted radial gradient + vignette (recorded once into a
///    [ui.Picture], rebuilt only on resize)
///  • a pool of slow-drifting motes in the world accent at 4–8% alpha
///  • a ripple pulse emitted from every extraction ([pulseAt])
///  • a faint screen-edge glow while the extraction streak is hot ([setStreak])
///  • low network-integrity atmosphere (scanline shimmer < 60, red breathing
///    vignette < 30) so jams have a visible cost beyond the HUD number
///
/// Mote drift freezes while the long-press ray preview is active so nothing
/// moves behind the player while they are aiming.
class AmbientBackgroundComponent extends PositionComponent
    with HasGameReference<ChainPopGame> {
  final WorldTheme theme;
  final math.Random _rng;

  AmbientBackgroundComponent({required this.theme, math.Random? random})
      : _rng = random ?? math.Random();

  static const int _moteCount = 24;
  static const int _pulsePoolSize = 8;
  static const double _pulseLife = 0.55;
  static const double _scanlineInterval = 4.0;
  static const double _scanlineLife = 0.10;

  final List<_Mote> _motes = [];
  final List<_Pulse> _pulses =
      List.generate(_pulsePoolSize, (_) => _Pulse(), growable: false);

  double _clock = 0;
  double _streakGlow = 0;
  int _streakLevel = 0;

  double _scanlineTimer = 0;
  double _scanlineAge = double.infinity;
  double _scanlineY = 0;

  ui.Picture? _base;
  final Vector2 _baseSize = Vector2.zero();

  final Paint _motePaint = Paint();
  final Paint _pulsePaint = Paint()..style = PaintingStyle.stroke;
  final Paint _scanlinePaint = Paint();
  late final Paint _edgeGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 18
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
  late final Paint _integrityGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 22
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

  @override
  Future<void> onLoad() async {
    _scatterMotes();
  }

  void _scatterMotes() {
    _motes.clear();
    final w = math.max(game.size.x, 1.0);
    final h = math.max(game.size.y, 1.0);
    for (var i = 0; i < _moteCount; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = 8.0 + _rng.nextDouble() * 7.0;
      _motes.add(
        _Mote(
          pos: Vector2(_rng.nextDouble() * w, _rng.nextDouble() * h),
          vel: Vector2(math.cos(angle), math.sin(angle))..scale(speed),
          radius: 1.0 + _rng.nextDouble() * 1.8,
          phase: _rng.nextDouble() * math.pi * 2,
        ),
      );
    }
  }

  /// Emits a ripple at [screenPos] (game/screen coordinates).
  void pulseAt(Vector2 screenPos, {double radius = 64}) {
    for (final p in _pulses) {
      if (p.age >= _pulseLife) {
        p.pos.setFrom(screenPos);
        p.age = 0;
        p.maxRadius = radius;
        return;
      }
    }
  }

  /// Mirrors the extraction streak so visuals can match the audio pitch ramp.
  void setStreak(int streak) => _streakLevel = streak;

  ui.Picture _buildBase(double w, double h) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h * 0.45),
          math.max(w, h) * 0.7,
          [
            theme.accent.withValues(alpha: 0.07),
            theme.accent.withValues(alpha: 0.0),
          ],
        ),
    );
    // Vignette: darken the corners so the playfield center reads as the stage.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w / 2, h / 2),
          math.max(w, h) * 0.75,
          [
            Colors.black.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.30),
          ],
          [0.62, 1.0],
        ),
    );
    return recorder.endRecording();
  }

  @override
  void update(double dt) {
    _clock += dt;

    if (_motes.isEmpty && game.size.x > 0 && game.size.y > 0) {
      _scatterMotes();
    }

    // Freeze drift while the player is aiming with the ray preview or if disabled by user settings.
    if (game.ambientMotion && !game.rayPreviewActive) {
      final w = game.size.x;
      final h = game.size.y;
      for (final m in _motes) {
        m.pos.addScaled(m.vel, dt);
        if (m.pos.x < -4) m.pos.x = w + 4;
        if (m.pos.x > w + 4) m.pos.x = -4;
        if (m.pos.y < -4) m.pos.y = h + 4;
        if (m.pos.y > h + 4) m.pos.y = -4;
      }
    }

    for (final p in _pulses) {
      if (p.age < _pulseLife) p.age += dt;
    }

    final glowTarget = _streakLevel >= 5 ? 1.0 : 0.0;
    final t = 1.0 - math.exp(-6.0 * dt);
    _streakGlow += (glowTarget - _streakGlow) * t;

    // Low-integrity scanline shimmer (occasional, one frame-burst at a time).
    if (game.networkIntegrity < 60) {
      _scanlineTimer += dt;
      _scanlineAge += dt;
      if (_scanlineTimer >= _scanlineInterval) {
        _scanlineTimer = 0;
        _scanlineAge = 0;
        _scanlineY = _rng.nextDouble() * math.max(game.size.y, 1.0);
      }
    } else {
      _scanlineAge = double.infinity;
    }
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    if (w <= 0 || h <= 0) return;

    if (_base == null || _baseSize.x != w || _baseSize.y != h) {
      _base = _buildBase(w, h);
      _baseSize.setValues(w, h);
    }
    canvas.drawPicture(_base!);

    for (final m in _motes) {
      final twinkle = 0.6 + 0.4 * math.sin(_clock * 0.8 + m.phase);
      _motePaint.color =
          theme.accent.withValues(alpha: 0.04 + 0.04 * twinkle);
      canvas.drawCircle(Offset(m.pos.x, m.pos.y), m.radius, _motePaint);
    }

    for (final p in _pulses) {
      if (p.age >= _pulseLife) continue;
      final progress = p.age / _pulseLife;
      _pulsePaint
        ..color = theme.accent.withValues(alpha: (1.0 - progress) * 0.16)
        ..strokeWidth = 2.0 * (1.0 - progress * 0.5);
      canvas.drawCircle(
        Offset(p.pos.x, p.pos.y),
        p.maxRadius * Curves.easeOut.transform(progress),
        _pulsePaint,
      );
    }

    if (_streakGlow > 0.02) {
      _edgeGlowPaint.color =
          theme.accent.withValues(alpha: 0.10 * _streakGlow);
      canvas.drawRect(Rect.fromLTWH(-6, -6, w + 12, h + 12), _edgeGlowPaint);
    }

    if (_scanlineAge < _scanlineLife) {
      final fade = 1.0 - _scanlineAge / _scanlineLife;
      _scanlinePaint.color = Colors.white.withValues(alpha: 0.05 * fade);
      canvas.drawRect(Rect.fromLTWH(0, _scanlineY, w, 2), _scanlinePaint);
    }

    if (game.networkIntegrity < 30) {
      // Slow red breathing at critically low integrity — atmosphere, not panic.
      final breath = 0.5 + 0.5 * math.sin(_clock * (math.pi * 2 / 4.0));
      _integrityGlowPaint.color = const Color(0xFFFF5F6D)
          .withValues(alpha: 0.05 * breath);
      canvas.drawRect(
        Rect.fromLTWH(-8, -8, w + 16, h + 16),
        _integrityGlowPaint,
      );
    }
  }
}

class _Mote {
  final Vector2 pos;
  final Vector2 vel;
  final double radius;
  final double phase;

  _Mote({
    required this.pos,
    required this.vel,
    required this.radius,
    required this.phase,
  });
}

class _Pulse {
  final Vector2 pos = Vector2.zero();
  double age = double.infinity;
  double maxRadius = 64;
}
