import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../theme/world_theme.dart';
import '../levels/grid_cell_key.dart';

/// Restoration trail — board-local layer (priority -75, between the mask and
/// the nodes) that marks every cell a node has been extracted from.
///
/// Each restored cell is a faint accent-tinted glowing tile; 4-adjacent
/// restored cells are connected by a thin energized trace. As the player
/// clears the board it fills with a lit circuit instead of draining toward a
/// void, making "restore the network" literal and progress visible spatially.
///
/// Owned state lives in `ChainPopGame` (so it survives board relayout); this
/// component is reseeded via [seedAll] when the board rebuilds.
class RestoredNetworkComponent extends PositionComponent {
  final double cellSize;
  final WorldTheme theme;

  static const double _fadeInDuration = 0.35;

  final List<_RestoredCell> _cells = [];
  final Map<int, _RestoredCell> _byKey = {};
  double _clock = 0;

  final Paint _fillPaint = Paint();
  final Paint _tracePaint = Paint()..strokeCap = StrokeCap.round;
  final Paint _dotPaint = Paint();

  RestoredNetworkComponent({
    required this.cellSize,
    required this.theme,
    required int gridWidth,
    required int gridHeight,
  }) : super(size: Vector2(gridWidth * cellSize, gridHeight * cellSize));

  /// Adds a restored marker with a fade-in (a node was just extracted here).
  void addCell(int x, int y) => _add(x, y, mature: false);

  /// Reseeds existing markers after a board relayout — no fade-in replay.
  void seedAll(Iterable<(int, int)> cells) {
    _cells.clear();
    _byKey.clear();
    for (final (x, y) in cells) {
      _add(x, y, mature: true);
    }
  }

  void _add(int x, int y, {required bool mature}) {
    final key = gridCellKey(x, y);
    if (_byKey.containsKey(key)) return;
    final cell = _RestoredCell(x, y, age: mature ? _fadeInDuration : 0.0);
    _cells.add(cell);
    _byKey[key] = cell;
  }

  /// Removes the marker at ([x], [y]) — an undo put the node back.
  void removeCell(int x, int y) {
    final cell = _byKey.remove(gridCellKey(x, y));
    if (cell != null) _cells.remove(cell);
  }

  void clear() {
    _cells.clear();
    _byKey.clear();
  }

  @override
  void update(double dt) {
    _clock += dt;
    for (final c in _cells) {
      if (c.age < _fadeInDuration) c.age += dt;
    }
  }

  double _fadeOf(_RestoredCell c) =>
      (c.age / _fadeInDuration).clamp(0.0, 1.0);

  @override
  void render(Canvas canvas) {
    if (_cells.isEmpty) return;

    // Gentle global pulse so the circuit feels energized, never distracting.
    final pulse = 0.85 + 0.15 * math.sin(_clock * 1.6);

    // Traces first (under the tiles). Only right/down neighbors are checked so
    // each adjacent pair draws exactly one line.
    final traceAlpha = theme.restoredTrace.a * pulse;
    _tracePaint.strokeWidth = math.max(1.5, cellSize * 0.05);
    for (final c in _cells) {
      final from = Offset((c.x + 0.5) * cellSize, (c.y + 0.5) * cellSize);
      final right = _byKey[gridCellKey(c.x + 1, c.y)];
      final down = _byKey[gridCellKey(c.x, c.y + 1)];
      if (right != null) {
        _tracePaint.color = theme.restoredTrace.withValues(
          alpha: traceAlpha * math.min(_fadeOf(c), _fadeOf(right)),
        );
        canvas.drawLine(
          from,
          Offset((c.x + 1.5) * cellSize, (c.y + 0.5) * cellSize),
          _tracePaint,
        );
      }
      if (down != null) {
        _tracePaint.color = theme.restoredTrace.withValues(
          alpha: traceAlpha * math.min(_fadeOf(c), _fadeOf(down)),
        );
        canvas.drawLine(
          from,
          Offset((c.x + 0.5) * cellSize, (c.y + 1.5) * cellSize),
          _tracePaint,
        );
      }
    }

    final inset = cellSize * 0.20;
    final radius = Radius.circular(cellSize * 0.14);
    for (final c in _cells) {
      final fade = _fadeOf(c);
      _fillPaint.color = theme.restoredFill
          .withValues(alpha: theme.restoredFill.a * fade * pulse);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            c.x * cellSize + inset,
            c.y * cellSize + inset,
            cellSize - inset * 2,
            cellSize - inset * 2,
          ),
          radius,
        ),
        _fillPaint,
      );
      _dotPaint.color =
          theme.accent.withValues(alpha: 0.35 * fade * pulse);
      canvas.drawCircle(
        Offset((c.x + 0.5) * cellSize, (c.y + 0.5) * cellSize),
        math.max(1.5, cellSize * 0.045),
        _dotPaint,
      );
    }
  }

  @visibleForTesting
  int get cellCount => _cells.length;
}

class _RestoredCell {
  final int x;
  final int y;
  double age;

  _RestoredCell(this.x, this.y, {required this.age});
}
