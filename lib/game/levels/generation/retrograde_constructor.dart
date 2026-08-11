import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'candidate_scorer.dart';
import 'dependency_graph.dart';
import 'frontier_set.dart';
import 'motifs.dart';
import 'removal_order.dart';
export 'retrograde_placement.dart';
import 'retrograde_placement.dart';
import 'sightline_table.dart';
import 'difficulty_profile.dart';
import 'metrics.dart';

/// Constructs a fully solvable level from the **empty** board outward, in
/// reverse extraction order (last-removed first).
///
/// At each step the constructor:
/// 1. Enumerates candidate (cell, direction) pairs over the [FrontierSet].
/// 2. Asks the [CandidateScorer] to pick one via softmax sampling.
/// 3. Commits the chosen placement; the cell becomes a blocker for future
///    placements and its neighbours join the frontier.
///
/// **Solvability invariant** — at construction time the chosen direction's
/// ray is clear. Because the eventual extraction order removes nodes in the
/// reverse of the placement order, removing a node only *frees* rays
/// (monotonicity), so the ray is still clear at extraction time.
///
/// On a dead-end (zero candidates), the constructor uses a bounded
/// **Rollback Stack**: it pops [rollbackPopCount] recent placements,
/// blacklists the offending cell for the current step, and retries. After
/// [maxRollbackDepth] consecutive rollbacks the constructor gives up by
/// returning null; the caller (Director in Phase 3 onward, fallback path in
/// Phase 1) is responsible for renegotiating the silhouette or node count.
class RetrogradeConstructor {
  /// Fraction of [silhouette] cells that must be filled (bulk phase) before
  /// generic motif reservations are injected — bulk treats those keys as
  /// ray obstacles so the greedy ray semantics never "see through" holes
  /// reserved for motifs.
  static const double kDefaultMotifOccupancyThreshold = 0.55;

  /// Lock-cluster motifs inject earlier (40%) so they become midgame crunch.
  static const double kLockClusterMotifOccupancyThreshold = 0.40;

  /// Width of the bounding grid.
  final int gridWidth;

  /// Height of the bounding grid.
  final int gridHeight;

  /// Silhouette mask (set of cell keys) where nodes may be placed.
  final Set<int> silhouette;

  /// Total number of nodes to place.
  final int targetNodeCount;

  /// Selector used to pick among enumerated candidates.
  final CandidateScorer scorer;

  /// Precomputed per-cell ray table for this grid.
  final SightlineTable sightlines;

  /// RNG injected for full determinism (per §10 of the plan).
  final Random random;

  /// 4-connected by default; archetypes that prefer organic, dense fills can
  /// opt in to 8-connected frontier expansion.
  final bool eightConnected;

  /// Maximum consecutive rollback steps before giving up (§4.2).
  final int maxRollbackDepth;

  /// Hard ceiling on total rollback events per construction attempt. Prevents
  /// pathological "rollback → 1 successful placement → rollback again" cycles
  /// that would otherwise keep the consecutive counter pegged at low values
  /// forever. Defaults to 4× [maxRollbackDepth].
  final int maxTotalRollbacks;

  /// How many recent placements to undo when a step dead-ends.
  final int rollbackPopCount;

  /// Pre-committed Motif Transaction placements (§4.6). Injected after bulk
  /// occupancy thresholds — lock clusters at 40%, other motifs at 55%.
  final List<MotifPlacement> motifPlacements;

  /// The difficulty tier for this generation, used for opening compression.
  final DifficultyTier? tier;

  static const Map<DifficultyTier, int> _maxOpeningByTier = {
    DifficultyTier.easy: 10,
    DifficultyTier.medium: 8,
    // Matches [DifficultyProfile.hardExpertOpeningBand] — see OPENING_BAND_DECISION.md.
    DifficultyTier.hard: 11,
    DifficultyTier.expert: 11,
  };

  static const Map<DifficultyTier, int> _minOpeningByTier = {
    DifficultyTier.easy: 5,
    DifficultyTier.medium: 4,
    DifficultyTier.hard: 3,
    DifficultyTier.expert: 3,
  };

