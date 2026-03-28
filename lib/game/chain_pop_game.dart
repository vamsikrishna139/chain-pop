import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'levels/level.dart';
import 'levels/level_manager.dart';
import 'levels/level_solver.dart';
import 'levels/generation/difficulty_mode.dart';
import 'components/arrow_axis_guide_component.dart';
import 'components/board_mask_component.dart';
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
class ChainPopGame extends FlameGame with ScaleDetector, ScrollDetector {
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

  // ── Board zoom / pan (scale is around board centre; pan in screen space) ──
  static const double _minZoom = 1.0;
  static const double _maxZoom = 2.75;
  static const double _zoomAnimSpeed = 14.0;
  static const double _panClearSpeed = 11.0;

  double _targetZoom = 1.0;
  double _displayZoom = 1.0;
  final Vector2 _pan = Vector2.zero();
  final Vector2 _gridPixels = Vector2.zero();
  final Vector2 _usableSize = Vector2.zero();
  final Vector2 _boardCenter = Vector2.zero();
  bool _pinchActive = false;
  bool _boardLaidOut = false;

  /// Zoom when the current pinch began; Flutter's [ScaleUpdateDetails.scale] is
  /// **cumulative** (≈1.0 at start), not per-frame — must not multiply into
  /// [_targetZoom] each update or zoom explodes.
  double _pinchBaseZoom = 1.0;
  int _lastScalePointerCount = 0;

  /// Row/column guide lines ([ArrowAxisGuideComponent]); toggled from HUD only.
  bool _axisGuidesVisible = false;

  /// Whether alignment guides are shown (driven by HUD; cleared after a valid extraction).
  bool get axisGuidesVisible => _axisGuidesVisible;

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

  @override
  void update(double dt) {
    _tickZoomAndPan(dt);
    _applyBoardTransform();
    super.update(dt);
  }

  void _tickZoomAndPan(double dt) {
    if (!_pinchActive) {
      final zt = 1.0 - math.exp(-_zoomAnimSpeed * dt);
      _displayZoom += (_targetZoom - _displayZoom) * zt;
      if (_targetZoom <= 1.001) {
        final pt = 1.0 - math.exp(-_panClearSpeed * dt);
        _pan.addScaled(_pan, -pt);
      }
    }
    _clampPan();
  }

  void _applyBoardTransform() {
    if (!_boardLaidOut) return;
    board.position.setFrom(_boardCenter + _pan);
    board.scale.setAll(_displayZoom);
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

    _gridPixels.setValues(gridPixelW, gridPixelH);
    _usableSize.setValues(usableW, usableH);
    _boardCenter.setValues(
      offsetX + gridPixelW / 2,
      offsetY + gridPixelH / 2,
    );

    board = PositionComponent(
      position: _boardCenter + _pan,
      size: Vector2(gridPixelW, gridPixelH),
      anchor: Anchor.center,
    );

    final mask = BoardMaskComponent(levelData: levelData, cellSize: cellSize);
    mask.priority = -100;
    board.add(mask);

    final axisGuides = ArrowAxisGuideComponent(
      cellSize: cellSize,
      gridWidth: levelData.gridWidth,
      gridHeight: levelData.gridHeight,
    );
    axisGuides.priority = -50;
    board.add(axisGuides);

    for (final nodeData in activeNodes) {
      board.add(NodeComponent(data: nodeData, cellSize: cellSize));
    }

    add(board);
    _boardLaidOut = true;
    _applyBoardTransform();
  }

  void _clampPan() {
    if (_displayZoom <= 1.01 && _targetZoom <= 1.01) {
      _pan.setZero();
      return;
    }
    final zw = _gridPixels.x * _displayZoom;
    final zh = _gridPixels.y * _displayZoom;
    final maxX = math.max(0.0, zw / 2 - _usableSize.x / 2 + 32);
    final maxY = math.max(0.0, zh / 2 - _usableSize.y / 2 + 32);
    _pan.x = _pan.x.clamp(-maxX, maxX);
    _pan.y = _pan.y.clamp(-maxY, maxY);
  }

  @override
  void onScaleStart(ScaleStartInfo info) {
    if (info.pointerCount >= 2) {
      _pinchBaseZoom = _targetZoom;
    }
    _pinchActive = info.pointerCount >= 2;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    if (info.pointerCount >= 2) {
      if (_lastScalePointerCount < 2) {
        _pinchBaseZoom = _targetZoom;
      }
      _pinchActive = true;
      final g = info.raw.scale;
      if (g.isFinite && g > 0) {
        _targetZoom = (_pinchBaseZoom * g).clamp(_minZoom, _maxZoom);
        _displayZoom = _targetZoom;
      }
    }
    if (info.pointerCount >= 2) {
      _pan.add(info.delta.global);
    } else if (_displayZoom > 1.02) {
      _pan.add(info.delta.global);
    }
    _lastScalePointerCount = info.pointerCount;
    _clampPan();
    _applyBoardTransform();
  }

  @override
  void onScaleEnd(ScaleEndInfo info) {
    _pinchActive = false;
    _lastScalePointerCount = 0;
    _clampPan();
  }

  @override
  void onScroll(PointerScrollInfo info) {
    final dy = info.scrollDelta.global.y;
    if (dy == 0) return;
    final factor = dy > 0 ? 0.9 : 1.1;
    _targetZoom = (_targetZoom * factor).clamp(_minZoom, _maxZoom);
  }

  /// Animated reset to default framing.
  void resetView() {
    _targetZoom = _minZoom;
    _pinchActive = false;
  }

  /// Toggles row/column alignment guides (see [axisGuidesVisible]).
  void toggleAxisGuides() {
    _axisGuidesVisible = !_axisGuidesVisible;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool canExtract(NodeData data) =>
      LevelSolver.canRemove(data, activeNodes, levelData);

  /// Returns true if [nodeId] is currently extractable.
  /// O(1) — checked per frame by every [NodeComponent].
  bool isExtractable(int nodeId) => _extractableIds.contains(nodeId);

  void registerExtraction(NodeData data) {
    _axisGuidesVisible = false;
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
    final hintNode = LevelSolver.getHint(activeNodes, levelData);
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
    _boardLaidOut = false;
    _lastScalePointerCount = 0;
    _targetZoom = _minZoom;
    _displayZoom = _minZoom;
    _pan.setZero();
    _pinchActive = false;
    _axisGuidesVisible = false;
    _rebuildExtractableIds();
    _setupBoard();
    onNodeRemoved?.call(0, levelData.nodes.length);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _rebuildExtractableIds() {
    _extractableIds.clear();
    for (final node in activeNodes) {
      if (LevelSolver.canRemove(node, activeNodes, levelData)) {
        _extractableIds.add(node.id);
      }
    }
  }
}
