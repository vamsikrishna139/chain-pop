import 'dart:math' as math;
import '../level.dart';
import '../level_solver.dart';
import '../grid_cell_key.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';

enum VisualCompositionRejectReason {
  aspect,
  occupancy,
  components,
  singleton,
  blobVsGrid,
}

class VisualCompositionResult {
  final bool passes;
  final VisualCompositionRejectReason? reason;

  const VisualCompositionResult.pass()
      : passes = true,
        reason = null;

  const VisualCompositionResult.reject(VisualCompositionRejectReason this.reason)
      : passes = false;
}

/// Evaluates a layout for visually pleasing composition.
VisualCompositionResult evaluateVisualComposition(
  LevelData level,
  DifficultyTier tier,
) {
  // Easy only — do not over-constrain small boards
  if (tier == DifficultyTier.easy) {
    return const VisualCompositionResult.pass();
  }

  if (level.nodes.isEmpty) {
    return const VisualCompositionResult.pass();
  }

  // 1. Trace occupied bounds
  var minX = level.nodes.first.x;
  var maxX = level.nodes.first.x;
  var minY = level.nodes.first.y;
  var maxY = level.nodes.first.y;

  for (final node in level.nodes) {
    if (node.x < minX) minX = node.x;
    if (node.x > maxX) maxX = node.x;
    if (node.y < minY) minY = node.y;
    if (node.y > maxY) maxY = node.y;
  }

  final bboxWidth = maxX - minX + 1;
  final bboxHeight = maxY - minY + 1;

  // 2. Aspect Ratio: 0.55 .. 1.75 on node bbox
  // Check logic: skip if logical aspect is outside 0.7..1.4 to avoid penalizing intentional corridors
  final logicalAspect = level.gridWidth / level.gridHeight;
  final gridArea = level.gridWidth * level.gridHeight;
  var skipAspectCheck = false;
  var skipBlobVsGridCheck = false;
  if (level.playCells != null && level.playCells!.isNotEmpty) {
    var maskMinX = 999;
    var maskMaxX = -999;
    var maskMinY = 999;
    var maskMaxY = -999;
    for (final s in level.playCells!) {
      final comma = s.indexOf(',');
      if (comma >= 0) {
        final x = int.parse(s.substring(0, comma));
        final y = int.parse(s.substring(comma + 1));
        if (x < maskMinX) maskMinX = x;
        if (x > maskMaxX) maskMaxX = x;
        if (y < maskMinY) maskMinY = y;
        if (y > maskMaxY) maskMaxY = y;
      }
    }
    final maskBboxWidth = maskMaxX - maskMinX + 1;
    final maskBboxHeight = maskMaxY - maskMinY + 1;
    if (maskBboxHeight > 0) {
      final maskAspect = maskBboxWidth / maskBboxHeight;
      if (maskAspect < 0.55 || maskAspect > 1.75) {
        skipAspectCheck = true;
      }
    }
    final maskBboxArea = maskBboxWidth * maskBboxHeight;
    if (gridArea > 0 && maskBboxArea / gridArea < 0.50) {
      skipBlobVsGridCheck = true;
    }
  }
  if (!skipAspectCheck && logicalAspect >= 0.7 && logicalAspect <= 1.4) {
    final bboxAspect = bboxWidth / bboxHeight;
    if (bboxAspect < 0.55 || bboxAspect > 1.75) {
      return const VisualCompositionResult.reject(VisualCompositionRejectReason.aspect);
    }
  }

  // 3. Blob vs Grid: bboxArea / gridArea >= 0.50
  final bboxArea = bboxWidth * bboxHeight;
  if (!skipBlobVsGridCheck && gridArea > 0) {
    final blobVsGrid = bboxArea / gridArea;
    if (blobVsGrid < 0.50) {
      return const VisualCompositionResult.reject(VisualCompositionRejectReason.blobVsGrid);
    }
  }

  // 4. Bbox Occupancy: node count / bbox area >= 0.35 (relax to 0.22 if nodes < 15 to allow sparse configurations without skewing archetypes)
  if (bboxArea > 0) {
    final occupancy = level.nodes.length / bboxArea;
    final minOccupancy = level.nodes.length < 15 ? 0.22 : 0.35;
    if (occupancy < minOccupancy) {
      return const VisualCompositionResult.reject(VisualCompositionRejectReason.occupancy);
    }
  }

  // Calculate connected components of the mask to dynamically scale constraints
  var maskComponents = 1;
  if (level.playCells != null && level.playCells!.isNotEmpty) {
    final maskKeys = <int>{};
    for (final s in level.playCells!) {
      final comma = s.indexOf(',');
      if (comma >= 0) {
        final x = int.parse(s.substring(0, comma));
        final y = int.parse(s.substring(comma + 1));
        maskKeys.add(gridCellKey(x, y));
      }
    }
    final maskVisited = <int>{};
    var maskCompCount = 0;
    for (final key in maskKeys) {
      if (!maskVisited.contains(key)) {
        maskCompCount++;
        final queue = [key];
        maskVisited.add(key);
        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          final cx = curr & 0xffff;
          final cy = (curr >> 16) & 0xffff;
          final neighbors = [
            gridCellKey(cx - 1, cy),
            gridCellKey(cx + 1, cy),
            gridCellKey(cx, cy - 1),
            gridCellKey(cx, cy + 1),
          ];
          for (final nb in neighbors) {
            if (maskKeys.contains(nb) && !maskVisited.contains(nb)) {
              maskVisited.add(nb);
              queue.add(nb);
            }
          }
        }
      }
    }
    if (maskCompCount > 0) {
      maskComponents = maskCompCount;
    }
  }

  // 5. Singletons: > allowed singletons -> reject (scaled to match mask components)
  // An isolated node has no neighbors in 4-connected directions.
  final keys = level.nodes.map((n) => gridCellKey(n.x, n.y)).toSet();
  var singletonCount = 0;
  final allowedSingletons = math.max(2, maskComponents);
  for (final node in level.nodes) {
    final neighbors = [
      gridCellKey(node.x - 1, node.y),
      gridCellKey(node.x + 1, node.y),
      gridCellKey(node.x, node.y - 1),
      gridCellKey(node.x, node.y + 1),
    ];
    var hasNeighbor = false;
    for (final nbKey in neighbors) {
      if (keys.contains(nbKey)) {
        hasNeighbor = true;
        break;
      }
    }
    if (!hasNeighbor) {
      singletonCount++;
      if (singletonCount > allowedSingletons) {
        return const VisualCompositionResult.reject(VisualCompositionRejectReason.singleton);
      }
    }
  }

  // 6. 4-connected components count <= allowed components (scaled to match mask components)
  final visited = <int>{};
  var componentCount = 0;
  final allowedComponents = math.max(2, maskComponents);

  for (final node in level.nodes) {
    final key = gridCellKey(node.x, node.y);
    if (!visited.contains(key)) {
      componentCount++;
      if (componentCount > allowedComponents) {
        return const VisualCompositionResult.reject(VisualCompositionRejectReason.components);
      }
      // BFS to find connected components
      final queue = [node];
      visited.add(key);
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        // Neighbors (4-connected)
        final neighbors = [
          (current.x - 1, current.y),
          (current.x + 1, current.y),
          (current.x, current.y - 1),
          (current.x, current.y + 1),
        ];
        for (final nb in neighbors) {
          final nbKey = gridCellKey(nb.$1, nb.$2);
          if (keys.contains(nbKey) && !visited.contains(nbKey)) {
            visited.add(nbKey);
            final nbNode = level.nodes.firstWhere((n) => n.x == nb.$1 && n.y == nb.$2);
            queue.add(nbNode);
          }
        }
      }
    }
  }

  return const VisualCompositionResult.pass();
}
