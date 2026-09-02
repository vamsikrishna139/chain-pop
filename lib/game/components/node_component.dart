import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'dart:math' as math;
import '../levels/level.dart';
import '../chain_pop_game.dart';
import '../../services/game_sfx.dart';

class NodeComponent extends PositionComponent
    with TapCallbacks, HasGameReference<ChainPopGame> {
  NodeData data;
  final double cellSize;

  bool isPopping = false;
  bool isJamming = false;
  bool isHighlighted = false;

  Vector2 _originalPos = Vector2.zero();
  double _shakeTimer = 0.0;
  double _highlightTimer = 0.0; // replaces Future.delayed — lifecycle-safe
  double _nudgeTimer = -1.0; // < 0 = idle
  double _freedTimer = -1.0; // < 0 = idle; one-shot "now freed" chain pulse
  double _blockerFlashTimer = -1.0; // < 0 = idle; "this is blocking you" flash
  double _arrowSpin = 0.0; // current arrow rotation offset (rad), eases to 0
  double _arrowSpinTimer = -1.0; // < 0 = idle; relay-rotation arrow animation
  bool _longPressActive = false;

  double _clock = 0.0;
  double _relayRotation = 0.0;
  bool _isLockActive = true;
  bool _lastLockActive = false;
  bool _isPhaseBlocked = false;
  bool _lastPhaseBlocked = false;

  late Rect _rect;
  late RRect _rrect;
  late Path _shadowPath;
  late Path _arrowPath;
  late Paint _fillPaint;
  late Paint _gradientPaint;
  late Paint _arrowPaintNormal;

  Color _shadowGlowColor = Colors.transparent;
  late double _shadowGlowRadius;

  static const double _shakeDuration = 0.3;
  static const double _highlightDuration = 2.0;
  static const double _highlightPulseCount = 3.0;
  static const double _nudgeDuration = 0.12;
  static const double _freedDuration = 0.5;
  static const double _blockerFlashDuration = 0.6;
  static const double _arrowSpinDuration = 0.18;
  static const double _speed = 1500.0;

  static final Vector2 _dirUp = Vector2(0, -1);
  static final Vector2 _dirDown = Vector2(0, 1);
  static final Vector2 _dirLeft = Vector2(-1, 0);
  static final Vector2 _dirRight = Vector2(1, 0);

  Color? _cachedEffectiveColor;

  final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  NodeComponent({required this.data, required this.cellSize})
      : super(
          size: Vector2.all(cellSize * 0.82),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    _updatePositionFromGrid();
    _buildRenderCaches();
    _isLockActive = data.kind == NodeKind.locked && _hasActiveNeighbors();
    _lastLockActive = _isLockActive;
    _isPhaseBlocked = _checkPhaseBlocked();
    _lastPhaseBlocked = _isPhaseBlocked;
  }

  bool _checkPhaseBlocked() {
    if (data.phaseGroup == 0) return false;
    for (final other in game.activeNodes) {
      if (other.phaseGroup < data.phaseGroup) return true;
    }
    return false;
  }

  bool _hasActiveNeighbors() {
    for (final other in game.activeNodes) {
      if (other.id == data.id) continue;
      final dx = (other.x - data.x).abs();
      final dy = (other.y - data.y).abs();
      if ((dx == 1 && dy == 0) || (dx == 0 && dy == 1)) {
        return true;
      }
    }
    return false;
  }

  void _buildRenderCaches() {
    _rect = size.toRect();
    _rrect = RRect.fromRectAndRadius(
      _rect,
      Radius.circular(cellSize * 0.18),
    );
    _shadowPath = Path()..addRRect(_rrect);

    _gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(_rect);

    _fillPaint = Paint()..color = data.color.withValues(alpha: 1.0);

    final strokeW = cellSize * 0.09;
    _arrowPaintNormal = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    _buildArrowPath();

    _shadowGlowColor = data.color.withValues(alpha: 0.55);
    _shadowGlowRadius = (cellSize * 0.38).clamp(4.0, 18.0);
  }

  void _buildArrowPath() {
    final arrow = Path();
    final center = _rect.center;
    final al = cellSize * 0.22;
    switch (data.dir) {
      case Direction.up:
        arrow
          ..moveTo(center.dx, center.dy + al)
          ..lineTo(center.dx, center.dy - al)
          ..moveTo(center.dx - al / 2, center.dy - al / 4)
          ..lineTo(center.dx, center.dy - al)
          ..lineTo(center.dx + al / 2, center.dy - al / 4);
      case Direction.down:
        arrow
          ..moveTo(center.dx, center.dy - al)
          ..lineTo(center.dx, center.dy + al)
          ..moveTo(center.dx - al / 2, center.dy + al / 4)
          ..lineTo(center.dx, center.dy + al)
          ..lineTo(center.dx + al / 2, center.dy + al / 4);
      case Direction.left:
        arrow
          ..moveTo(center.dx + al, center.dy)
          ..lineTo(center.dx - al, center.dy)
          ..moveTo(center.dx - al / 4, center.dy - al / 2)
          ..lineTo(center.dx - al, center.dy)
          ..lineTo(center.dx - al / 4, center.dy + al / 2);
      case Direction.right:
        arrow
          ..moveTo(center.dx - al, center.dy)
          ..lineTo(center.dx + al, center.dy)
          ..moveTo(center.dx + al / 4, center.dy - al / 2)
          ..lineTo(center.dx + al, center.dy)
          ..lineTo(center.dx + al / 4, center.dy + al / 2);
    }
    _arrowPath = arrow;
  }

  void _updatePositionFromGrid() {
    position = Vector2((data.x + 0.5) * cellSize, (data.y + 0.5) * cellSize);
    _originalPos = position.clone();
  }

  /// After a board relayout (e.g. resize), sync the jam "home" position to the
  /// new grid cell center while the node may still be mid-shake.
  void resyncJamRestPositionForCellSize(double newCellSize) {
    _originalPos.setValues(
      (data.x + 0.5) * newCellSize,
      (data.y + 0.5) * newCellSize,
    );
  }

  void updateData(NodeData next) {
    data = next;
    _buildRenderCaches();
  }

  /// Updates to [next] (the post-rotation direction) and animates the arrow
  /// spinning into place over [_arrowSpinDuration], rather than snapping. Used
  /// when a relay rotates its row so the change reads as motion.
  void animateRotationTo(NodeData next, {required bool clockwise}) {
    updateData(next);
    // Start the rendered arrow a quarter-turn back from the new direction and
    // ease to 0, so it visually rotates the way the row turned.
    _arrowSpin = clockwise ? -math.pi / 2 : math.pi / 2;
    _arrowSpinTimer = 0.0;
  }

  /// Brief warning ring — flags this node as the blocker stopping a repeatedly
  /// jammed node, turning a frustrating dead-end into a readable hint.
  void flashAsBlocker() {
    if (isPopping) return;
    _blockerFlashTimer = 0.0;
  }

  @visibleForTesting
  bool get isFlashingBlocker => _blockerFlashTimer >= 0;

  @visibleForTesting
  double get arrowSpin => _arrowSpin;

  void highlight() {
    isHighlighted = true;
    _highlightTimer = 0.0;
  }

  /// Brief scale dip when a 4-adjacent neighbor is extracted — makes chains
  /// feel physically connected.
  void nudge() {
    if (isPopping || isJamming) return;
    _nudgeTimer = 0.0;
  }

  /// One-shot accent ring pulse when this node becomes extractable because a
  /// neighbor was just removed — telegraphs the chain so cause→effect reads.
  void telegraphFreed() {
    if (isPopping || isJamming) return;
    _freedTimer = 0.0;
  }

  @visibleForTesting
  bool get isTelegraphingFreed => _freedTimer >= 0;

  /// Pops this node as part of the core-win cascade finale (no extraction
  /// bookkeeping — the game has already won and drives the sequence).
  void triggerCascadePop() {
    if (isPopping) return;
    isPopping = true;
    isJamming = false;
  }

  void _syncColorsFromSettings() {
    var effective = game.effectiveNodeColor(data);
    final activeLock = data.kind == NodeKind.locked && _isLockActive;
    if (activeLock) {
      final hsl = HSLColor.fromColor(effective);
      effective = hsl
          .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.60).clamp(0.0, 1.0))
          .toColor();
    } else if (_isPhaseBlocked) {
      final hsl = HSLColor.fromColor(effective);
      effective = hsl
          .withSaturation((hsl.saturation * 0.30).clamp(0.0, 1.0))
          .withLightness((hsl.lightness * 0.20).clamp(0.0, 1.0))
          .toColor();
    }
    if (_cachedEffectiveColor == effective &&
        _lastLockActive == activeLock &&
        _lastPhaseBlocked == _isPhaseBlocked) {
      return;
    }
    _cachedEffectiveColor = effective;
    _lastLockActive = activeLock;
    _lastPhaseBlocked = _isPhaseBlocked;
    _fillPaint.color = effective.withValues(alpha: 1.0);
    _shadowGlowColor = effective.withValues(alpha: 0.55);
  }

  @override
  void render(Canvas canvas) {
    _syncColorsFromSettings();
    if (isHighlighted) {
      _renderHighlighted(canvas);
    } else {
      if (isPopping) {
        _renderGhostTrails(canvas);
      }
      // Uniform brightness — legal moves are not telegraphed; wrong taps jam.
      canvas.drawShadow(
        _shadowPath,
        _shadowGlowColor,
        _shadowGlowRadius,
        true,
      );
      canvas.drawRRect(_rrect, _fillPaint);
      canvas.drawRRect(_rrect, _gradientPaint);
      _drawArrow(canvas);
      _renderKindBadges(canvas);
      if (_freedTimer >= 0) _renderFreedPulse(canvas);
      if (_blockerFlashTimer >= 0) _renderBlockerFlash(canvas);
    }
  }

  /// Draws fading, scaling ghost nodes behind the current popping node position.
  void _renderGhostTrails(Canvas canvas) {
    final dir = _directionVector();
    final ghostPaint = Paint()..style = PaintingStyle.fill;
    final baseColor = _fillPaint.color;
    final center = _rect.center;
    for (var i = 1; i <= 3; i++) {
      final distance = cellSize * 0.24 * i;
      final offset = Offset(-dir.x * distance, -dir.y * distance);
      final alpha = (0.55 - i * 0.15).clamp(0.0, 1.0);
      final scaleAmt = 1.0 - i * 0.12;
      ghostPaint.color = baseColor.withValues(alpha: alpha);

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.translate(center.dx, center.dy);
      canvas.scale(scaleAmt, scaleAmt);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawRRect(_rrect, ghostPaint);
      canvas.restore();
    }
  }

  /// Draws the direction arrow, applying the relay-rotation spin offset when
  /// one is active so the arrow appears to rotate into place.
  void _drawArrow(Canvas canvas) {
    if (_arrowSpin == 0.0) {
      canvas.drawPath(_arrowPath, _arrowPaintNormal);
      return;
    }
    final c = _rect.center;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_arrowSpin);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawPath(_arrowPath, _arrowPaintNormal);
    canvas.restore();
  }

  /// Pulsing red ring — "this node is what's blocking you."
  void _renderBlockerFlash(Canvas canvas) {
    final t = (_blockerFlashTimer / _blockerFlashDuration).clamp(0.0, 1.0);
    // Two quick pulses over the lifetime.
    final pulse = (math.sin(t * math.pi * 2) * 0.5 + 0.5);
    final opacity = (1.0 - t) * (0.5 + 0.4 * pulse);
    if (opacity <= 0.005) return;
    _ringPaint
      ..color = const Color(0xFFFF5252).withValues(alpha: opacity)
      ..strokeWidth = cellSize * 0.08;
    canvas.drawRRect(_rrect, _ringPaint);
  }

  /// Expanding accent ring radiating once from the node when it becomes
  /// extractable via a chain. Fades over [_freedDuration]; no scale (distinct
  /// from the hint highlight).
  void _renderFreedPulse(Canvas canvas) {
    final t = (_freedTimer / _freedDuration).clamp(0.0, 1.0);
    final base = _rect.width * 0.5;
    final radius = base + t * base * 0.7;
    final opacity = (1.0 - t) * 0.6;
    if (opacity <= 0.005) return;
    _ringPaint
      ..color = game.theme.accent.withValues(alpha: opacity)
      ..strokeWidth = (cellSize * 0.06) * (1.0 - t * 0.5);
    canvas.drawCircle(_rect.center, radius, _ringPaint);
  }

  void _renderKindBadges(Canvas canvas) {
    if (data.isCore) {
      final pulse = 0.55 + 0.4 * math.sin(_clock * math.pi);
      _ringPaint
        ..color = Colors.black.withValues(alpha: 0.45 * pulse)
        ..strokeWidth = cellSize * 0.12;
      canvas.drawRRect(_rrect, _ringPaint);
      _ringPaint
        ..color = const Color(0xFFFFD54F).withValues(alpha: 0.55 + 0.4 * pulse)
        ..strokeWidth = cellSize * 0.07;
      canvas.drawRRect(_rrect, _ringPaint);
    }
    if (data.kind == NodeKind.locked) {
      final bracketPaint = Paint()
        ..color = Colors.white.withValues(alpha: _isLockActive ? 0.85 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.06
        ..strokeCap = StrokeCap.round;

      final padding = cellSize * 0.08;
      final l = _rect.left + padding;
      final r = _rect.right - padding;
      final t = _rect.top + padding;
      final b = _rect.bottom - padding;
      final len = cellSize * 0.16;

      // Top-Left corner
      canvas.drawPath(
        Path()
          ..moveTo(l + len, t)
          ..lineTo(l, t)
          ..lineTo(l, t + len),
        bracketPaint,
      );
      // Top-Right corner
      canvas.drawPath(
        Path()
          ..moveTo(r - len, t)
          ..lineTo(r, t)
          ..lineTo(r, t + len),
        bracketPaint,
      );
      // Bottom-Left corner
      canvas.drawPath(
        Path()
          ..moveTo(l + len, b)
          ..lineTo(l, b)
          ..lineTo(l, b - len),
        bracketPaint,
      );
      // Bottom-Right corner
      canvas.drawPath(
        Path()
          ..moveTo(r - len, b)
          ..lineTo(r, b)
          ..lineTo(r, b - len),
        bracketPaint,
      );
    }
    if (data.kind == NodeKind.relay) {
      final c = _rect.center;
      final r = cellSize * 0.12;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(_relayRotation);

      final bgPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.08;
      canvas.drawCircle(Offset.zero, r, bgPaint);

      final strokePaint = Paint()
        ..color = const Color(0xFF00FF87).withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.04
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r),
        0.1,
        math.pi - 0.2,
        false,
        strokePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r),
        math.pi + 0.1,
        math.pi - 0.2,
        false,
        strokePaint,
      );

      canvas.restore();
    }
  }

  /// Pulsing scale + expanding ring ripple — much more noticeable than a
  /// static color swap and universally reads as "tap me."
  void _renderHighlighted(Canvas canvas) {
    final progress = _highlightTimer / _highlightDuration;
    final fadeOut =
        progress < 0.7 ? 1.0 : ((1.0 - progress) / 0.3).clamp(0.0, 1.0);

    final phase =
        _highlightTimer * math.pi * _highlightPulseCount / _highlightDuration;
    final pulseVal = math.sin(phase).abs();
    final center = _rect.center;

    // ── Expanding ring ripple (one ring per pulse cycle) ──
    const ringPeriod = _highlightDuration / _highlightPulseCount;
    final ringT = (_highlightTimer % ringPeriod) / ringPeriod;
    final baseRadius = _rect.width * 0.5;
    final ringRadius = baseRadius + ringT * baseRadius * 0.6;
    final ringOpacity = (1.0 - ringT) * 0.45 * fadeOut;
    if (ringOpacity > 0.005) {
      _ringPaint
        ..color = game.effectiveNodeColor(data).withValues(alpha: ringOpacity)
        ..strokeWidth = 2.5 * (1.0 - ringT * 0.6);
      canvas.drawCircle(center, ringRadius, _ringPaint);
    }

    // ── Pulsing scale + intensified glow ──
    final scaleAmt = 1.0 + 0.09 * pulseVal * fadeOut;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scaleAmt, scaleAmt);
    canvas.translate(-center.dx, -center.dy);

    final glowStrength =
        _shadowGlowRadius + _shadowGlowRadius * 0.85 * pulseVal * fadeOut;
    final glowOpacity = (0.55 + 0.3 * pulseVal * fadeOut).clamp(0.0, 1.0);
    canvas.drawShadow(
      _shadowPath,
      game.effectiveNodeColor(data).withValues(alpha: glowOpacity),
      glowStrength,
      true,
    );
    canvas.drawRRect(_rrect, _fillPaint);
    canvas.drawRRect(_rrect, _gradientPaint);
    _drawArrow(canvas);

    canvas.restore();
  }

  @override
  void update(double dt) {
    _clock += dt;

    if (data.kind == NodeKind.relay) {
      _relayRotation += dt * 1.5;
    }

    _blockerFlashTimer -= dt;
    _arrowSpinTimer -= dt;

    if (!isPopping && !isJamming) {
      final activeLock = data.kind == NodeKind.locked && _hasActiveNeighbors();
      if (_isLockActive && !activeLock) {
        telegraphFreed();
      }
      _isLockActive = activeLock;

      final phaseBlocked = _checkPhaseBlocked();
      if (_isPhaseBlocked && !phaseBlocked) {
        telegraphFreed();
      }
      _isPhaseBlocked = phaseBlocked;
    }

    // ── Highlight timeout (replaces Future.delayed — no memory leak) ─────────
    if (isHighlighted) {
      _highlightTimer += dt;
      if (_highlightTimer >= _highlightDuration) {
        isHighlighted = false;
        _highlightTimer = 0.0;
      }
    }

    // ── Neighbor-extraction nudge (60–120ms scale dip) ──────────────────────
    if (_nudgeTimer >= 0) {
      _nudgeTimer += dt;
      if (_nudgeTimer >= _nudgeDuration) {
        _nudgeTimer = -1.0;
        scale.setAll(1.0);
      } else {
        final t = _nudgeTimer / _nudgeDuration;
        scale.setAll(1.0 - 0.05 * math.sin(math.pi * t));
      }
    }

    // ── "Now freed" chain telegraph (one-shot accent ring) ──────────────────
    if (_freedTimer >= 0) {
      _freedTimer += dt;
      if (_freedTimer >= _freedDuration) _freedTimer = -1.0;
    }

    // ── Blocker flash (one-shot warning ring) ───────────────────────────────
    if (_blockerFlashTimer >= 0) {
      _blockerFlashTimer += dt;
      if (_blockerFlashTimer >= _blockerFlashDuration)
        _blockerFlashTimer = -1.0;
    }

    // ── Relay arrow rotation (ease the spin offset back to 0) ────────────────
    if (_arrowSpinTimer >= 0) {
      _arrowSpinTimer += dt;
      if (_arrowSpinTimer >= _arrowSpinDuration) {
        _arrowSpinTimer = -1.0;
        _arrowSpin = 0.0;
      } else {
        final t = _arrowSpinTimer / _arrowSpinDuration;
        // Ease-out: fraction of the original offset still remaining.
        final remaining = (1.0 - t) * (1.0 - t);
        final sign = _arrowSpin >= 0 ? 1.0 : -1.0;
        _arrowSpin = sign * (math.pi / 2) * remaining;
      }
    }

    // ── Pop (fly off in arrow direction) ────────────────────────────────────
    if (isPopping) {
      position += _directionVector() * _speed * dt;
      // [position] is board-local; compare in game/world space so we actually
      // reach the viewport edge before removing.
      final world = absoluteCenter;
      final gs = game.size;
      final pad = math.max(size.x, size.y) * 0.55 + 48;
      if (world.x < -pad ||
          world.x > gs.x + pad ||
          world.y < -pad ||
          world.y > gs.y + pad) {
        removeFromParent();
        game.checkWinCondition();
      }
      return;
    }

    // ── Jam shake ────────────────────────────────────────────────────────────
    if (isJamming) {
      _shakeTimer += dt;
      if (_shakeTimer >= _shakeDuration) {
        isJamming = false;
        position.setFrom(_originalPos);
        _shakeTimer = 0.0;
      } else {
        final shakeAmount = (1.0 - (_shakeTimer / _shakeDuration)) * 10.0;
        final offset = math.sin(_shakeTimer * 60) * shakeAmount;
        position = _originalPos + _directionVector() * offset;
      }
    }
  }

  /// Dev autoplay only: extract this node as if validly tapped (no haptics).
  void debugAutoExtract() {
    if (isPopping || isJamming || game.hasWon || game.isGameOver) return;
    isPopping = true;
    game.registerExtraction(data);
    game.playSfx(GameSfx.pop, playbackRate: game.popPlaybackRate);
  }

  void _performTapAction() {
    if (isPopping || isJamming || game.hasWon || game.isGameOver) return;

    if (game.canExtract(data)) {
      isPopping = true;
      game.registerExtraction(data);
      if (game.hapticsEnabled) {
        Haptics.vibrate(HapticsType.medium);
      }
      game.playSfx(
        GameSfx.pop,
        playbackRate: game.popPlaybackRate,
      );
    } else {
      isJamming = true;
      _shakeTimer = 0.0;
      if (game.hapticsEnabled) {
        Haptics.vibrate(HapticsType.heavy);
      }
      game.playSfx(GameSfx.jam);
      game.reportJam(data);
    }
  }

  /// The painted tile is `cellSize × 0.82`, which at a shipped 40 px cell is a
  /// 33 px interaction target — under both the 44 pt iOS and 48 dp Android
  /// minimums. The *hit* region is decoupled from the art and expanded to the
  /// whole cell, which is the largest region that cannot steal a tap from a
  /// neighbour: nodes sit at cell centres, so full-cell regions tile the board
  /// exactly. Intervals are half-open on the far edge so a tap landing exactly
  /// on a shared boundary resolves to precisely one node instead of two or four.
  ///
  /// The whole tiling is nudged by [_hitBoundaryEpsilon] so that a point at an
  /// exact multiple of the cell size falls strictly *inside* one interval
  /// rather than on its edge. Without it, cell centres and grid lines computed
  /// by different float paths (`(x + 0.5) * cell` vs `x * cell`) can disagree
  /// in the last bit and drop the tap entirely.
  ///
  /// **Rollback:** delete this override — the default `PositionComponent` rect
  /// over [size] is the previous behaviour.
  @override
  bool containsLocalPoint(Vector2 point) {
    if (cellSize <= 0) return super.containsLocalPoint(point);
    // Local space runs 0..size with the anchor centred, so the surrounding cell
    // extends by half the difference on each side.
    final padX = (cellSize - size.x) / 2;
    final padY = (cellSize - size.y) / 2;
    // The interval is [-pad, size + pad) shifted down by epsilon, so grid lines
    // land strictly inside the higher-indexed cell rather than on a seam.
    const e = _hitBoundaryEpsilon;
    return point.x >= -padX - e &&
        point.x < size.x + padX - e &&
        point.y >= -padY - e &&
        point.y < size.y + padY - e;
  }

  /// Sub-pixel nudge that keeps the full-cell hit tiling gap-free and
  /// overlap-free at exact grid lines. Far below one logical pixel, so it has
  /// no perceptible effect on where a tap lands.
  static const double _hitBoundaryEpsilon = 0.01;

  @override
  void onTapDown(TapDownEvent event) {
    if (isPopping || isJamming || game.hasWon || game.isGameOver) return;
    // Faint aim guide on press (before release): shows this node's exit path /
    // first blocker so a jam is a choice, not a surprise. A long press below
    // upgrades it to the full-intensity ray.
    if (game.showAimRay) {
      game.showRayPreview(data, intensity: 0.42);
    }
  }

  @override
  void onLongTapDown(TapDownEvent event) {
    if (isPopping || isJamming || game.hasWon || game.isGameOver) return;
    _longPressActive = true;
    game.showRayPreview(data);
  }

  @override
  void onTapUp(TapUpEvent event) {
    game.hideRayPreview();
    if (_longPressActive) {
      _longPressActive = false;
      return;
    }
    _performTapAction();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _longPressActive = false;
    game.hideRayPreview();
  }

  Vector2 _directionVector() {
    switch (data.dir) {
      case Direction.up:
        return _dirUp;
      case Direction.down:
        return _dirDown;
      case Direction.left:
        return _dirLeft;
      case Direction.right:
        return _dirRight;
    }
  }
}
