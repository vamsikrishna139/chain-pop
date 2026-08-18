import 'dart:math';

import '../level.dart';

/// A single committed placement in the retrograde sequence — a board cell
/// paired with the direction whose ray was clear at the moment of placement.
class RetrogradePlacement {
  /// `(x, y)` on the bounding grid.
  final Point<int> position;

  /// The direction the node will fire when extracted.
  final Direction direction;

  const RetrogradePlacement({
    required this.position,
    required this.direction,
  });

  @override
  String toString() => 'RetrogradePlacement($position, $direction)';
}