  /// Debug telemetry — solvability retries after reassignment pass.
  int constructionSolvabilityRetries = 0;

  /// Crunch-zone direction flips applied by [_applyPhaseAwareDirectionReassignment].
  int reassignmentCrunchFlips = 0;

  /// Reassignment flip opportunities offered in the crunch window.
  int reassignmentFlipsOffered = 0;

  /// Index into the reassignment-probability retry ladder (0=0.72, 1=0.45, 2=0.25)
  /// for the last successful [construct] call; null when [construct] failed.
  int? winningBlockingRetryIndex;

  RetrogradeConstructor({
    required this.gridWidth,
    required this.gridHeight,
    required this.silhouette,
    required this.targetNodeCount,
    required this.scorer,
    required this.sightlines,
    required this.random,
    this.eightConnected = false,
    this.maxRollbackDepth = 5,
    int? maxTotalRollbacks,
    this.rollbackPopCount = 3,
    List<MotifPlacement> motifPlacements = const <MotifPlacement>[],
    List<MotifReservation> reservations = const <MotifReservation>[],
    this.tier,
  })  : motifPlacements = motifPlacements.isNotEmpty
            ? motifPlacements
            : _placementsFromReservations(reservations),
        maxTotalRollbacks = maxTotalRollbacks ?? (maxRollbackDepth * 4);

  static List<MotifPlacement> _placementsFromReservations(
    List<MotifReservation> reservations,
  ) {
    if (reservations.isEmpty) return const [];
    return [
      MotifPlacement(
        id: MotifId.none,
        reservations: reservations,
        anchor: reservations.first.position,
      ),
    ];
  }

  List<MotifReservation> get reservations => [
        for (final m in motifPlacements) ...m.reservations,
      ];

  /// Runs the constructor.
  ///
  /// Returns the placements in **removal order** — index 0 is the first node
  /// the player taps, index N-1 the last. Returns null on irrecoverable
  /// failure (silhouette starvation or rollback depth exceeded).
  List<RetrogradePlacement>? construct() {
    if (targetNodeCount <= 0) return <RetrogradePlacement>[];
    if (silhouette.length < targetNodeCount) return null;
    if (reservations.length > targetNodeCount) return null;

    const reassignmentProbs = <double>[
      kCrunchBlockingProbability,
      0.45,
      0.25,
    ];
    winningBlockingRetryIndex = null;
    reassignmentCrunchFlips = 0;
    reassignmentFlipsOffered = 0;

    int? liberationNodeId;
    List<RetrogradePlacement>? baseline;
    for (var attempt = 0; attempt < 8; attempt++) {
      scorer.crunchBlockingProbability = 0;
      scorer.blockingDirCandidatesOffered = 0;
      scorer.blockingDirCandidatesPicked = 0;
      scorer.crunchZoneBlockingPicked = 0;
      scorer.releaseZoneFallbackPicked = 0;

      Point<int>? liberationPos;
      for (final m in motifPlacements) {
        if (m.id == MotifId.cascadeHub) {
          liberationPos = m.anchor;
          break;
        }
      }

      final forward = motifPlacements.isEmpty
          ? _constructPlain(liberationPos: liberationPos)
          : _constructDeferredMotifs(liberationPos: liberationPos);
      if (forward == null) continue;

      final candidate = _finalizeRemovalOrder(forward);
      if (_validatesRemovalOrderIdSequence(candidate)) {
        baseline = candidate;
        final third = max(1, candidate.length ~/ 3);
        final lower = min(3, third);
        final targetRemovalIdx =
            (candidate.length * 0.30).round().clamp(lower, max(lower, third)).toInt();
        final startRemoval = max(0, targetRemovalIdx - 2);
        final endRemoval = min(candidate.length - 1, targetRemovalIdx + 2);
        if (startRemoval <= endRemoval) {
          var bestRemovalIdx = targetRemovalIdx;
          var bestDist = double.infinity;
          final cx = gridWidth / 2.0;
          final cy = gridHeight / 2.0;
          for (var i = startRemoval; i <= endRemoval; i++) {
            final p = candidate[i].position;
            final dist = (p.x - cx).abs() + (p.y - cy).abs();
            if (dist < bestDist) {
              bestDist = dist;
              bestRemovalIdx = i;
            }
          }
          liberationNodeId = bestRemovalIdx;
        }
        break;
      }
    }
    if (baseline == null) return null;

    // Phase 2: post-placement direction reassignment (crunch blocking toward lower IDs).
    for (var retry = 0; retry < reassignmentProbs.length; retry++) {
      final flipProb = reassignmentProbs[retry];
      final reassigned = _applyPhaseAwareDirectionReassignment(
        baseline,
        flipProbability: flipProb,
        liberationNodeId: liberationNodeId,
      );
      if (_validatesRemovalOrderIdSequence(reassigned)) {
        if (retry > 0) constructionSolvabilityRetries++;
        winningBlockingRetryIndex = retry;
        scorer.crunchZoneBlockingPicked = reassignmentCrunchFlips;
        
        var finalResult = reassigned;
        if (tier != null) {
          final maxOpening = _maxOpeningByTier[tier];
          final minOpening = _minOpeningByTier[tier];
          if (maxOpening != null && minOpening != null) {
            finalResult = _enforceOpeningTarget(
              finalResult,
              maxOpening: maxOpening,
              minOpening: minOpening,
            );
          }
        }
        return finalResult;
      }
      if (retry < reassignmentProbs.length - 1) {
        constructionSolvabilityRetries++;
      }
    }
    // Validated clear-ray baseline when no reassignment tier succeeds.
    winningBlockingRetryIndex = null;
    reassignmentCrunchFlips = 0;
    scorer.crunchZoneBlockingPicked = 0;
    var finalBaseline = baseline;
    if (tier != null) {
      final maxOpening = _maxOpeningByTier[tier];
      final minOpening = _minOpeningByTier[tier];
      if (maxOpening != null && minOpening != null) {
        finalBaseline = _enforceOpeningTarget(
          finalBaseline,
          maxOpening: maxOpening,
          minOpening: minOpening,
        );
      }
    }
    return finalBaseline;
  }

