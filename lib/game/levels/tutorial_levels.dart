import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'level.dart';

/// Compile-time mirror of [tutorialLevels.length] for const asserts
/// (e.g. [GameScreen]'s `tutorialIndex` range check).
const int tutorialStepCount = 10;

/// Ten hand-authored onboarding boards (fixed [LevelData], not procedural).
///
/// Progressive focus: single pop → ordered pair → parallel wave + column
/// follow-up → mixed 5×5 → larger 6×6 recap → cores (gold ring win
/// condition) → relay (row rotation) → locked node (padlock) → phase gate
/// (dimmed until the earlier phase clears) → graduation board carrying every
/// arrow type at once.
///
/// **Indices are load-bearing.** `_tutorialHintText` in `game_screen.dart`
/// switches on them, `computeTutorialCountdownSec` special-cases 4 and 9, the
/// Integrity HUD appears from index 5, and `GameTimerController` fast-tracks
/// the coach hint on 0–1. Append new steps at the end rather than renumbering.
final List<LevelData> tutorialLevels = [
  _tutorial0,
  _tutorial1,
  _tutorial2,
  _tutorial3,
  _tutorial4,
  _tutorial5,
  _tutorial6,
  _tutorial7,
  _tutorial8,
  _tutorial9,
];

Color _c(int slot) =>
    AppColors.nodePalette[slot % AppColors.nodePalette.length];

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

/// 6×6 recap with 8 arrows: layered row/column dependencies while remaining
/// approachable for a final tutorial board.
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
    NodeData(
      id: 6,
      x: 2,
      y: 5,
      dir: Direction.right,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 7,
      x: 5,
      y: 4,
      dir: Direction.up,
      color: _c(1),
      colorSlot: 1,
    ),
  ],
);

/// Cores: the three gold-ringed arrows are the win condition. The two normal
/// arrows face each other (permanently stuck) on purpose — the cascade finale
/// clears them once the last core pops.
final LevelData _tutorial5 = LevelData(
  levelId: 9005,
  gridWidth: 5,
  gridHeight: 5,
  nodes: [
    NodeData(
      id: 0,
      x: 1,
      y: 1,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
      isCore: true,
    ),
    NodeData(
      id: 1,
      x: 3,
      y: 1,
      dir: Direction.up,
      color: _c(1),
      colorSlot: 1,
      isCore: true,
    ),
    NodeData(
      id: 2,
      x: 2,
      y: 3,
      dir: Direction.down,
      color: _c(2),
      colorSlot: 2,
      isCore: true,
    ),
    NodeData(
      id: 3,
      x: 1,
      y: 2,
      dir: Direction.right,
      color: _c(3),
      colorSlot: 3,
    ),
    NodeData(
      id: 4,
      x: 3,
      y: 2,
      dir: Direction.left,
      color: _c(4),
      colorSlot: 4,
    ),
  ],
);

/// Relay: the two right-column arrows point at each other and can never exit
/// on their own. Popping the green-ringed relay rotates its row clockwise,
/// turning the lower arrow toward the open right edge.
final LevelData _tutorial6 = LevelData(
  levelId: 9006,
  gridWidth: 5,
  gridHeight: 5,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 2,
      dir: Direction.left,
      color: _c(0),
      colorSlot: 0,
      kind: NodeKind.relay,
    ),
    NodeData(
      id: 1,
      x: 3,
      y: 2,
      dir: Direction.up,
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
  ],
);

/// Locked node: the padlocked arrow refuses to move until both occupied
/// neighbor cells are cleared, then exits upward.
final LevelData _tutorial7 = LevelData(
  levelId: 9007,
  gridWidth: 4,
  gridHeight: 4,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 1,
      dir: Direction.left,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 1,
      y: 2,
      dir: Direction.down,
      color: _c(1),
      colorSlot: 1,
    ),
    NodeData(
      id: 2,
      x: 1,
      y: 1,
      dir: Direction.up,
      color: _c(2),
      colorSlot: 2,
      kind: NodeKind.locked,
    ),
  ],
);

