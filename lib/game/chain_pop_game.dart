import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'board_layout.dart';
import 'levels/grid_cell_key.dart';
import 'levels/level.dart';
import 'levels/level_manager.dart';
import 'levels/level_solver.dart';
import 'levels/generation/difficulty_mode.dart';
import 'components/ambient_background_component.dart';
import 'components/arrow_axis_guide_component.dart';
import 'components/board_mask_component.dart';
import 'components/combo_text_component.dart';
import 'components/extraction_burst_component.dart';
import 'components/node_component.dart';
import 'components/ray_preview_component.dart';
import 'components/restored_network_component.dart';
import '../services/game_sfx.dart';
import '../theme/app_colors.dart';
import '../theme/world_theme.dart';

/// The core Flame game engine for Unbound.
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

  /// Playfield palette for the current world (or daily/tutorial fallback).
  final WorldTheme theme;

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
  final Vector2 _occupiedOffset = Vector2.zero();
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

  RayPreviewComponent? _rayPreview;

  /// Whether the long-press ray preview is showing (ambient layers freeze
  /// their motion while the player is aiming).
  bool get rayPreviewActive => _rayPreview != null;

  /// Whether alignment guides are shown (driven by HUD; cleared after a valid extraction).
  bool get axisGuidesVisible => _axisGuidesVisible;

  // ── Ambient / restoration presentation layers ──────────────────────────────

  AmbientBackgroundComponent? _ambient;
  RestoredNetworkComponent? _restoredLayer;

  /// Cells vacated by extracted nodes — source of truth for the restoration
  /// trail, survives board relayout (the component is reseeded from this).
  final Set<(int, int)> _restoredCells = {};

  @visibleForTesting
  Set<(int, int)> get restoredCellsForTest => Set.unmodifiable(_restoredCells);

  // ── Cascade finale (core win) ──────────────────────────────────────────────

  /// When the last core is restored with nodes still on the board, the rest
  /// auto-pop in a ripple radiating from the final core before [onWin] fires —
  /// "the network cascades back online", literally.
  bool _finaleActive = false;
  double _finaleClock = 0;
  int _finaleIndex = 0;
  final List<(double, int)> _finaleSchedule = [];
  double _finaleWinAt = 0;
  int _lastExtractedX = 0;
  int _lastExtractedY = 0;

  bool get cascadeFinaleActive => _finaleActive;

  /// Mirrors persisted accessibility/audio flags — updated from [GameScreen] when preferences change.
  bool soundEnabled = true;
  bool hapticsEnabled = true;
  bool colorblindPalette = false;

  /// Plays short SFX via the Flutter layer ([GameAudioController]).
  void Function(GameSfx sfx, {double playbackRate})? onSfx;

  int _extractionStreak = 0;

  /// Consecutive valid extractions since the last jam (visible to HUD/visuals).
  int get extractionStreak => _extractionStreak;

  /// Network integrity — starts at 100%; jams reduce it.
  int networkIntegrity = 100;

  /// Total core nodes on this level (0 when classic clear-all win).
  int get totalCores =>
      levelData.nodes.where((n) => n.isCore).length;

  /// Cores already extracted.
  int get coresRestored => levelData.nodes
      .where((n) => n.isCore)
      .where((n) => !activeNodes.any((a) => a.id == n.id))
      .length;

  /// Whether this level uses core-restore win condition.
  bool get usesCoreWin => totalCores > 0;

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
    WorldTheme? theme,
    this.topReserved = 140.0,
    this.bottomReserved = 92.0,
  }) : theme = theme ?? WorldTheme.forLevel(levelId) {
    // HUD getters ([usesCoreWin], [totalCores]) are read by the first Flutter
    // build, which happens before [onLoad] — seed [levelData] eagerly when the
    // level is already generated.
    final preloaded = preloadedLevel;
    if (preloaded != null) levelData = preloaded;
  }

  @override
  Color backgroundColor() => theme.backgroundTint;

  @override
  Future<void> onLoad() async {
    // Use pre-generated level if provided — avoids a second generator run.
    levelData = preloadedLevel ?? LevelManager.getLevel(levelId, mode: difficulty);

    for (final node in levelData.nodes) {
      activeNodes.add(node.clone());
    }

    final ambient = AmbientBackgroundComponent(theme: theme)..priority = -200;
    _ambient = ambient;
    add(ambient);

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
    _tickCascadeFinale(dt);
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
    board.position.setFrom(_boardCenter - _occupiedOffset * _displayZoom + _pan);
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

    final bounds = OccupiedBounds.fromLevel(levelData, pad: 1);

    var cellSize = BoardLayoutMetrics.fitCellSizeForBounds(
      bandW: usableW,
      bandH: usableH,
      bboxWidth: bounds.bboxWidth,
      bboxHeight: bounds.bboxHeight,
      targetFill: 0.80,
    );
    if (cellSize <= 0 &&
        levelData.gridWidth > 0 &&
        levelData.gridHeight > 0) {
      cellSize = 1.0;
    }
    _cellSize = cellSize;

    final gridPixelW = cellSize * levelData.gridWidth;
    final gridPixelH = cellSize * levelData.gridHeight;

    final occupiedCenterX = (bounds.minX + bounds.maxX + 1) / 2.0 * cellSize;
    final occupiedCenterY = (bounds.minY + bounds.maxY + 1) / 2.0 * cellSize;

    _occupiedOffset.setValues(
      occupiedCenterX - gridPixelW / 2,
      occupiedCenterY - gridPixelH / 2,
    );

    _gridPixels.setValues(gridPixelW, gridPixelH);
    _usableSize.setValues(usableW, usableH);
    _boardCenter.setValues(screenW / 2, topReserved + usableH / 2);

    board = PositionComponent(
      position: _boardCenter - _occupiedOffset * _displayZoom + _pan,
      size: Vector2(gridPixelW, gridPixelH),
      anchor: Anchor.center,
    );

    final mask = BoardMaskComponent(
      levelData: levelData,
      cellSize: cellSize,
      theme: theme,
    );
    mask.priority = -100;
    board.add(mask);

    final restoredLayer = RestoredNetworkComponent(
      cellSize: cellSize,
      theme: theme,
      gridWidth: levelData.gridWidth,
      gridHeight: levelData.gridHeight,
    );
    restoredLayer.priority = -75;
    restoredLayer.seedAll(_restoredCells);
    _restoredLayer = restoredLayer;
    board.add(restoredLayer);

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

  /// Discrete zoom in from the toolbar (pinch / scroll still apply elsewhere).
  void zoomInStep() {
    _targetZoom = (_targetZoom * 1.12).clamp(_minZoom, _maxZoom);
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

  @visibleForTesting
  void refreshExtractableIdsForTest() => _rebuildExtractableIds();

  /// Shows a dotted ray from [node] to the grid edge or first blocker.
  void showRayPreview(NodeData node) {
    if (hasWon || isGameOver || !_boardLaidOut) return;
    hideRayPreview();
    final trace = LevelSolver.traceRay(node, activeNodes, levelData);
    final preview = RayPreviewComponent(
      source: node,
      trace: trace,
      cellSize: _cellSize,
      gridWidth: levelData.gridWidth,
      gridHeight: levelData.gridHeight,
    );
    preview.priority = 50;
    _rayPreview = preview;
    board.add(preview);
  }

  /// Clears any active long-press ray preview.
  void hideRayPreview() {
    _rayPreview?.removeFromParent();
    _rayPreview = null;
  }

  void registerExtraction(NodeData data) {
    hideRayPreview();
    _axisGuidesVisible = false;
    _extractionStreak++;
    _lastExtractedX = data.x;
    _lastExtractedY = data.y;
    if (data.isCore) {
      networkIntegrity = (networkIntegrity + 5).clamp(0, 100);
    }
    if (data.kind == NodeKind.relay) {
      _applyRelayRowRotation(data.y);
    }
    _undoStack.add(data.clone());
    activeNodes.removeWhere((n) => n.id == data.id);
    _rebuildExtractableIds();

    _spawnExtractionVisuals(data);
    _ambient?.setStreak(_extractionStreak);
    if (_boardLaidOut) {
      for (final comp in board.children.whereType<NodeComponent>()) {
        if (comp.isPopping || comp.isJamming) continue;
        final dist =
            (comp.data.x - data.x).abs() + (comp.data.y - data.y).abs();
        if (dist == 1) comp.nudge();
      }
      if (_extractionStreak >= 3 && _cellSize > 0) {
        final combo = ComboTextComponent(
          cellCenter: Vector2(
            (data.x + 0.5) * _cellSize,
            (data.y + 0.5) * _cellSize,
          ),
          streak: _extractionStreak,
          color: theme.accent,
          cellSize: _cellSize,
        )..priority = 60;
        board.add(combo);
      }
    }

    final total = levelData.nodes.length;
    final removed = total - activeNodes.length;
    onNodeRemoved?.call(removed, total);
    checkWinCondition();
  }

  /// Restoration-trail marker + ring burst + ambient ripple at the vacated
  /// cell. Shared by player extractions and the cascade finale.
  void _spawnExtractionVisuals(NodeData data) {
    _restoredCells.add((data.x, data.y));
    if (!_boardLaidOut || _cellSize <= 0) return;
    _restoredLayer?.addCell(data.x, data.y);
    final center = Vector2(
      (data.x + 0.5) * _cellSize,
      (data.y + 0.5) * _cellSize,
    );
    final burst = ExtractionBurstComponent(
      cellCenter: center,
      color: effectiveNodeColor(data),
      maxRadius: _cellSize * 0.8,
    )..priority = 5;
    board.add(burst);
    _ambient?.pulseAt(
      board.absolutePositionOf(center),
      radius: _cellSize * 2.2,
    );
  }

  void _applyRelayRowRotation(int rowY, {bool clockwise = true}) {
    for (var i = 0; i < activeNodes.length; i++) {
      final n = activeNodes[i];
      if (n.y != rowY) continue;
      activeNodes[i] =
          n.copyWith(dir: clockwise ? n.dir.rotatedCw : n.dir.rotatedCcw);
    }
    if (!_boardLaidOut) return;
    for (final comp in board.children.whereType<NodeComponent>()) {
      if (comp.data.y == rowY && activeNodes.any((n) => n.id == comp.data.id)) {
        final updated = activeNodes.firstWhere((n) => n.id == comp.data.id);
        comp.updateData(updated);
      }
    }
  }

  /// Restores the last removed node back onto the board.
  /// Returns true if an undo was performed.
  bool undo() {
    if (_undoStack.isEmpty || hasWon || isGameOver) return false;
    final restored = _undoStack.removeLast();
    if (_extractionStreak > 0) _extractionStreak--;
    _ambient?.setStreak(_extractionStreak);
    if (restored.kind == NodeKind.relay) {
      // Undo is LIFO, so the row holds exactly the nodes present when the
      // relay popped — rotating back restores their pre-pop directions.
      _applyRelayRowRotation(restored.y, clockwise: false);
    }
    activeNodes.add(restored);
    _rebuildExtractableIds();

    _restoredCells.remove((restored.x, restored.y));
    _restoredLayer?.removeCell(restored.x, restored.y);

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
    _ambient?.setStreak(0);
    networkIntegrity = (networkIntegrity - 8).clamp(0, 100);
    onJam?.call();
  }

  void checkWinCondition() {
    if (hasWon) return;
    if (usesCoreWin) {
      if (coresRestored >= totalCores) {
        hasWon = true;
        networkIntegrity = 100;
        if (_boardLaidOut && activeNodes.isNotEmpty) {
          _startCascadeFinale();
        } else {
          onWin();
        }
      }
      return;
    }
    if (activeNodes.isEmpty && !hasWon) {
      hasWon = true;
      onWin();
    }
  }

  /// Queues the remaining (non-core) nodes to auto-pop in a ripple ordered by
  /// Manhattan distance from the last restored core. [onWin] fires after the
  /// last pop settles. Input is already blocked because [hasWon] is set.
  void _startCascadeFinale() {
    final remaining = List<NodeData>.of(activeNodes)
      ..sort((a, b) {
        final da = (a.x - _lastExtractedX).abs() + (a.y - _lastExtractedY).abs();
        final db = (b.x - _lastExtractedX).abs() + (b.y - _lastExtractedY).abs();
        return da.compareTo(db);
      });
    final step = (1.2 / remaining.length).clamp(0.05, 0.09);
    _finaleSchedule.clear();
    for (var i = 0; i < remaining.length; i++) {
      _finaleSchedule.add((0.15 + i * step, remaining[i].id));
    }
    _finaleWinAt = 0.15 + (remaining.length - 1) * step + 0.5;
    _finaleClock = 0;
    _finaleIndex = 0;
    _finaleActive = true;
  }

  void _tickCascadeFinale(double dt) {
    if (!_finaleActive) return;
    _finaleClock += dt;
    while (_finaleIndex < _finaleSchedule.length &&
        _finaleClock >= _finaleSchedule[_finaleIndex].$1) {
      final id = _finaleSchedule[_finaleIndex].$2;
      _finaleIndex++;
      final idx = activeNodes.indexWhere((n) => n.id == id);
      if (idx < 0) continue;
      final node = activeNodes.removeAt(idx);
      _spawnExtractionVisuals(node);
      playSfx(
        GameSfx.pop,
        playbackRate: (1.0 + _finaleIndex * 0.05).clamp(1.0, 1.6),
      );
      for (final comp in board.children.whereType<NodeComponent>()) {
        if (comp.data.id == id) {
          comp.triggerCascadePop();
          break;
        }
      }
      final total = levelData.nodes.length;
      onNodeRemoved?.call(total - activeNodes.length, total);
    }
    if (_finaleClock >= _finaleWinAt) {
      _finaleActive = false;
      onWin();
    }
  }

  /// Whether [showHint] would currently highlight a removable node.
  bool hasAvailableHint() =>
      LevelSolver.getHint(activeNodes, levelData) != null;

  /// Highlights a valid hint node. Returns `false` if none exists.
  bool showHint() {
    final hintNode = LevelSolver.getHint(activeNodes, levelData);
    if (hintNode == null) return false;
    playSfx(GameSfx.hint);
    for (final comp in board.children.whereType<NodeComponent>()) {
      if (comp.data.id == hintNode.id) {
        comp.highlight();
        break;
      }
    }
    return true;
  }

  void restart() {
    hideRayPreview();
    _extractionStreak = 0;
    _ambient?.setStreak(0);
    _finaleActive = false;
    _finaleSchedule.clear();
    _restoredCells.clear();
    hasWon = false;
    isGameOver = false;
    networkIntegrity = 100;
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
    final positions = <int>{
      for (final n in activeNodes) gridCellKey(n.x, n.y),
    };
    for (final node in activeNodes) {
      final key = gridCellKey(node.x, node.y);
      positions.remove(key);
      if (LevelSolver.canRemoveWithPositions(node, positions, levelData)) {
        _extractableIds.add(node.id);
      }
      positions.add(key);
    }
  }
}