  List<RetrogradePlacement>? _constructPlain({Point<int>? liberationPos}) {
    final placed = <int>{};
    final placements = <RetrogradePlacement>[];
    final frontier = FrontierSet(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      silhouette: silhouette,
      eightConnected: eightConnected,
    );
    final blacklist = <int>{};
    var rollbackDepth = 0;
    var totalRollbacks = 0;

    while (placements.length < targetNodeCount) {
      final state = ConstructionState(
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        silhouette: silhouette,
        placed: placed,
        frontier: frontier,
        sightlines: sightlines,
        eightConnected: eightConnected,
        occupancyRatio: placements.length / targetNodeCount,
        liberationPosition: liberationPos,
      );

      final candidates =
          _enumerateCandidates(state, blacklist, const <int>{});
      if (candidates.isEmpty) {
        if (rollbackDepth >= maxRollbackDepth) return null;
        if (totalRollbacks >= maxTotalRollbacks) return null;
        if (placements.isEmpty) return null;
        rollbackDepth++;
        totalRollbacks++;
        final triggered = placements.last.position;
        blacklist.add(gridCellKey(triggered.x, triggered.y));
        final popCount = min(rollbackPopCount, placements.length);
        for (var i = 0; i < popCount; i++) {
          final pop = placements.removeLast();
          placed.remove(gridCellKey(pop.position.x, pop.position.y));
          frontier.removePlaced(gridCellKey(pop.position.x, pop.position.y));
        }
        continue;
      }

      final picked = scorer.pick(candidates, state, random);
      if (picked == null) return null;

      placed.add(picked.cellKey);
      frontier.addPlaced(picked.cellKey);
      placements.add(RetrogradePlacement(
        position: picked.cell,
        direction: picked.direction,
      ));

      blacklist.clear();
      rollbackDepth = 0;
    }

    return placements;
  }

