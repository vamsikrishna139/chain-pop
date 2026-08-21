import 'dart:math' as math;
import '../level.dart';
import '../grid_cell_key.dart';
import 'difficulty_profile.dart';


enum VisualCompositionRejectReason {
  aspect,
  occupancy,
  components,
  singleton,
  blobVsGrid,
}

/// Per-rule composition detail, each normalised to 0..1 where **higher is
/// better**.
///
/// T2.4a records these; nothing acts on them. T2.4b calibrates a threshold
/// from their distribution, and only T2.4c turns the soft rules into ranking
/// terms. Splitting it that way is deliberate: converting the measurement and
/// the decision in one commit leaves no baseline to judge the new gate
/// against (plan §T2.4, correction 5).
class VisualCompositionDetail {
  const VisualCompositionDetail({
    required this.aspect,
    required this.blobVsGrid,
    required this.occupancy,
    required this.singleton,
    required this.components,
  });

  /// All-ones: what a short-circuited board reports. Paired with
  /// `evaluated: false` so calibration can drop these rows.
  static const unevaluated = VisualCompositionDetail(
    aspect: 1,
    blobVsGrid: 1,
    occupancy: 1,
    singleton: 1,
    components: 1,
  );

  /// Node-bbox aspect, 1.0 at square, 0.0 at the 0.55/1.75 reject edges.
  final double aspect;

  /// Occupied bbox area as a share of grid area (the rule rejects < 0.50).
  final double blobVsGrid;

  /// Nodes per bbox cell (the rule rejects < 0.35, or < 0.22 under 15 nodes).
  final double occupancy;

  /// 1.0 with no isolated nodes, falling as singletons approach the allowance.
  final double singleton;

  /// 1.0 when the board is one connected piece, falling toward the allowance.
  final double components;

  /// Provisional composite: the unweighted mean of the five.
  ///
  /// Unweighted **on purpose** — weighting the terms before seeing their
  /// distributions would bake in exactly the assumption T2.4b exists to test.
  double get score =>
      (aspect + blobVsGrid + occupancy + singleton + components) / 5.0;
}

class VisualCompositionResult {
  final bool passes;
  final VisualCompositionRejectReason? reason;

  /// T2.4a — computed for every board, **acted on by nothing**. The accept /
  /// reject decision is still exactly the five hard rules below.
  final VisualCompositionDetail detail;

  /// False when the rules were short-circuited (Easy tier, or an empty board),
  /// so [detail] is filler rather than a measurement. Calibration must exclude
  /// these rows instead of reading them as perfect scores.
  final bool evaluated;

  double get score => detail.score;

  const VisualCompositionResult.pass({
    this.detail = VisualCompositionDetail.unevaluated,
    this.evaluated = false,
  })  : passes = true,
        reason = null;

  const VisualCompositionResult.reject(
    VisualCompositionRejectReason this.reason, {
    this.detail = VisualCompositionDetail.unevaluated,
    this.evaluated = true,
  }) : passes = false;
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
  // T2.4a restructure: every rule is now evaluated and scored, and the reject
  // reason is resolved at the end in the SAME priority order the early returns
  // used (aspect → blobVsGrid → occupancy → singleton → components). Behaviour
  // is unchanged; only the bookkeeping is new.
  final bboxAspect = bboxHeight == 0 ? 1.0 : bboxWidth / bboxHeight;
  final aspectApplies =
      !skipAspectCheck && logicalAspect >= 0.7 && logicalAspect <= 1.4;
  final aspectFails =
      aspectApplies && (bboxAspect < 0.55 || bboxAspect > 1.75);
  // 1.0 at square, 0.0 at whichever reject edge the board is heading for.
  //
  // An exempted board scores 1.0 rather than being measured. `skipAspectCheck`
  // and the 0.7..1.4 logical-aspect window exist because a deliberate corridor
  // is not a badly-framed square — scoring it against a squareness ideal the
  // rule explicitly declined to apply would penalise intent. Measured
  // 2026-08-21: without this, p10 AND p25 of shipped Medium aspect were both
  // 0.0000, i.e. a quarter of shipped boards looked maximally broken on a rule
  // that never ran for them.
  final aspectScore = !aspectApplies
      ? 1.0
      : bboxAspect >= 1.0
          ? (1.0 - (bboxAspect - 1.0) / (1.75 - 1.0)).clamp(0.0, 1.0)
          : (1.0 - (1.0 - bboxAspect) / (1.0 - 0.55)).clamp(0.0, 1.0);

  // 3. Blob vs Grid: bboxArea / gridArea >= 0.50
  final bboxArea = bboxWidth * bboxHeight;
  final blobVsGrid = gridArea > 0 ? bboxArea / gridArea : 1.0;
  final blobVsGridFails =
      !skipBlobVsGridCheck && gridArea > 0 && blobVsGrid < 0.50;
  // Same exemption logic: `skipBlobVsGridCheck` marks masks whose bbox is
  // *meant* to be a small share of the grid, so they are not scored on it.
  final blobVsGridScore = (skipBlobVsGridCheck || gridArea <= 0)
      ? 1.0
      : blobVsGrid.clamp(0.0, 1.0);

  // 4. Bbox Occupancy: node count / bbox area >= 0.35 (relax to 0.22 if nodes < 15 to allow sparse configurations without skewing archetypes)
  final occupancy = bboxArea > 0 ? level.nodes.length / bboxArea : 1.0;
  final minOccupancy = level.nodes.length < 15 ? 0.22 : 0.35;
  final occupancyFails = bboxArea > 0 && occupancy < minOccupancy;
  final occupancyScore = occupancy.clamp(0.0, 1.0);

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
    }
  }
  // Counting all singletons instead of bailing at the first excess yields the
  // same predicate (`> allowedSingletons`) and costs O(n) on n <= 42.
  final singletonFails = singletonCount > allowedSingletons;
  final singletonScore =
      (1.0 - singletonCount / (allowedSingletons + 1)).clamp(0.0, 1.0);

  // 6. 4-connected components count <= allowed components (scaled to match mask components)
  final visited = <int>{};
  var componentCount = 0;
  final allowedComponents = math.max(2, maskComponents);

  for (final node in level.nodes) {
    final key = gridCellKey(node.x, node.y);
    if (!visited.contains(key)) {
      componentCount++;
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

  final componentsFails = componentCount > allowedComponents;
  final componentsScore =
      (1.0 - (componentCount - 1) / math.max(1, allowedComponents))
          .clamp(0.0, 1.0);

  final detail = VisualCompositionDetail(
    aspect: aspectScore,
    blobVsGrid: blobVsGridScore,
    occupancy: occupancyScore,
    singleton: singletonScore,
    components: componentsScore,
  );

  // Priority order preserved exactly as the original early returns had it.
  // T2.4c is what changes which of these still reject; T2.4a changes nothing.
  if (aspectFails) {
    return VisualCompositionResult.reject(
        VisualCompositionRejectReason.aspect, detail: detail);
  }
  if (blobVsGridFails) {
    return VisualCompositionResult.reject(
        VisualCompositionRejectReason.blobVsGrid, detail: detail);
  }
  if (occupancyFails) {
    return VisualCompositionResult.reject(
        VisualCompositionRejectReason.occupancy, detail: detail);
  }
  if (singletonFails) {
    return VisualCompositionResult.reject(
        VisualCompositionRejectReason.singleton, detail: detail);
  }
  if (componentsFails) {
    return VisualCompositionResult.reject(
        VisualCompositionRejectReason.components, detail: detail);
  }
  return VisualCompositionResult.pass(detail: detail, evaluated: true);
}
