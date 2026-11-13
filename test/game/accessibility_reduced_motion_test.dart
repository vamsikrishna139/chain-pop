import 'dart:ui';
import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/components/ambient_background_component.dart';
import 'package:chain_pop/game/components/node_component.dart';
import 'package:chain_pop/game/components/ray_preview_component.dart';
import 'package:chain_pop/game/components/relay_sweep_component.dart';
import 'package:chain_pop/game/components/tutorial_coach_mark.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/theme/app_colors.dart';
import 'package:chain_pop/theme/world_theme.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

class CanvasOp {
  final String method;
  final int colorArgb;
  final double strokeWidth;
  final PaintingStyle style;
  final double radius;

  CanvasOp({
    required this.method,
    required this.colorArgb,
    this.strokeWidth = 0.0,
    this.style = PaintingStyle.fill,
    this.radius = 0.0,
  });

  @override
  String toString() => '$method: color=${colorArgb.toRadixString(16)}, width=$strokeWidth, style=$style, r=$radius';
}

class _RecordingCanvas implements Canvas {
  final List<CanvasOp> operations = [];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    operations.add(CanvasOp(
      method: 'drawRRect',
      colorArgb: paint.color.toARGB32(),
      strokeWidth: paint.strokeWidth,
      style: paint.style,
    ));
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    operations.add(CanvasOp(
      method: 'drawCircle',
      colorArgb: paint.color.toARGB32(),
      strokeWidth: paint.strokeWidth,
      style: paint.style,
      radius: radius,
    ));
  }

  @override
  void drawPath(Path path, Paint paint) {
    operations.add(CanvasOp(
      method: 'drawPath',
      colorArgb: paint.color.toARGB32(),
      strokeWidth: paint.strokeWidth,
      style: paint.style,
    ));
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    operations.add(CanvasOp(
      method: 'drawLine',
      colorArgb: paint.color.toARGB32(),
      strokeWidth: paint.strokeWidth,
      style: paint.style,
    ));
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    operations.add(CanvasOp(
      method: 'drawRect',
      colorArgb: paint.color.toARGB32(),
      strokeWidth: paint.strokeWidth,
      style: paint.style,
    ));
  }

  @override
  void drawShadow(Path path, Color color, double elevation, bool transparentOccluder) {
    operations.add(CanvasOp(method: 'drawShadow', colorArgb: color.toARGB32()));
  }

  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint) {
    operations.add(CanvasOp(method: 'drawArc', colorArgb: paint.color.toARGB32()));
  }

  @override
  void drawPicture(Picture picture) {
    operations.add(CanvasOp(method: 'drawPicture', colorArgb: 0));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void translate(double dx, double dy) {}

  @override
  void scale(double sx, [double? sy]) {}

  @override
  void rotate(double radians) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ChainPopGame _createGame({
  bool colorblind = false,
  bool ambient = true,
  bool reduced = false,
}) {
  final game = ChainPopGame(
    levelId: 1,
    difficulty: DifficultyMode.easy,
    onWin: () {},
  );
  game.colorblindPalette = colorblind;
  game.ambientMotion = ambient;
  game.reducedMotion = reduced;
  final n = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
  game.levelData = LevelData(
    levelId: 1,
    gridWidth: 5,
    gridHeight: 5,
    nodes: [n],
  );
  game.activeNodes.add(n);
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W2.8 Accessibility: Colorblind cues for meaning-carrying colors', () {
    testWidgets('Core node draws dashed pattern when colorblindPalette is true', (tester) async {
      final game = _createGame(colorblind: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final coreNode = NodeComponent(
        data: NodeData(id: 1, x: 2, y: 2, dir: Direction.up, isCore: true),
        cellSize: 40,
      );
      await game.world.add(coreNode);
      await tester.pump();

      final canvas = _RecordingCanvas();
      coreNode.render(canvas);

      final dashedPaths = canvas.operations.where(
        (op) => op.method == 'drawPath' && (op.strokeWidth - 2.4).abs() < 0.1,
      );
      expect(dashedPaths.isNotEmpty, isTrue,
          reason: 'Colorblind mode must draw dashed ring segments along core border');
    });

    testWidgets('Core node does NOT draw dashed pattern when colorblindPalette is false', (tester) async {
      final game = _createGame(colorblind: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final coreNode = NodeComponent(
        data: NodeData(id: 1, x: 2, y: 2, dir: Direction.up, isCore: true),
        cellSize: 40,
      );
      await game.world.add(coreNode);
      await tester.pump();

      final canvas = _RecordingCanvas();
      coreNode.render(canvas);

      final dashedPaths = canvas.operations.where(
        (op) => op.method == 'drawPath' && (op.strokeWidth - 2.4).abs() < 0.1,
      );
      expect(dashedPaths.isEmpty, isTrue,
          reason: 'Default mode must retain original solid core ring without dashes');
    });

    testWidgets('Relay node draws central diamond glyph when colorblindPalette is true', (tester) async {
      final game = _createGame(colorblind: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final relayNode = NodeComponent(
        data: NodeData(id: 2, x: 3, y: 3, dir: Direction.right, kind: NodeKind.relay),
        cellSize: 40,
      );
      await game.world.add(relayNode);
      await tester.pump();

      final canvas = _RecordingCanvas();
      relayNode.render(canvas);

      final glyphPath = canvas.operations.where(
        (op) => op.method == 'drawPath' && op.colorArgb == 0xFFFFFFFF,
      );
      expect(glyphPath.isNotEmpty, isTrue,
          reason: 'Relay in colorblind mode must render white central diamond glyph');
    });

    testWidgets('Blocker flash draws high-contrast outline when colorblindPalette is true', (tester) async {
      final game = _createGame(colorblind: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final node = NodeComponent(
        data: NodeData(id: 3, x: 1, y: 1, dir: Direction.left),
        cellSize: 40,
      );
      await game.world.add(node);
      await tester.pump();
      node.flashAsBlocker();

      final canvas = _RecordingCanvas();
      node.render(canvas);

      final whiteOutline = canvas.operations.where(
        (op) => op.method == 'drawRRect' && (op.colorArgb & 0x00FFFFFF) == 0x00FFFFFF,
      );
      expect(whiteOutline.isNotEmpty, isTrue,
          reason: 'Blocker flash must draw high-contrast outline under colorblindPalette');
    });

    testWidgets('Ray preview draws pips and blocker X under colorblindPalette', (tester) async {
      final game = _createGame(colorblind: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final source = NodeData(id: 4, x: 1, y: 1, dir: Direction.right);
      const trace = RayTraceResult(
        endX: 3,
        endY: 1,
        blockerNodeId: 5,
      );

      final ray = RayPreviewComponent(
        source: source,
        trace: trace,
        cellSize: 40,
        gridWidth: 6,
        gridHeight: 6,
      );
      await game.world.add(ray);
      await tester.pump();

      final canvas = _RecordingCanvas();
      ray.render(canvas);

      final pips = canvas.operations.where(
        (op) => op.method == 'drawCircle' && (op.colorArgb & 0x00FFFFFF) == 0x00FFFFFF,
      );
      expect(pips.isNotEmpty, isTrue, reason: 'Dotted ray must draw white pips');

      final xLines = canvas.operations.where(
        (op) => op.method == 'drawLine' && (op.colorArgb & 0x00FFFFFF) == 0x00FFFFFF,
      );
      expect(xLines.length >= 2, isTrue, reason: 'Blocker cell must draw cross X lines');
    });
  });

  group('W2.8 Accessibility: ambientMotion gates all ambient animation', () {
    testWidgets('AmbientBackgroundComponent suppresses ripples and glow when ambientMotion is false', (tester) async {
      final game = _createGame(ambient: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final ambient = AmbientBackgroundComponent(
        theme: WorldTheme.fromAccent(AppColors.accentEasy),
      );
      await game.world.add(ambient);
      await tester.pump();

      ambient.setStreak(10);
      ambient.pulseAt(Vector2(50, 50), radius: 64);
      ambient.update(0.1);

      final canvas = _RecordingCanvas();
      ambient.render(canvas);

      final edgeGlow = canvas.operations.where((op) => op.method == 'drawRect');
      expect(edgeGlow.isEmpty, isTrue,
          reason: 'Streak edge glow and scanlines must be suppressed when ambientMotion is false');
    });
  });

  group('W2.8 Accessibility: reducedMotion gates high-motion effects', () {
    testWidgets('Jam shake does NOT displace position when reducedMotion is true', (tester) async {
      final game = _createGame(reduced: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final node = NodeComponent(
        data: NodeData(id: 6, x: 2, y: 2, dir: Direction.right),
        cellSize: 40,
      );
      await game.world.add(node);
      await tester.pump();
      final origPos = Vector2.copy(node.position);

      node.isJamming = true;
      expect(node.isJamming, isTrue);

      node.update(0.05);
      expect(node.position.x, closeTo(origPos.x, 0.001),
          reason: 'Node must not shake laterally under reducedMotion');
      expect(node.position.y, closeTo(origPos.y, 0.001));
    });

    testWidgets('Jam shake DOES displace position when reducedMotion is false', (tester) async {
      final game = _createGame(reduced: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final node = NodeComponent(
        data: NodeData(id: 7, x: 2, y: 2, dir: Direction.right),
        cellSize: 40,
      );
      await game.world.add(node);
      await tester.pump();
      final origPos = Vector2.copy(node.position);

      node.isJamming = true;
      node.update(0.05);
      expect(node.position.x, isNot(closeTo(origPos.x, 0.0001)),
          reason: 'Node normally oscillates under jam shake');
    });

    testWidgets('RelaySweepComponent omits moving bar when reducedMotion is true', (tester) async {
      final game = _createGame(reduced: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final sweep = RelaySweepComponent(
        rowY: 2,
        gridWidth: 6,
        cellSize: 40,
        color: const Color(0xFF00FF87),
      );
      await game.world.add(sweep);
      await tester.pump();

      sweep.update(0.1);
      final canvas = _RecordingCanvas();
      sweep.render(canvas);

      final blurBars = canvas.operations.where((op) => op.method == 'drawRect');
      expect(blurBars.isEmpty, isTrue,
          reason: 'Moving sweep bar must be omitted under reducedMotion');
    });

    testWidgets('TutorialCoachMark bounce is zero and ring is steady under reducedMotion', (tester) async {
      final game = _createGame(reduced: true);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump();

      final coach = TutorialCoachMark(cellSize: 40);
      await game.world.add(coach);
      await tester.pump();
      coach.showAt(Vector2(100, 100));

      coach.update(0.25);
      final canvas = _RecordingCanvas();
      coach.render(canvas);

      final steadyRing = canvas.operations.where(
        (op) => op.method == 'drawCircle' && (op.radius - 26.0).abs() < 0.1,
      );
      expect(steadyRing.isNotEmpty, isTrue,
          reason: 'Ring must stay at a steady radius (40 * 0.65 = 26) under reducedMotion');
    });
  });
}
