import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'board_layout.dart';
import 'levels/level.dart';
import 'levels/level_manager.dart';
import 'levels/level_solver.dart';
import 'levels/generation/difficulty_mode.dart';
import 'components/arrow_axis_guide_component.dart';
import 'components/board_mask_component.dart';
import 'components/node_component.dart';
import '../services/game_sfx.dart';
import '../theme/app_colors.dart';

/// The core Flame game engine for Chain Pop.
///
/// Key design points:
///  • Accept an optional [preloadedLevel] so [GameScreen] can generate the
///    level once and reuse it — avoids double-generation.
///  • [topReserved] / [bottomReserved] match stacked HUD height; [GameScreen]
///    measures the real overlays and calls [configurePlayfieldInsets].
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

  /// Logical pixels from the top of the canvas to the top of the playfield.
  /// Must match the stacked Flutter HUD height (SafeArea + header). Updated by
  /// [configurePlayfieldInsets] from [GameScreen] using real measurements.
  double topReserved;

  /// Logical pixels reserved above the bottom edge for the Flutter toolbar.
  double bottomReserved;

  late LevelData levelData;
  final List<NodeData> activeNodes = [];

  /// IDs of nodes that are currently extractable.
  /// Rebuilt after every extraction — O(n) once, then O(1) per NodeComponent lookup.
  final Set<int> _extractableIds = {};

  /// Stack of removed nodes for undo. Most recent removal is last.
  final List<NodeData> _undoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;

  bool hasWon = false;
  bool isGameOver = false;
  late PositionComponent board;
  double _cellSize = 0;

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

  /// Last [size] used for layout; avoids rebuilding every frame when the
  /// embedder reports tiny [onGameResize] deltas (which recreated all nodes and
  /// caused flicker, and dropped [isPopping] nodes that are off [activeNodes]).
  Vector2? _lastLaidOutGameSize;
  static const double _layoutResizeEpsilon = 1.5;

  bool _gameSizeChangedMeaningfully(Vector2 s) {
    final last = _lastLaidOutGameSize;
    if (last == null) return true;
    return (s.x - last.x).abs() >= _layoutResizeEpsilon ||
        (s.y - last.y).abs() >= _layoutResizeEpsilon;
  }

  /// Zoom when the current pinch began; Flutter's [ScaleUpdateDetails.scale] is
  /// **cumulative** (≈1.0 at start), not per-frame — must not multiply into
  /// [_targetZoom] each update or zoom explodes.
  double _pinchBaseZoom = 1.0;
  int _lastScalePointerCount = 0;

  /// Row/column guide lines ([ArrowAxisGuideComponent]); toggled from HUD only.
  bool _axisGuidesVisible = false;

  /// Whether alignment guides are shown (driven by HUD; cleared after a valid extraction).
  bool get axisGuidesVisible => _axisGuidesVisible;

  /// Mirrors persisted accessibility/audio flags — updated from [GameScreen] when preferences change.
  bool soundEnabled = true;
  bool hapticsEnabled = true;
  bool colorblindPalette = false;

  /// Plays short SFX via the Flutter layer ([GameAudioController]).
  void Function(GameSfx sfx, {double playbackRate})? onSfx;

  int _extractionStreak = 0;

  /// Playback rate for [GameSfx.pop] — rises with consecutive good extractions.
  double get popPlaybackRate =>
      1.0 + math.min((_extractionStreak - 1) * 0.06, 0.42);

  void playSfx(GameSfx sfx, {double playbackRate = 1.0}) {
    if (!soundEnabled) return;
    onSfx?.call(sfx, playbackRate: playbackRate);
  }

  static const double _insetConfigEpsilon = 1.0;

  /// Sync vertical bands with the real [GameScreen] HUD (measured in Flutter).
  void configurePlayfieldInsets({
    required double top,
    required double bottom,
  }) {
    if ((top - topReserved).abs() < _insetConfigEpsilon &&
        (bottom - bottomReserved).abs() < _insetConfigEpsilon) {
      return;
    }
    topReserved = top;
    bottomReserved = bottom;
    if (!isLoaded || !_boardLaidOut) return;
    _targetZoom = _minZoom;
    _displayZoom = _minZoom;
    _pan.setZero();
    _pinchActive = false;
    _lastScalePointerCount = 0;
    _setupBoard(preserveAnimatingNodes: true);
  }

  Color effectiveNodeColor(NodeData data) {
    if (!colorblindPalette) return data.color;
    final slot = data.colorSlot >= 0
        ? data.colorSlot
        : AppColors.matchNodePaletteIndex(data.color);
    const list = AppColors.nodePaletteColorblind;
    return list[slot % list.length];
  }

  ChainPopGame({
    required this.levelId,
    required this.difficulty,
    required this.onWin,
    this.onJam,
    this.onNodeRemoved,
    this.preloadedLevel,
    this.topReserved = 140.0,
    this.bottomReserved = 92.0,
  });

  @override
  Color backgroundColor() => AppColors.background;

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
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!isLoaded || size.x <= 0 || size.y <= 0) return;
    if (!_boardLaidOut) return;
    if (!_gameSizeChangedMeaningfully(size)) return;
    _targetZoom = _minZoom;
    _displayZoom = _minZoom;
    _pan.setZero();
    _pinchActive = false;
    _lastScalePointerCount = 0;
    _setupBoard(preserveAnimatingNodes: true);
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

  void _setupBoard({bool preserveAnimatingNodes = false}) {
    final orphans = <(NodeComponent, Vector2)>[];
    if (_boardLaidOut) {
      if (preserveAnimatingNodes) {
        for (final c in board.children.whereType<NodeComponent>()) {
          if (c.isPopping || c.isJamming) {
            orphans.add((c, c.absoluteCenter.clone()));
            c.removeFromParent();
          }
        }
      }
      board.removeFromParent();
      _boardLaidOut = false;
    }

    final skipActiveIds = <int>{
      for (final o in orphans) o.$1.data.id,
    };

    final screenW = size.x;
    final screenH = size.y;

    const margin = 24.0;
    final usableW = math.max(0.0, screenW - margin * 2);
    // Shrink vertical space to avoid overlapping Flutter HUD layers.
    final usableH = math.max(
      0.0,
      screenH - topReserved - bottomReserved - margin,
    );

    var cellSize = BoardLayoutMetrics.fitCellSize(
      bandW: usableW,
      bandH: usableH,
      gridWidth: levelData.gridWidth,
      gridHeight: levelData.gridHeight,
    );
    if (cellSize <= 0 &&
        levelData.gridWidth > 0 &&
        levelData.gridHeight > 0) {
      cellSize = 1.0;
    }
    _cellSize = cellSize;

    assert(() {
      const eps = 1e-6;
      if (cellSize <= 0) return true;
      return cellSize * levelData.gridWidth <= usableW + eps &&
          cellSize * levelData.gridHeight <= usableH + eps;
    }());

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
      if (skipActiveIds.contains(nodeData.id)) continue;
      board.add(NodeComponent(data: nodeData, cellSize: cellSize));
    }

    add(board);
    _boardLaidOut = true;
    _applyBoardTransform();

    for (final o in orphans) {
      final node = o.$1;
      final worldCenter = o.$2;
      board.add(node);
      node.position.setFrom(board.toLocal(worldCenter));
      if (node.isJamming) {
        node.resyncJamRestPositionForCellSize(cellSize);
      }
    }

    (_lastLaidOutGameSize ??= Vector2.zero()).setValues(size.x, size.y);
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
    _extractionStreak++;
    _undoStack.add(data.clone());
    activeNodes.removeWhere((n) => n.id == data.id);
    _rebuildExtractableIds();

    try {
      final total = levelData.nodes.length;
      final removed = total - activeNodes.length;
      onNodeRemoved?.call(removed, total);
    } catch (_) {}
  }

  /// Restores the last removed node back onto the board.
  /// Returns true if an undo was performed.
  bool undo() {
    if (_undoStack.isEmpty || hasWon || isGameOver) return false;
    final restored = _undoStack.removeLast();
    if (_extractionStreak > 0) _extractionStreak--;
    activeNodes.add(restored);
    _rebuildExtractableIds();

    if (_boardLaidOut && _cellSize > 0) {
      board.add(NodeComponent(data: restored, cellSize: _cellSize));
    }

    final total = levelData.nodes.length;
    final removed = total - activeNodes.length;
    onNodeRemoved?.call(removed, total);
    return true;
  }

  void reportJam() {
    _extractionStreak = 0;
    onJam?.call();
  }

  void checkWinCondition() {
    if (activeNodes.isEmpty && !hasWon) {
      hasWon = true;
      onWin();
    }
  }

  void showHint() {
    final hintNode = LevelSolver.getHint(activeNodes, levelData);
    if (hintNode == null) return;
    playSfx(GameSfx.hint);
    for (final comp in board.children.whereType<NodeComponent>()) {
      if (comp.data.id == hintNode.id) {
        comp.highlight();
        break;
      }
    }
  }

  void restart() {
    _extractionStreak = 0;
    hasWon = false;
    isGameOver = false;
    activeNodes.clear();
    _undoStack.clear();
    for (final node in levelData.nodes) {
      activeNodes.add(node.clone());
    }
    _lastScalePointerCount = 0;
    _targetZoom = _minZoom;
    _displayZoom = _minZoom;
    _pan.setZero();
    _pinchActive = false;
    _axisGuidesVisible = false;
    _rebuildExtractableIds();
    _setupBoard(preserveAnimatingNodes: false);
    onNodeRemoved?.call(0, levelData.nodes.length);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  /// Refreshes which nodes can exit the board. O(n × grid span): one position
  /// set for all [activeNodes], then each node is checked via a ray walk only.
  void _rebuildExtractableIds() {
    _extractableIds.clear();
    final positions = <String>{
      for (final n in activeNodes) '${n.x},${n.y}',
    };
    for (final node in activeNodes) {
      final key = '${node.x},${node.y}';
      positions.remove(key);
      if (LevelSolver.canRemoveWithPositions(node, positions, levelData)) {
        _extractableIds.add(node.id);
      }
      positions.add(key);
    }
  }
}
