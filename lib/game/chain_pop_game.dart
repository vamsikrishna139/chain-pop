import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'levels/level.dart';
import 'levels/level_manager.dart';
import 'levels/level_solver.dart';
import 'levels/generation/difficulty_mode.dart';
import 'components/node_component.dart';

/// The core Flame game engine for Chain Pop.
///
/// Key design points:
///  • Accept an optional [preloadedLevel] so [GameScreen] can generate the
///    level once and reuse it — avoids double-generation.
///  • [topReserved] / [bottomReserved] tell the board to stay clear of the
///    Flutter HUD widgets overlaid on top of the Flame canvas.
///  • [extractableIds] is rebuilt after every extraction so [NodeComponent]
///    can query it O(1) per frame to show the extractable/blocked visual state.
class ChainPopGame extends FlameGame {
  final int levelId;
  final DifficultyMode difficulty;
  final VoidCallback onWin;
  final VoidCallback? onJam;
  final void Function(int removed, int total)? onNodeRemoved;

  /// Pre-generated [LevelData] from [GameScreen]. When provided, [onLoad]
  /// skips the generator call — no double-generation.
  final LevelData? preloadedLevel;

  /// Logical pixels reserved for the top HUD. The board is shifted down by
  /// this amount so it doesn't sit behind the Flutter overlay widgets.
  final double topReserved;

  /// Logical pixels reserved for the bottom bar.
  final double bottomReserved;

  late LevelData levelData;
  final List<NodeData> activeNodes = [];

  /// IDs of nodes that are currently extractable.
  /// Rebuilt after every extraction — O(n) once, then O(1) per NodeComponent lookup.
  final Set<int> _extractableIds = {};

  bool hasWon = false;
  late PositionComponent board;

  ChainPopGame({
    required this.levelId,
    required this.difficulty,
    required this.onWin,
    this.onJam,
    this.onNodeRemoved,
    this.preloadedLevel,
    this.topReserved = 130.0,
    this.bottomReserved = 88.0,
  });

  @override
  Color backgroundColor() => const Color(0xFF0F0F13);

  @override
  Future<void> onLoad() async {
    // Use pre-generated level if provided — avoids a second generator run.
    levelData = preloadedLevel ?? LevelManager.getLevel(levelId, mode: difficulty);

    for (final node in levelData.nodes) {
      activeNodes.add(node.clone());
    }

    _rebuildExtractableIds();
    _setupBoard();
  }

  void _setupBoard() {
    final screenW = size.x;
    final screenH = size.y;

    const margin = 24.0;
    final usableW = screenW - margin * 2;
    // Shrink vertical space to avoid overlapping Flutter HUD layers.
    final usableH = screenH - topReserved - bottomReserved - margin;

    final cellW = usableW / levelData.gridWidth;
    final cellH = usableH / levelData.gridHeight;
    final cellSize = (cellW < cellH ? cellW : cellH).clamp(26.0, 96.0);

    final gridPixelW = cellSize * levelData.gridWidth;
    final gridPixelH = cellSize * levelData.gridHeight;

    // Centre horizontally; offset vertically into the safe zone.
    final offsetX = (screenW - gridPixelW) / 2;
    final offsetY = topReserved + (usableH - gridPixelH) / 2;

    board = PositionComponent(
      position: Vector2(offsetX, offsetY),
      size: Vector2(gridPixelW, gridPixelH),
    );

    for (final nodeData in activeNodes) {
      board.add(NodeComponent(data: nodeData, cellSize: cellSize));
    }

    add(board);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool canExtract(NodeData data) => LevelSolver.canRemove(data, activeNodes);

  /// Returns true if [nodeId] is currently extractable.
  /// O(1) — checked per frame by every [NodeComponent].
  bool isExtractable(int nodeId) => _extractableIds.contains(nodeId);

  void registerExtraction(NodeData data) {
    activeNodes.removeWhere((n) => n.id == data.id);
    _rebuildExtractableIds();

    try {
      final total = levelData.nodes.length;
      final removed = total - activeNodes.length;
      onNodeRemoved?.call(removed, total);
    } catch (_) {
      // levelData not yet initialised (unit-test scenario).
    }
  }

  void reportJam() => onJam?.call();

  void checkWinCondition() {
    if (activeNodes.isEmpty && !hasWon) {
      hasWon = true;
      onWin();
    }
  }

  void showHint() {
    final hintNode = LevelSolver.getHint(activeNodes);
    if (hintNode == null) return;
    for (final comp in board.children.whereType<NodeComponent>()) {
      if (comp.data.id == hintNode.id) {
        comp.highlight();
        break;
      }
    }
  }

  void restart() {
    hasWon = false;
    activeNodes.clear();
    for (final node in levelData.nodes) {
      activeNodes.add(node.clone());
    }
    board.removeFromParent();
    _rebuildExtractableIds();
    _setupBoard();
    onNodeRemoved?.call(0, levelData.nodes.length);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _rebuildExtractableIds() {
    _extractableIds.clear();
    for (final node in activeNodes) {
      if (LevelSolver.canRemove(node, activeNodes)) {
        _extractableIds.add(node.id);
      }
    }
  }
}
