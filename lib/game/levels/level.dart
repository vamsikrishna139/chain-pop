import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'generation/silhouettes.dart';

enum Direction { up, down, left, right }

/// 90° rotations, shared by relay gameplay ([NodeKind.relay] pops rotate the
/// row clockwise; undo rotates it back) and by solver/validator simulation.
extension DirectionRotation on Direction {
  Direction get rotatedCw => switch (this) {
        Direction.up => Direction.right,
        Direction.right => Direction.down,
        Direction.down => Direction.left,
        Direction.left => Direction.up,
      };

  Direction get rotatedCcw => switch (this) {
        Direction.up => Direction.left,
        Direction.left => Direction.down,
        Direction.down => Direction.right,
        Direction.right => Direction.up,
      };
}

/// Gameplay role of a board node.
enum NodeKind { normal, locked, relay }

/// Immutable data for a single board node.
///
/// [x] and [y] are `final` — grid coordinates never change after placement.
class NodeData {
  final int id;
  final int x;
  final int y;
  final Direction dir;
  final Color color;

  /// Index into [AppColors.nodePalette] when assigned at generation; `-1` uses
  /// [AppColors.matchNodePaletteIndex] for colorblind remapping only.
  final int colorSlot;

  /// Locked until all 4-neighbors are cleared; relay rotates its row on extract.
  final NodeKind kind;

  final bool isCore;

  /// Phase gates block extraction until the preceding phase is fully cleared.
  final int phaseGroup;

  NodeData({
    required this.id,
    required this.x,
    required this.y,
    required this.dir,
    this.color = AppColors.nodeDefault,
    this.colorSlot = -1,
    this.kind = NodeKind.normal,
    this.isCore = false,
    this.phaseGroup = 0,
  });

  NodeData clone() => NodeData(
        id: id,
        x: x,
        y: y,
        dir: dir,
        color: color,
        colorSlot: colorSlot,
        kind: kind,
        isCore: isCore,
        phaseGroup: phaseGroup,
      );

  NodeData copyWith({
    int? id,
    int? x,
    int? y,
    Direction? dir,
    Color? color,
    int? colorSlot,
    NodeKind? kind,
    bool? isCore,
    int? phaseGroup,
  }) =>
      NodeData(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        dir: dir ?? this.dir,
        color: color ?? this.color,
        colorSlot: colorSlot ?? this.colorSlot,
        kind: kind ?? this.kind,
        isCore: isCore ?? this.isCore,
        phaseGroup: phaseGroup ?? this.phaseGroup,
      );

  @override
  String toString() => 'Node($id, at: $x,$y, dir: $dir)';
}

class PortalPair {
  final int x1;
  final int y1;
  final int x2;
  final int y2;

  const PortalPair(this.x1, this.y1, this.x2, this.y2);

  String get cell1 => '$x1,$y1';
  String get cell2 => '$x2,$y2';
}

class LevelData {
  final int levelId;
  final int gridWidth;
  final int gridHeight;

  /// When non-null and non-empty, only these `"x,y"` cells may hold nodes
  /// (irregular silhouette). Blocking rays still use straight lines across the
  /// full `gridWidth`×`gridHeight` bounds. When null, every cell may hold a node.
  final Set<String>? playCells;

  final List<NodeData> nodes;
  final List<PortalPair> portalPairs;

  /// Silhouette the Director picked for this board, when known.
  ///
  /// Pure metadata — nothing about generation or gameplay reads it, so it never
  /// affects level bytes. Null for boards that do not come from the Director
  /// (tutorial levels, hand-authored seeds), and consumers must treat null as
  /// "unknown" rather than guessing a family.
  final SilhouetteId? silhouetteId;

  LevelData({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.nodes,
    this.playCells,
    this.portalPairs = const [],
    this.silhouetteId,
  });

  /// Cores on the board.
  int get coreCount => nodes.where((n) => n.isCore).length;

  /// Locked nodes on the board.
  int get lockCount => nodes.where((n) => n.kind == NodeKind.locked).length;

  /// Relay nodes on the board.
  int get relayCount => nodes.where((n) => n.kind == NodeKind.relay).length;

  /// Distinct phase gates — one per non-zero phase group, since a gate is the
  /// boundary between groups rather than a property of each node.
  int get phaseGateCount =>
      nodes.map((n) => n.phaseGroup).where((g) => g > 0).toSet().length;

  /// Layout invariants (not solvability). Returns `null` if valid.
  static String? layoutValidationMessage(LevelData data) {
    final seen = <String>{};
    final play = data.playCells;
    for (final n in data.nodes) {
      if (n.x < 0 ||
          n.x >= data.gridWidth ||
          n.y < 0 ||
          n.y >= data.gridHeight) {
        return 'Node ${n.id} at (${n.x},${n.y}) out of bounds for '
            '${data.gridWidth}x${data.gridHeight}';
      }
      final key = '${n.x},${n.y}';
      if (!seen.add(key)) {
        return 'Duplicate cell $key';
      }
      if (play != null && play.isNotEmpty && !play.contains(key)) {
        return 'Node ${n.id} at $key not in playCells';
      }
    }
    return null;
  }
}
