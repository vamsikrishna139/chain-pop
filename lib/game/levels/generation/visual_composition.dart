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

/// T2.4c — the rules that still **reject** a candidate outright.
///
/// Everything not listed here became a *ranking* term: the rule is still
/// evaluated and still scored, but violating it costs the candidate rank
/// instead of its existence.
///
/// `aspect` is hard for the reason T2.4b gave: it is the lowest-volume rule in
/// both modes (Medium 38, Hard 88) and its violation is genuinely broken
/// framing rather than a taste call, so keeping it costs almost no variety.
///
/// **`components` is hard because the measurement said so, and the plan said
/// so first.** T2.4c shipped with all four soft rules soft, and the p10 floor
/// T2.4b exists to defend went straight through the gate: Medium 0.6259 ->
/// 0.4625, Hard 0.6595 -> 0.5844 on the seed-7 sample. The diagnosis was
/// unambiguous — `components` p10 read **0.00** in both modes, i.e. a
/// meaningful share of shipped boards were scattered into four-plus pieces —
/// and the risk table in `IMPLEMENTATION_PLAN_V2.md` §"Checks and balances"
/// had already named the remedy before anyone ran it: *"Re-reject `components`
/// only; keep others soft."* Followed exactly, rather than reinvented after
/// seeing the numbers.
///
/// This costs the largest single share of Hard's rejections (T2.4b: 1,602 of
/// 2,657) and it is still the right trade: T2.1 and T2.3 deliver the variety
/// targets on their own (Hard topology 22 -> 48), so `components` was buying
/// scatter rather than variety.
const Set<VisualCompositionRejectReason> kHardCompositionRules = {
  VisualCompositionRejectReason.aspect,
  VisualCompositionRejectReason.components,
};

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
  /// Whether the candidate is **admitted**. After T2.4c this is "no rule in
  /// [kHardCompositionRules] failed", not "no rule failed at all" — a board
  /// can have `passes == true` and a non-null [reason].
  final bool passes;

  /// The first rule that failed, in the fixed priority order
  /// aspect → blobVsGrid → occupancy → singleton → components, whether that
  /// rule is hard or soft. `null` when the board satisfies all five.
  ///
  /// Reporting soft failures here on purpose: it is what keeps the per-rule
  /// volumes in `docs/playtests/composition_calibration.md` comparable across
  /// T2.4c. If soft failures went unnamed, the reject-reason table would read
  /// as if `components` had been fixed when it had only stopped being fatal.
  final VisualCompositionRejectReason? reason;

  /// T2.4a — computed for every board. T2.4c is the first stage that lets it
  /// change a decision: it is a ranking term in the K-loop's candidate
  /// comparator, never an admission test.
  final VisualCompositionDetail detail;

  /// False when the rules were short-circuited (Easy tier, or an empty board),
  /// so [detail] is filler rather than a measurement. Calibration must exclude
  /// these rows instead of reading them as perfect scores.
  final bool evaluated;

  double get score => detail.score;

  /// A rule failed, but not a hard one: the board is admitted and carries the
  /// score penalty into ranking.
  bool get softFailed => passes && reason != null;

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

  /// T2.4c — a soft-rule violation. Admitted, named, and scored.
  const VisualCompositionResult.softPass(
    VisualCompositionRejectReason this.reason, {
    required this.detail,
    this.evaluated = true,
  }) : passes = true;
}

/// S1: the largest empty axis-aligned rectangle of in-frame cells outside the
/// play mask may cover at most this share of the frame.
const double kGenV2MaxDarkRectFraction = 0.25;

/// Area of the largest axis-aligned rectangle of non-play cells, as a share
/// of the frame. Brute force; frames are at most 10x10.
double genV2LargestDarkRectFraction(LevelData level) {
  if (level.playCells == null || level.playCells!.isEmpty) return 0;
  final play = <int>{};
  for (final s in level.playCells!) {
    final c = s.indexOf(',');
    if (c < 0) continue;
    play.add(gridCellKey(
        int.parse(s.substring(0, c)), int.parse(s.substring(c + 1))));
  }
  return genV2DarkRectFractionOfMask(play, level.gridWidth, level.gridHeight);
}

