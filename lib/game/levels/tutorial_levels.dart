import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'level.dart';

/// Five hand-authored onboarding boards (fixed [LevelData], not procedural).
///
/// Progressive focus: single pop → ordered pair → parallel wave + column
/// follow-up → mixed 5×5 → larger 6×6 recap.
final List<LevelData> tutorialLevels = [
  _tutorial0,
  _tutorial1,
  _tutorial2,
  _tutorial3,
  _tutorial4,
];

Color _c(int slot) => AppColors.nodePalette[slot % AppColors.nodePalette.length];

/// One node: tap to clear (ray exits upward).
final LevelData _tutorial0 = LevelData(
  levelId: 9000,
  gridWidth: 4,
  gridHeight: 4,
  nodes: [
    NodeData(
      id: 0,
      x: 2,
      y: 2,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
  ],
);

/// Two nodes: clear the one that exits upward first; then the left-facing
/// neighbor can slide off the board.
final LevelData _tutorial1 = LevelData(
  levelId: 9001,
  gridWidth: 4,
  gridHeight: 4,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 1,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 2,
      y: 1,
      dir: Direction.left,
      color: _c(1),
      colorSlot: 1,
    ),
  ],
);

/// Two opens in wave one; the third waits behind a same-column neighbor.
final LevelData _tutorial2 = LevelData(
  levelId: 9002,
  gridWidth: 4,
  gridHeight: 4,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 0,
      dir: Direction.right,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 3,
      y: 1,
      dir: Direction.up,
      color: _c(1),
      colorSlot: 1,
    ),
    NodeData(
      id: 2,
      x: 3,
      y: 3,
      dir: Direction.up,
      color: _c(2),
      colorSlot: 2,
    ),
  ],
);

/// 5×5: clear the vertical escape first so the left-facing piece on row 2 can
/// slide off; two other arrows are free in the opening wave.
final LevelData _tutorial3 = LevelData(
  levelId: 9003,
  gridWidth: 5,
  gridHeight: 5,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 2,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 3,
      y: 2,
      dir: Direction.left,
      color: _c(1),
      colorSlot: 1,
    ),
    NodeData(
      id: 2,
      x: 4,
      y: 0,
      dir: Direction.down,
      color: _c(2),
      colorSlot: 2,
    ),
    NodeData(
      id: 3,
      x: 2,
      y: 4,
      dir: Direction.up,
      color: _c(3),
      colorSlot: 3,
    ),
  ],
);

/// 6×6: two small column stories plus row-2 ordering at the top edge.
final LevelData _tutorial4 = LevelData(
  levelId: 9004,
  gridWidth: 6,
  gridHeight: 6,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 2,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 5,
      y: 2,
      dir: Direction.left,
      color: _c(1),
      colorSlot: 1,
    ),
    NodeData(
      id: 2,
      x: 3,
      y: 0,
      dir: Direction.down,
      color: _c(2),
      colorSlot: 2,
    ),
    NodeData(
      id: 3,
      x: 4,
      y: 5,
      dir: Direction.up,
      color: _c(3),
      colorSlot: 3,
    ),
    NodeData(
      id: 4,
      x: 1,
      y: 0,
      dir: Direction.right,
      color: _c(4),
      colorSlot: 4,
    ),
    NodeData(
      id: 5,
      x: 0,
      y: 5,
      dir: Direction.left,
      color: _c(5),
      colorSlot: 5,
    ),
  ],
);
