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
/// Accepts both a [levelId] and a [difficulty] so the level generator
/// produces a puzzle appropriate for the player's chosen mode.
class ChainPopGame extends FlameGame {
  final int levelId;
  final DifficultyMode difficulty;
  final VoidCallback onWin;

  /// Called whenever the player taps a node that is currently blocked.
  /// The screen uses this to track jams for star calculation.
  final VoidCallback? onJam;

  late LevelData levelData;
  final List<NodeData> activeNodes = [];
  bool hasWon = false;
  late PositionComponent board;

  ChainPopGame({
    required this.levelId,
    required this.difficulty,
    required this.onWin,
    this.onJam,
  });

  @override
  Color backgroundColor() {
    // Very subtle difficulty tint over the dark background.
    // Blended with the base colour 0xFF0F0F13.
    return const Color(0xFF0F0F13);
  }

  @override
  Future<void> onLoad() async {
    levelData = LevelManager.getLevel(levelId, mode: difficulty);

    for (var node in levelData.nodes) {
      activeNodes.add(node.clone());
    }

    _setupBoard();
  }

  void _setupBoard() {
    final screenWidth = size.x;
    final screenHeight = size.y;

    const margin = 40.0;
    final usableWidth = screenWidth - (margin * 2);
    final usableHeight = screenHeight - (margin * 4);

    final cellWidth = usableWidth / levelData.gridWidth;
    final cellHeight = usableHeight / levelData.gridHeight;
    final cellSize = (cellWidth < cellHeight ? cellWidth : cellHeight)
        .clamp(28.0, 100.0); // clamp tighter for hard-mode large grids

    final gridPixelWidth = cellSize * levelData.gridWidth;
    final gridPixelHeight = cellSize * levelData.gridHeight;

    final offsetX = (screenWidth - gridPixelWidth) / 2;
    final offsetY = (screenHeight - gridPixelHeight) / 2;

    board = PositionComponent(
      position: Vector2(offsetX, offsetY),
      size: Vector2(gridPixelWidth, gridPixelHeight),
    );

    for (var nodeData in activeNodes) {
      final nodeComp = NodeComponent(data: nodeData, cellSize: cellSize);
      board.add(nodeComp);
    }

    add(board);
  }

  bool canExtract(NodeData data) => LevelSolver.canRemove(data, activeNodes);

  void registerExtraction(NodeData data) {
    activeNodes.removeWhere((node) => node.id == data.id);
  }

  /// Called by [NodeComponent] when a tap hits a blocked node.
  void reportJam() => onJam?.call();

  void checkWinCondition() {
    if (activeNodes.isEmpty && !hasWon) {
      hasWon = true;
      onWin();
    }
  }

  void showHint() {
    final hintNode = LevelSolver.getHint(activeNodes);
    if (hintNode != null) {
      for (var component in board.children.whereType<NodeComponent>()) {
        if (component.data.id == hintNode.id) {
          component.highlight();
          break;
        }
      }
    }
  }

  void restart() {
    hasWon = false;
    activeNodes.clear();
    for (var node in levelData.nodes) {
      activeNodes.add(node.clone());
    }
    board.removeFromParent();
    _setupBoard();
  }
}