/// Same measure on a raw mask of [gridCellKey]s.
double genV2DarkRectFractionOfMask(Set<int> play, int w, int h) {
  final heights = List<int>.filled(w, 0);
  var best = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      heights[x] = play.contains(gridCellKey(x, y)) ? 0 : heights[x] + 1;
    }
    for (var x0 = 0; x0 < w; x0++) {
      var minH = 1 << 20;
      for (var x1 = x0; x1 < w; x1++) {
        minH = math.min(minH, heights[x1]);
        if (minH == 0) break;
        best = math.max(best, minH * (x1 - x0 + 1));
      }
    }
  }
  return best / (w * h);
}

/// S1 v2: the largest 4-connected region of in-frame non-play cells may cover
/// at most this share of the frame. Catches diagonal and L-shaped voids that
/// contain no large rectangle (a staircase leaves two big triangles).
const double kGenV2MaxVoidRegionFraction = 0.25;

/// Largest 4-connected region of non-play cells inside the frame, as a share
/// of the frame.
double genV2LargestVoidRegionFractionOfMask(Set<int> play, int w, int h) {
  final seen = <int>{};
  var best = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final k = gridCellKey(x, y);
      if (play.contains(k) || !seen.add(k)) continue;
      var size = 0;
      final stack = <(int, int)>[(x, y)];
      while (stack.isNotEmpty) {
        final (cx, cy) = stack.removeLast();
        size++;
        for (final (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final nk = gridCellKey(nx, ny);
          if (play.contains(nk) || !seen.add(nk)) continue;
          stack.add((nx, ny));
        }
      }
      best = math.max(best, size);
    }
  }
  return best / (w * h);
}

/// S1 combined emptiness score: <= 1.0 means the mask passes both the dark
/// rectangle and the void-region limits; lower is fuller.
double genV2MaskEmptinessScore(Set<int> play, int w, int h) => math.max(
    genV2DarkRectFractionOfMask(play, w, h) / kGenV2MaxDarkRectFraction,
    genV2LargestVoidRegionFractionOfMask(play, w, h) /
        kGenV2MaxVoidRegionFraction);

/// Same measure on a level's play cells.
double genV2LargestVoidRegionFraction(LevelData level) {
  if (level.playCells == null || level.playCells!.isEmpty) return 0;
  final play = <int>{};
  for (final s in level.playCells!) {
    final c = s.indexOf(',');
    if (c < 0) continue;
    play.add(gridCellKey(
        int.parse(s.substring(0, c)), int.parse(s.substring(c + 1))));
  }
  return genV2LargestVoidRegionFractionOfMask(
      play, level.gridWidth, level.gridHeight);
}

/// Evaluates a layout for visually pleasing composition.
VisualCompositionResult evaluateVisualComposition(
  LevelData level,
  DifficultyTier tier, {
  bool genV2Scaled = false,
}) {
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
  final aspectFails = aspectApplies && (bboxAspect < 0.55 || bboxAspect > 1.75);
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
  final blobVsGridScore =
      (skipBlobVsGridCheck || gridArea <= 0) ? 1.0 : blobVsGrid.clamp(0.0, 1.0);

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
  // T2.4c: `max(2, maskComponents)` -> `maskComponents + 2`. On a one-piece
  // mask both read 2, so simple boards are unaffected; the difference is that a
  // deliberately multi-part silhouette (archipelago, scattered holes) now gets
  // an allowance that scales *with* its own part count instead of being held to
  // the same absolute 2 a solid rectangle is. T2.2 makes those silhouettes
  // actually reachable, so this stops the new variety from arriving pre-penalised.
  final allowedSingletons = maskComponents + 2;
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
  // T2.4c, same reasoning as [allowedSingletons] above.
  //
  // Gen V2: the allowance scales by `nodes / 25` (V1's calibration size), the
  // same rule `DifficultyProfile.scaledForGenV2` applies to absolute counts.
  // A 32-node board on a 7x9 frame at V1's visual density has proportionally
  // more clusters; without this 69% of V2 candidates failed (V1: 46%).
  final allowedComponents = genV2Scaled
      ? ((maskComponents + 2) *
              math.max(1.0, level.nodes.length / 25))
          .round()
      : maskComponents + 2;

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
            final nbNode =
                level.nodes.firstWhere((n) => n.x == nb.$1 && n.y == nb.$2);
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

  // Priority order preserved exactly as the original early returns had it, so
  // the per-rule volume table stays a like-for-like series across T2.4c.
  const order = <(VisualCompositionRejectReason, int)>[
    (VisualCompositionRejectReason.aspect, 0),
    (VisualCompositionRejectReason.blobVsGrid, 1),
    (VisualCompositionRejectReason.occupancy, 2),
    (VisualCompositionRejectReason.singleton, 3),
    (VisualCompositionRejectReason.components, 4),
  ];
  final fails = [
    aspectFails,
    blobVsGridFails,
    occupancyFails,
    singletonFails,
    componentsFails,
  ];

  // **Hard rules are resolved first, across the whole set, before any soft
  // rule is allowed to name the board.**
  //
  // Scanning the single priority order and stopping at the first failure —
  // which is what the pre-T2.4c early returns did, and what the first cut of
  // T2.4c kept doing — is correct only while every rule is hard. Once some are
  // soft it silently breaks: a board failing both `singleton` (soft, 4th) and
  // `components` (hard, 5th) is named `singleton`, admitted, and the hard rule
  // never fires. Measured, that is not hypothetical — re-rejecting
  // `components` moved Hard's shipped `singleton` violations 5 -> 36 while
  // shipped `components` violations stayed at 0 and the `components` p10 stayed
  // pinned at 0.00, i.e. the scattered boards were still shipping, now wearing
  // a different label. Two passes, not one.
  for (final (rule, i) in order) {
    if (fails[i] && kHardCompositionRules.contains(rule)) {
      return VisualCompositionResult.reject(rule, detail: detail);
    }
  }
  for (final (rule, i) in order) {
    if (fails[i]) {
      return VisualCompositionResult.softPass(rule, detail: detail);
    }
  }
  return VisualCompositionResult.pass(detail: detail, evaluated: true);
}

