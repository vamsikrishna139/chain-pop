import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'levels/level.dart';
import 'components/node_component.dart';

class ChainPopGame extends FlameGame {
  final int levelId;
  final VoidCallback onWin;

  late LevelData levelData;
  final List<NodeData> activeNodes = [];
  bool hasWon = false;

  ChainPopGame({required this.levelId, required this.onWin});

  @override
  Color backgroundColor() => const Color(0xFF1E1E24);

  @override
  Future<void> onLoad() async {
    levelData = LevelManager.getLevel(levelId) ?? LevelManager.levels.first;
    
    // Copy nodes so we don't modify the static definition
    for (var node in levelData.nodes) {
      activeNodes.add(node.clone());
    }

    _setupBoard();
  }

  void _setupBoard() {
    // Calculate cell size based on screen size
    final screenWidth = size.x;
    final screenHeight = size.y;
    
    // Leave some margin
    final margin = screenWidth * 0.1;
    final usableWidth = screenWidth - (margin * 2);
    final usableHeight = screenHeight - (margin * 2);
    
    final cellWidth = usableWidth / levelData.gridWidth;
    final cellHeight = usableHeight / levelData.gridHeight;
    final cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

    // Calculate offset to center the grid
    final gridPixelWidth = cellSize * levelData.gridWidth;
    final gridPixelHeight = cellSize * levelData.gridHeight;
    
    final offsetX = (screenWidth - gridPixelWidth) / 2;
    final offsetY = (screenHeight - gridPixelHeight) / 2;

    // Create container for the board to apply offset easily
    final board = PositionComponent(
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
    // Check if there is any active node in the path
    for (var other in activeNodes) {
      if (other.id == data.id) continue;
      
      switch (data.dir) {
        case Direction.up:
          if (other.x == data.x && other.y < data.y) return false;
          break;
        case Direction.down:
          if (other.x == data.x && other.y > data.y) return false;
          break;
        case Direction.left:
          if (other.y == data.y && other.x < data.x) return false;
          break;
        case Direction.right:
          if (other.y == data.y && other.x > data.x) return false;
          break;
      }
    }
    return true; // Path is clear
  }

  void registerExtraction(NodeData data) {
    activeNodes.removeWhere((node) => node.id == data.id);
  }

  void checkWinCondition() {
    if (activeNodes.isEmpty && !hasWon) {
      hasWon = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        onWin();
      });
    }
  }
}
