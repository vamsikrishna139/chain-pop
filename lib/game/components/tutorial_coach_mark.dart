import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../chain_pop_game.dart';

/// Tutorial-only "do this next" pointer. Sits above the board and marks the
/// single tile the player should tap next — a pulsing ring on the tile plus a
/// bouncing arrow coming in from the lower-right (the classic finger gesture).
///
/// It draws nothing on its own schedule: the engine sets [showAt] with the
/// next valid move's board-space centre (from `LevelSolver.getHint`) after every
/// pop, so the pointer walks the player through the whole solution. Purely
/// cosmetic — it never intercepts taps (no [TapCallbacks]).
class TutorialCoachMark extends PositionComponent
    with HasGameReference<ChainPopGame> {
  TutorialCoachMark({required this.cellSize})
      : super(anchor: Anchor.center, priority: 80);

  final double cellSize;
  bool _visible = false;
  double _clock = 0;

  /// Point the marker at a board-space tile centre and show it.
  void showAt(Vector2 tileCentre) {
    position = tileCentre;
    _visible = true;
  }

  /// Hide the marker (no current target / level won).
  void hide() => _visible = false;

  @override
  void update(double dt) {
    _clock += dt;
  }

  @override
  void render(Canvas canvas) {
    if (!_visible || game.hasWon || game.isGameOver) return;
    final accent = game.theme.accent;

    // ── Pulsing ring on the tile ─────────────────────────────────────────────
    final t = (_clock % 1.3) / 1.3;
    final ringR = cellSize * 0.55 + t * cellSize * 0.35;
    final ringOpacity = (1.0 - t) * 0.7;
    if (ringOpacity > 0.01) {
      canvas.drawCircle(
        Offset.zero,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cellSize * 0.05 * (1.0 - t * 0.5)
          ..color = accent.withValues(alpha: ringOpacity),
      );
    }

    // ── Bouncing arrow from the lower-right, pointing up-left at the tile ─────
    final bounce = (math.sin(_clock * math.pi * 2) * 0.5 + 0.5) * cellSize * 0.12;
    final dir = const Offset(-1, -1) / math.sqrt2; // points up-left
    final perp = const Offset(-1, 1) / math.sqrt2;
    final tip = Offset(cellSize * 0.34, cellSize * 0.34) + dir * -bounce;
    final tail = Offset(cellSize * 0.95, cellSize * 0.95) + dir * -bounce;

    const headLen = 0.30;
    const headW = 0.18;
    final baseC = tip - dir * (cellSize * headLen);

    final shaftDark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cellSize * 0.16
      ..color = Colors.black.withValues(alpha: 0.35);
    final shaft = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = cellSize * 0.09
      ..color = accent;

    canvas.drawLine(tail, baseC, shaftDark);
    canvas.drawLine(tail, baseC, shaft);

    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((baseC + perp * (cellSize * headW)).dx,
          (baseC + perp * (cellSize * headW)).dy)
      ..lineTo((baseC - perp * (cellSize * headW)).dx,
          (baseC - perp * (cellSize * headW)).dy)
      ..close();
    canvas.drawPath(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.06
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawPath(head, Paint()..color = accent);
  }
}
