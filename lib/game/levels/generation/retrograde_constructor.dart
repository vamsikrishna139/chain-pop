import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import 'candidate_scorer.dart';
import 'frontier_set.dart';
import 'motifs.dart';
import 'sightline_table.dart';

/// A single committed placement in the retrograde sequence — a board cell
/// paired with the direction whose ray was clear at the moment of placement.
class RetrogradePlacement {
  /// `(x, y)` on the bounding grid.
  final Point<int> position;

  /// The direction the node will fire when extracted.
  final Direction direction;

  const RetrogradePlacement({
    required this.position,
    required this.direction,
  });

  @override
  String toString() => 'RetrogradePlacement($position, $direction)';
}

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
  /// deferred motif reservations are injected — bulk treats those keys as
  /// ray obstacles so the greedy ray semantics never "see through" holes
  /// reserved for motifs.
  static const double kDefaultMotifOccupancyThreshold = 0.55;

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

  /// Pre-committed Motif Transaction reservations (§4.6). Injected **after**
  /// the bulk occupancy threshold so motif cells are placed **late** in the
  /// construction order → **early** in player removal order.
  final List<MotifReservation> reservations;

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
    this.reservations = const <MotifReservation>[],
  }) : maxTotalRollbacks = maxTotalRollbacks ?? (maxRollbackDepth * 4);

  /// Runs the constructor.
  ///
  /// Returns the placements in **removal order** — index 0 is the first node
  /// the player taps, index N-1 the last. Returns null on irrecoverable
  /// failure (silhouette starvation or rollback depth exceeded).
  List<RetrogradePlacement>? construct() {
    if (targetNodeCount <= 0) return <RetrogradePlacement>[];
    if (silhouette.length < targetNodeCount) return null;
    if (reservations.length > targetNodeCount) return null;

    if (reservations.isEmpty) {
      return _constructPlain();
    }
    return _constructDeferredMotifs();
  }

  List<RetrogradePlacement>? _constructPlain() {
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

    return placements.reversed.toList(growable: false);
  }

  List<RetrogradePlacement>? _constructDeferredMotifs() {
    final seenKeys = <int>{};
    for (final r in reservations) {
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

    var unplacedMotifKeys = {for (final r in reservations) r.cellKey};
    var motifQueue = List<MotifReservation>.from(reservations);

    var motifPhase = false;
    var freezeBulkCount = 0;
    /// Rollback may not pop placements with index < rollbackFloor.
    var rollbackFloor = 0;

    var rollbackDepth = 0;
    var totalRollbacks = 0;

    final motifReservationCount = reservations.length;
    final bulkSlotsBeforeMotifs = targetNodeCount - motifReservationCount;

    bool bulkPrefixCompleteForMotifs() {
      if (motifQueue.isEmpty) return false;
      final occGate = min(
        (kDefaultMotifOccupancyThreshold * silhouette.length).ceil(),
        bulkSlotsBeforeMotifs,
      );
      return placements.length >= bulkSlotsBeforeMotifs &&
          placements.length >= occGate;
    }

    void enterMotifPhase() {
      motifPhase = true;
      freezeBulkCount = placements.length;
      rollbackFloor = freezeBulkCount;
      rollbackDepth = 0;
      blacklist.clear();
      motifQueue = List<MotifReservation>.from(motifQueue)..shuffle(random);
    }

    bool tryPlaceNextMotif() {
      if (motifQueue.isEmpty) return false;
      final r = motifQueue.first;
      final key = r.cellKey;
      // Reserved-but-empty sibling motif cells must not block — only committed
      // [placed] nodes behave as obstacles for the ray probe (§6 motif phase).
      if (!sightlines.hasClearRay(
        r.position.x,
        r.position.y,
        r.direction,
        placed,
      )) {
        return false;
      }
      motifQueue = motifQueue.sublist(1);
      unplacedMotifKeys.remove(key);
      placed.add(key);
      frontier.addPlaced(key);
      placements.add(RetrogradePlacement(
        position: r.position,
        direction: r.direction,
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
      motifQueue = [];
      unplacedMotifKeys.clear();
      motifPhase = false;
      rollbackFloor = 0;
      blacklist.clear();
      rollbackDepth = 0;
    }

    while (placements.length < targetNodeCount) {
      if (!motifPhase &&
          motifQueue.isNotEmpty &&
          bulkPrefixCompleteForMotifs()) {
        enterMotifPhase();
      }

      if (motifPhase && motifQueue.isNotEmpty) {
        var placedThisRound = false;
        for (var attempt = 0;
            attempt < motifQueue.length && !placedThisRound;
            attempt++) {
          if (tryPlaceNextMotif()) {
            placedThisRound = true;
            if (motifQueue.isEmpty) {
              motifPhase = false;
            }
            break;
          }
          if (motifQueue.length > 1) {
            motifQueue = [...motifQueue.sublist(1), motifQueue.first];
          }
        }
        if (placedThisRound) {
          continue;
        }
        // Motif sub-phase deadlock — abandon motifs, freeze bulk prefix.
        degradeMotifTransaction();
        continue;
      }

      final state = ConstructionState(
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        silhouette: silhouette,
        placed: placed,
        frontier: frontier,
        sightlines: sightlines,
        eightConnected: eightConnected,
      );

      final candidates =
          _enumerateCandidates(state, blacklist, unplacedMotifKeys);
      if (candidates.isEmpty) {
        if (!motifPhase &&
            motifQueue.isNotEmpty &&
            bulkPrefixCompleteForMotifs()) {
          enterMotifPhase();
          continue;
        }
        if (rollbackDepth >= maxRollbackDepth) return null;
        if (totalRollbacks >= maxTotalRollbacks) return null;
        if (placements.length <= rollbackFloor) {
          if (motifQueue.isNotEmpty) {
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

    return placements.reversed.toList(growable: false);
  }

  List<Candidate> _enumerateCandidates(
    ConstructionState state,
    Set<int> blacklist,
    Set<int> forbiddenCells,
  ) {
    final rayObs = <int>{...state.placed, ...forbiddenCells};
    final result = <Candidate>[];
    for (final cellKey in state.frontier.cells) {
      if (blacklist.contains(cellKey)) continue;
      if (forbiddenCells.contains(cellKey)) continue;
      if (state.placed.contains(cellKey)) continue;
      final x = cellKey & 0xffff;
      final y = (cellKey >> 16) & 0xffff;
      final clearDirs = <Direction>[];
      for (final dir in Direction.values) {
        if (state.sightlines.hasClearRay(x, y, dir, rayObs)) {
          clearDirs.add(dir);
        }
      }
      if (clearDirs.isEmpty) continue;
      for (final dir in clearDirs) {
        result.add(Candidate(
          cellKey: cellKey,
          cell: Point<int>(x, y),
          direction: dir,
          clearDirectionCount: clearDirs.length,
        ));
      }
    }
    return result;
  }
}