  List<RetrogradePlacement>? _constructDeferredMotifs({Point<int>? liberationPos}) {
    final allReservations = reservations;
    final seenKeys = <int>{};
    for (final r in allReservations) {
      if (!silhouette.contains(r.cellKey)) return null;
      if (!seenKeys.add(r.cellKey)) return null;
    }

    var placed = <int>{};
    final placements = <RetrogradePlacement>[];
    final frontier = FrontierSet(
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      silhouette: silhouette,
      eightConnected: eightConnected,
    );
    final blacklist = <int>{};

    var lockClusterQueue = <MotifReservation>[];
    var genericQueue = <MotifReservation>[];
    var unplacedMotifKeys = <int>{};
    for (final m in motifPlacements) {
      final threshold = m.id == MotifId.lockCluster
          ? kLockClusterMotifOccupancyThreshold
          : kDefaultMotifOccupancyThreshold;
      final queue =
          threshold == kLockClusterMotifOccupancyThreshold
              ? lockClusterQueue
              : genericQueue;
      for (final r in m.reservations) {
        queue.add(r);
        unplacedMotifKeys.add(r.cellKey);
      }
    }
    lockClusterQueue = List<MotifReservation>.from(lockClusterQueue);
    genericQueue = List<MotifReservation>.from(genericQueue);

    var activePhase = false;
    var freezeBulkCount = 0;
    var rollbackFloor = 0;

    var rollbackDepth = 0;
    var totalRollbacks = 0;

    final motifReservationCount = allReservations.length;
    final bulkSlotsBeforeMotifs = targetNodeCount - motifReservationCount;

    double thresholdForQueue(List<MotifReservation> queue) {
      if (queue.isEmpty) return kDefaultMotifOccupancyThreshold;
      for (final m in motifPlacements) {
        if (m.reservations.any((r) => r.cellKey == queue.first.cellKey)) {
          return m.id == MotifId.lockCluster
              ? kLockClusterMotifOccupancyThreshold
              : kDefaultMotifOccupancyThreshold;
        }
      }
      return kDefaultMotifOccupancyThreshold;
    }

    bool bulkPrefixCompleteFor(List<MotifReservation> queue) {
      if (queue.isEmpty) return false;
      if (bulkSlotsBeforeMotifs <= 0) {
        return true;
      }
      final threshold = thresholdForQueue(queue);
      final occGate = (threshold * targetNodeCount).ceil();
      return placements.length >= occGate &&
          placements.length >= bulkSlotsBeforeMotifs;
    }

    void enterMotifPhase() {
      activePhase = true;
      freezeBulkCount = placements.length;
      rollbackFloor = freezeBulkCount;
      rollbackDepth = 0;
      blacklist.clear();
      lockClusterQueue = List<MotifReservation>.from(lockClusterQueue)
        ..shuffle(random);
      genericQueue = List<MotifReservation>.from(genericQueue)..shuffle(random);
    }

    bool tryPlaceNextFrom(List<MotifReservation> queue) {
      if (queue.isEmpty) return false;
      final r = queue.first;
      final key = r.cellKey;
      var dir = r.direction;
      if (!sightlines.hasClearRay(
        r.position.x,
        r.position.y,
        dir,
        placed,
      )) {
        Direction? fallback;
        for (final d in Direction.values) {
          if (sightlines.hasClearRay(
            r.position.x,
            r.position.y,
            d,
            placed,
          )) {
            fallback = d;
            break;
          }
        }
        if (fallback == null) return false;
        dir = fallback;
      }
      queue.removeAt(0);
      unplacedMotifKeys.remove(key);
      placed.add(key);
      frontier.addPlaced(key);
      placements.add(RetrogradePlacement(
        position: r.position,
        direction: dir,
      ));
      blacklist.clear();
      rollbackDepth = 0;
      return true;
    }

    void degradeMotifTransaction() {
      while (placements.length > freezeBulkCount) {
        final pop = placements.removeLast();
        final k = gridCellKey(pop.position.x, pop.position.y);
        placed.remove(k);
        frontier.removePlaced(k);
      }
      lockClusterQueue = [];
      genericQueue = [];
      unplacedMotifKeys.clear();
      activePhase = false;
      rollbackFloor = 0;
      blacklist.clear();
      rollbackDepth = 0;
    }

    List<MotifReservation> activeQueue() {
      if (lockClusterQueue.isNotEmpty &&
          bulkPrefixCompleteFor(lockClusterQueue)) {
        return lockClusterQueue;
      }
      if (genericQueue.isNotEmpty && bulkPrefixCompleteFor(genericQueue)) {
        return genericQueue;
      }
      return const [];
    }

    while (placements.length < targetNodeCount) {
      final queue = activeQueue();
      if (!activePhase && queue.isNotEmpty) {
        enterMotifPhase();
      }

      if (activePhase &&
          (lockClusterQueue.isNotEmpty || genericQueue.isNotEmpty)) {
        final targetQueue = lockClusterQueue.isNotEmpty &&
                bulkPrefixCompleteFor(lockClusterQueue)
            ? lockClusterQueue
            : (genericQueue.isNotEmpty &&
                    bulkPrefixCompleteFor(genericQueue)
                ? genericQueue
                : null);
        if (targetQueue != null && targetQueue.isNotEmpty) {
          var placedThisRound = false;
          for (var attempt = 0;
              attempt < targetQueue.length && !placedThisRound;
              attempt++) {
            if (tryPlaceNextFrom(targetQueue)) {
              placedThisRound = true;
              if (lockClusterQueue.isEmpty && genericQueue.isEmpty) {
                activePhase = false;
              }
              break;
            }
            if (targetQueue.length > 1) {
              final rotated = targetQueue.sublist(1)
                ..add(targetQueue.first);
              if (identical(targetQueue, lockClusterQueue)) {
                lockClusterQueue = rotated;
              } else {
                genericQueue = rotated;
              }
            }
          }
          if (placedThisRound) {
            continue;
          }
          degradeMotifTransaction();
          continue;
        }
      }

      final state = ConstructionState(
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        silhouette: silhouette,
        placed: placed,
        frontier: frontier,
        sightlines: sightlines,
        eightConnected: eightConnected,
        occupancyRatio: placements.length / targetNodeCount,
        liberationPosition: liberationPos,
      );

      final candidates =
          _enumerateCandidates(state, blacklist, unplacedMotifKeys);
      if (candidates.isEmpty) {
        final readyQueue = activeQueue();
        if (!activePhase && readyQueue.isNotEmpty) {
          enterMotifPhase();
          continue;
        }
        if (rollbackDepth >= maxRollbackDepth) return null;
        if (totalRollbacks >= maxTotalRollbacks) return null;
        if (placements.length <= rollbackFloor) {
          if (lockClusterQueue.isNotEmpty || genericQueue.isNotEmpty) {
            degradeMotifTransaction();
            continue;
          }
          return null;
        }
        rollbackDepth++;
        totalRollbacks++;
        final triggered = placements.last.position;
        blacklist.add(gridCellKey(triggered.x, triggered.y));
        final available = placements.length - rollbackFloor;
        final popCount = min(rollbackPopCount, max(0, available));
        for (var i = 0; i < popCount; i++) {
          final pop = placements.removeLast();
          final k = gridCellKey(pop.position.x, pop.position.y);
          placed.remove(k);
          frontier.removePlaced(k);
        }
        continue;
      }

      final picked = scorer.pick(candidates, state, random);
      if (picked == null) return null;

      placed.add(picked.cellKey);
      frontier.addPlaced(picked.cellKey);
      placements.add(RetrogradePlacement(
        position: picked.cell,
        direction: picked.direction,
      ));

      blacklist.clear();
      rollbackDepth = 0;
    }

    return placements;
  }

