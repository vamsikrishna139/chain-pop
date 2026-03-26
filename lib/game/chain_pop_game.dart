import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'levels/level.dart';
import 'levels/level_manager.dart';
import 'levels/level_solver.dart';
import 'components/node_component.dart';

class ChainPopGame extends FlameGame {
  final int levelId;
  final VoidCallback onWin;

  late LevelData levelData;
  final List<NodeData> activeNodes = [];
  bool hasWon = false;
  late PositionComponent board;

  ChainPopGame({required this.levelId, required this.onWin});

  @override
  Color backgroundColor() => const Color(0xFF0F0F13);

  @override
  Future<void> onLoad() async {
    levelData = LevelManager.getLevel(levelId);
    
    for (var node in levelData.nodes) {
      activeNodes.add(node.clone());
    }

    _setupBoard();
  }

  void _setupBoard() {
    final screenWidth = size.x;
    final screenHeight = size.y;
    
    final margin = 40.0;
    final usableWidth = screenWidth - (margin * 2);
    final usableHeight = screenHeight - (margin * 4);
    
    final cellWidth = usableWidth / levelData.gridWidth;
    final cellHeight = usableHeight / levelData.gridHeight;
    final cellSize = (cellWidth < cellHeight ? cellWidth : cellHeight).clamp(40.0, 100.0);

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

  bool canExtract(NodeData data) {
    return LevelSolver.canRemove(data, activeNodes);
  }

  void registerExtraction(NodeData data) {
    activeNodes.removeWhere((node) => node.id == data.id);
  }

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