/// Phase gate: the two dimmed arrows (`phaseGroup: 1`) both have a completely
/// clear ray, yet refuse to move while *any* `phaseGroup: 0` arrow is still on
/// the board — so the lesson is purely "wait for the phase", never "you were
/// blocked". Mirrors [LevelSolver] `_earlierPhaseRemains` and
/// `NodeComponent._checkPhaseBlocked`, which share the same predicate.
///
/// Opening wave is the two bright arrows; ID order 0→3 clears it.
final LevelData _tutorial8 = LevelData(
  levelId: 9008,
  gridWidth: 4,
  gridHeight: 4,
  nodes: [
    NodeData(
      id: 0,
      x: 0,
      y: 0,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 3,
      y: 3,
      dir: Direction.down,
      color: _c(1),
      colorSlot: 1,
    ),
    NodeData(
      id: 2,
      x: 1,
      y: 2,
      dir: Direction.left,
      color: _c(2),
      colorSlot: 2,
      phaseGroup: 1,
    ),
    NodeData(
      id: 3,
      x: 2,
      y: 1,
      dir: Direction.right,
      color: _c(3),
      colorSlot: 3,
      phaseGroup: 1,
    ),
  ],
);

/// Graduation board — every arrow type at once on a 5×5, in two acts.
///
/// **Act one** (`phaseGroup: 0`) forces each mechanic to be *used*, not merely
/// seen:
/// - `0` normal, free from the start, and the padlock's only live neighbour.
/// - `1` relay, free; popping it rotates row 2 clockwise.
/// - `2` normal, aimed up into core `6`. Because every core is `phaseGroup: 1`
///   and so cannot leave before act one ends, node `2` is provably reachable
///   *only* via the relay rotation (up → right, then a clear ray east).
/// - `3` locked, held by node `0` until it clears, then exits north.
///
/// **Act two** (`phaseGroup: 1`) unlocks once act one is empty: the dimmed
/// normal `4`, then the two gold cores `5`/`6` whose extraction wins the level.
/// Node `7` trails behind so the cascade finale still has something to sweep —
/// unlike [_tutorial5]'s stuck pair, `7` *is* removable in ID order, so this
/// board satisfies [LevelValidator] end to end.
///
/// No player ordering can soft-lock it: node `2`'s only unblocker is the relay,
/// the relay is free from turn one, and act two cannot open early.
final LevelData _tutorial9 = LevelData(
  levelId: 9009,
  gridWidth: 5,
  gridHeight: 5,
  nodes: [
    NodeData(
      id: 0,
      x: 3,
      y: 0,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
    ),
    NodeData(
      id: 1,
      x: 0,
      y: 2,
      dir: Direction.left,
      color: _c(1),
      colorSlot: 1,
      kind: NodeKind.relay,
    ),
    NodeData(
      id: 2,
      x: 2,
      y: 2,
      dir: Direction.up,
      color: _c(2),
      colorSlot: 2,
    ),
    NodeData(
      id: 3,
      x: 4,
      y: 0,
      dir: Direction.up,
      color: _c(3),
      colorSlot: 3,
      kind: NodeKind.locked,
    ),
    NodeData(
      id: 4,
      x: 0,
      y: 4,
      dir: Direction.left,
      color: _c(4),
      colorSlot: 4,
      phaseGroup: 1,
    ),
    NodeData(
      id: 5,
      x: 1,
      y: 1,
      dir: Direction.up,
      color: _c(5),
      colorSlot: 5,
      isCore: true,
      phaseGroup: 1,
    ),
    NodeData(
      id: 6,
      x: 2,
      y: 1,
      dir: Direction.up,
      color: _c(0),
      colorSlot: 0,
      isCore: true,
      phaseGroup: 1,
    ),
    NodeData(
      id: 7,
      x: 4,
      y: 4,
      dir: Direction.down,
      color: _c(1),
      colorSlot: 1,
      phaseGroup: 1,
    ),
  ],
);