  /// Post-placement pass: flip crunch-window nodes to point at lower-ID cells.
  ///
  /// Invariant: node [i] may point at node [j] only when `j < i`. At removal
  /// step [i], nodes `0..i-1` are gone so the ray is clear; while they remain
  /// on the board, node [i] is blocked — creating forced-sequence pressure.
  List<RetrogradePlacement> _applyPhaseAwareDirectionReassignment(
    List<RetrogradePlacement> removalOrder, {
    required double flipProbability,
    int? liberationNodeId,
  }) {
    final n = removalOrder.length;
    if (n < 3 || flipProbability <= 0) {
      return removalOrder;
    }

    final crunchStart = (n * 0.35).floor().clamp(1, n - 1);
    final crunchEnd = (n * 0.65).ceil().clamp(crunchStart, n - 1);

    final motifKeys = <int>{
      for (final m in motifPlacements)
        for (final r in m.reservations)
          r.cellKey,
    };

    final result = [
      for (final p in removalOrder)
        RetrogradePlacement(position: p.position, direction: p.direction),
    ];

    var flips = 0;
    var offered = 0;

    for (var i = crunchStart; i <= crunchEnd; i++) {
      final node = result[i];
      if (motifKeys.contains(gridCellKey(node.position.x, node.position.y))) {
        continue;
      }
      final blockingDirs = <Direction>[];

      for (final dir in Direction.values) {
        if (dir == node.direction) continue;
        final targetId = _firstNodeIdOnRay(
          node.position,
          dir,
          result,
          selfId: i,
        );
        if (targetId == null || targetId >= i) continue;
        if (!_directionClearAtRemovalStep(i, dir, result)) continue;
        blockingDirs.add(dir);
      }

      if (blockingDirs.isEmpty) continue;
      offered++;

      if (random.nextDouble() >= flipProbability) continue;

      final dep = _buildDependencyIndex(result);
      
      bool pickedLiberation = false;
      if (liberationNodeId != null && liberationNodeId < i) {
        final libPos = result[liberationNodeId].position;
        final libDirs = blockingDirs.where((d) => _pointsTowardLiberation(node.position, d, libPos)).toList();
        if (libDirs.isNotEmpty && random.nextDouble() < 0.60) {
          result[i] = RetrogradePlacement(
            position: node.position,
            direction: libDirs[random.nextInt(libDirs.length)],
          );
          flips++;
          pickedLiberation = true;
        }
      }

      if (pickedLiberation) continue;

      final picked = _pickScoredBlockingDirection(i, blockingDirs, result, dep, liberationNodeId: liberationNodeId);
      result[i] = RetrogradePlacement(
        position: node.position,
        direction: picked,
      );
      flips++;
    }

    reassignmentCrunchFlips = flips;
    reassignmentFlipsOffered = offered;
    scorer.blockingDirCandidatesOffered += offered;
    scorer.blockingDirCandidatesPicked += flips;
    return result;
  }