/// S1 carve-from-full: start from the whole frame and remove 1-4 rectangular
/// "bites" from the boundary, keeping the shape 4-connected, at least
/// [minCells] big and under the dark-rectangle limit. Mirrored left-right on
/// a coin flip. Deterministic for a given [random]. Null when no valid carve
/// is found in a handful of tries.
Set<int>? genV2CarveMask({
  required int gridWidth,
  required int gridHeight,
  required int minCells,
  required int maxCells,
  required math.Random random,
}) {
  final w = gridWidth, h = gridHeight;
  for (var attempt = 0; attempt < 8; attempt++) {
    final cells = <int>{
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++) gridCellKey(x, y)
    };
    final minBites = 1 + random.nextInt(4);
    for (var b = 0; b < 12; b++) {
      // Keep biting until the shape is small enough for the node target
      // (a near-full frame leaves half the tiles empty).
      if (b >= minBites && cells.length <= maxCells) break;
      final bw = 1 + random.nextInt(3);
      final bh = 1 + random.nextInt(4);
      // Anchor on the boundary: pick a side, then a position along it.
      final side = random.nextInt(4);
      final x0 = side == 0
          ? 0
          : side == 1
              ? w - bw
              : random.nextInt(w - bw + 1);
      final y0 = side == 2
          ? 0
          : side == 3
              ? h - bh
              : random.nextInt(h - bh + 1);
      for (var y = y0; y < y0 + bh; y++) {
        for (var x = x0; x < x0 + bw; x++) {
          cells.remove(gridCellKey(x, y));
        }
      }
    }
    var out = cells;
    if (random.nextDouble() < 0.4) {
      out = {
        for (final k in cells) gridCellKey(w - 1 - (k & 0xffff), (k >> 16) & 0xffff)
      };
    }
    if (out.length < minCells || out.length > maxCells) continue;
    if (!_isFourConnected(out)) continue;
    if (genV2DarkRectFractionOfMask(out, w, h) > kGenV2MaxDarkRectFraction) {
      continue;
    }
    return out;
  }
  return null;
}

bool _isFourConnected(Set<int> cells) {
  if (cells.isEmpty) return false;
  final seen = <int>{cells.first};
  final stack = <int>[cells.first];
  while (stack.isNotEmpty) {
    final k = stack.removeLast();
    final x = k & 0xffff, y = (k >> 16) & 0xffff;
    for (final n in [
      gridCellKey(x + 1, y),
      gridCellKey(x - 1, y),
      gridCellKey(x, y + 1),
      gridCellKey(x, y - 1),
    ]) {
      if (x - 1 < 0 && n == gridCellKey(x - 1, y)) continue;
      if (y - 1 < 0 && n == gridCellKey(x, y - 1)) continue;
      if (cells.contains(n) && seen.add(n)) stack.add(n);
    }
  }
  return seen.length == cells.length;
}