  DependencyGraph _buildDependencyIndex(List<RetrogradePlacement> order) {
    return DependencyGraph.fromRetrogradeOrder(
      order,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
  }

  bool _pointsTowardLiberation(Point<int> from, Direction dir, Point<int> liberation) {
    switch (dir) {
      case Direction.right: return liberation.y == from.y && liberation.x > from.x;
      case Direction.left:  return liberation.y == from.y && liberation.x < from.x;
      case Direction.down:  return liberation.x == from.x && liberation.y > from.y;
      case Direction.up:    return liberation.x == from.x && liberation.y < from.y;
    }
  }

  int _hubCapFor(int nodeId, int? liberationNodeId) {
    return (nodeId == liberationNodeId) ? 5 : 3;
  }

  double _spatialProximity(
    int i,
    int j,
    List<RetrogradePlacement> order,
  ) {
    final pi = order[i].position;
    final pj = order[j].position;
    if (pi.y != pj.y && pi.x != pj.x) return 0.0;
    final dist = (pi.x - pj.x).abs() + (pi.y - pj.y).abs();
    return dist <= 3 ? 1.0 : 0.0;
  }

  double _scoreReassignmentTarget({
    required int i,
    required int j,
    required DependencyGraph dep,
    required List<RetrogradePlacement> order,
    int? liberationNodeId,
  }) {
    var score = dep.chainDepthOf(j) * 2.0 +
        dep.blockerFanInOf(j) * 1.5 +
        (dep.isBlocked(j) ? 2.0 : 0.0) +
        _spatialProximity(i, j, order) * 0.5 +
        (1.0 / (i - j));
    final fanIn = dep.blockerFanInOf(j);
    final cap = _hubCapFor(j, liberationNodeId);
    if (fanIn >= cap) {
      score -= (fanIn - cap + 1) * 2.0;
    }
    return score;
  }

  Direction _pickScoredBlockingDirection(
    int i,
    List<Direction> blockingDirs,
    List<RetrogradePlacement> order,
    DependencyGraph dep, {
    int? liberationNodeId,
  }) {
    var bestScore = double.negativeInfinity;
    final tied = <Direction>[];
    for (final dir in blockingDirs) {
      final j = _firstNodeIdOnRay(
        order[i].position,
        dir,
        order,
        selfId: i,
      );
      if (j == null || j >= i) continue;
      final score = _scoreReassignmentTarget(
        i: i,
        j: j,
        dep: dep,
        order: order,
        liberationNodeId: liberationNodeId,
      );
      if (score > bestScore + 1e-9) {
        bestScore = score;
        tied
          ..clear()
          ..add(dir);
      } else if ((score - bestScore).abs() < 1e-9) {
        tied.add(dir);
      }
    }
    if (tied.isEmpty) {
      return blockingDirs[random.nextInt(blockingDirs.length)];
    }
    return tied[random.nextInt(tied.length)];
  }

  /// First node hit when stepping from [from] along [dir]; null if ray exits.
  int? _firstNodeIdOnRay(
    Point<int> from,
    Direction dir,
    List<RetrogradePlacement> order, {
    required int selfId,
  }) {
    final keyToId = <int, int>{
      for (var i = 0; i < order.length; i++)
        gridCellKey(order[i].position.x, order[i].position.y): i,
    };
    var x = from.x;
    var y = from.y;
    while (true) {
      switch (dir) {
        case Direction.up:
          y--;
          break;
        case Direction.down:
          y++;
          break;
        case Direction.left:
          x--;
          break;
        case Direction.right:
          x++;
          break;
      }
      if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return null;
      final hit = keyToId[gridCellKey(x, y)];
      if (hit == null) continue;
      if (hit == selfId) return null;
      return hit;
    }
  }

  /// True when [dir] from node [id] does not hit any higher-ID node still
  /// present at canonical removal step [id].
  bool _directionClearAtRemovalStep(
    int id,
    Direction dir,
    List<RetrogradePlacement> order,
  ) {
    var x = order[id].position.x;
    var y = order[id].position.y;
    while (true) {
      switch (dir) {
        case Direction.up:
          y--;
          break;
        case Direction.down:
          y++;
          break;
        case Direction.left:
          x--;
          break;
        case Direction.right:
          x++;
          break;
      }
      if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return true;
      for (var k = id + 1; k < order.length; k++) {
        final p = order[k].position;
        if (p.x == x && p.y == y) return false;
      }
    }
  }

  /// Converts forward-construction placements to canonical removal order
  /// (last-placed during retrograde build → id 0 / first player tap).
  ///
  /// Cross-block reorder was removed — a full [List.sort] on IDs broke the
  /// solvability invariant after crunch blocking and forced retry collapse.
  List<RetrogradePlacement> _finalizeRemovalOrder(
    List<RetrogradePlacement> forwardPlacements,
  ) {
    return forwardPlacements.reversed.toList(growable: false);
  }

  List<RetrogradePlacement> _enforceOpeningTarget(
    List<RetrogradePlacement> placements, {
    required int maxOpening,
    required int minOpening,
  }) {
    var current = placements.toList();
    for (var attempt = 0; attempt < 20; attempt++) {
      final opening = _waveZeroWidth(current);
      if (opening <= maxOpening && opening >= minOpening) break;


      final freeIndices = _rayFreeIndices(current);
      freeIndices.sort((a, b) => b.compareTo(a));

      var flippedAny = false;
      for (final i in freeIndices) {
        if (_waveZeroWidth(current) <= maxOpening) break;
        if (_waveZeroWidth(current) <= minOpening) break;

        final node = current[i];
        final dirs = Direction.values.toList()..shuffle(random);
        for (final dir in dirs) {
          if (dir == node.direction) continue;
          final j = _firstNodeIdOnRay(node.position, dir, current, selfId: i);
          if (j != null &&
              j < i &&
              _directionClearAtRemovalStep(i, dir, current)) {
            final next = current.toList();
            next[i] = RetrogradePlacement(
              position: node.position,
              direction: dir,
            );
            if (_validatesRemovalOrderIdSequence(next)) {
              current = next;
              flippedAny = true;
              break;
            }
          }
        }
      }
      if (!flippedAny) break;
    }
    return current;
  }

  int _waveZeroWidth(List<RetrogradePlacement> placements) {
    final nodes = <NodeData>[
      for (var i = 0; i < placements.length; i++)
        NodeData(
          id: i,
          x: placements[i].position.x,
          y: placements[i].position.y,
          dir: placements[i].direction,
        ),
    ];
    final level = LevelData(
      levelId: 0,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      nodes: nodes,
    );
    final profile = computeWavePeelingProfile(level);
    return profile.isEmpty ? 0 : profile.first;
  }

  List<int> _rayFreeIndices(List<RetrogradePlacement> current) {
    final freeIndices = <int>[];
    for (var i = 0; i < current.length; i++) {
      final target = _firstNodeIdOnRay(
        current[i].position,
        current[i].direction,
        current,
        selfId: i,
      );
      if (target == null) freeIndices.add(i);
    }
    return freeIndices;
  }

  bool _validatesRemovalOrderIdSequence(List<RetrogradePlacement> removalOrder) {
    final nodes = <NodeData>[
      for (var i = 0; i < removalOrder.length; i++)
        NodeData(
          id: i,
          x: removalOrder[i].position.x,
          y: removalOrder[i].position.y,
          dir: removalOrder[i].direction,
        ),
    ];
    final level = LevelData(
      levelId: 0,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      nodes: nodes,
    );
    final remaining = nodes.map((n) => n.clone()).toList();
    final byId = List<NodeData>.from(nodes)..sort((a, b) => a.id.compareTo(b.id));
    for (final n in byId) {
      if (!LevelSolver.canRemove(n, remaining, level)) return false;
      remaining.removeWhere((r) => r.id == n.id);
    }
    return remaining.isEmpty;
  }

  List<Candidate> _enumerateCandidates(
    ConstructionState state,
    Set<int> blacklist,
    Set<int> forbiddenCells,
  ) {
    final rayObs = <int>{...state.placed, ...forbiddenCells};
    final occ = state.occupancyRatio ?? 0.0;
    final result = <Candidate>[];
    for (final cellKey in state.frontier.cells) {
      if (blacklist.contains(cellKey)) continue;
      if (forbiddenCells.contains(cellKey)) continue;
      if (state.placed.contains(cellKey)) continue;
      final x = cellKey & 0xffff;
      final y = (cellKey >> 16) & 0xffff;
      final pos = Point<int>(x, y);
      final clearDirs = <Direction>[];
      final blockingDirs = <Direction>[];
      for (final dir in Direction.values) {
        if (state.sightlines.hasClearRay(x, y, dir, rayObs)) {
          clearDirs.add(dir);
        } else if (rayHitsObstacleBeforeExit(
          pos,
          dir,
          rayObs,
          gridWidth,
          gridHeight,
        )) {
          blockingDirs.add(dir);
        }
      }

      final dirs = _directionPoolForZone(occ, clearDirs, blockingDirs);
      if (dirs.isEmpty) continue;

      for (final dir in dirs) {
        final isBlocking = blockingDirs.contains(dir);
        if (isBlocking) scorer.blockingDirCandidatesOffered++;
        result.add(Candidate(
          cellKey: cellKey,
          cell: pos,
          direction: dir,
          clearDirectionCount: clearDirs.isEmpty ? 1 : clearDirs.length,
          isBlockingRay: isBlocking,
        ));
      }
    }
    return result;
  }

  /// Clear-ray-only pool during coordinate placement; crunch blocking is
  /// applied later via [_applyPhaseAwareDirectionReassignment].
  List<Direction> _directionPoolForZone(
    double occupancy,
    List<Direction> clearDirs,
    List<Direction> blockingDirs,
  ) {
    if (clearDirs.isNotEmpty) return clearDirs;
    return blockingDirs;
  }
}
