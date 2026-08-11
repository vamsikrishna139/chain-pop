import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import 'dependency_graph.dart';
import 'difficulty_profile.dart';
import 'frontier_set.dart';
import 'sightline_table.dart';

/// Weights for the [CandidateScorer]'s linear combination of feature scores.
///
/// Phase 1 ships the three baseline weights (`unlockFanout`, `mrvBonus`,
/// `isolationPenalty`) plus a softmax `temperature`. Later phases extend this
/// struct with `motifReinforcement`, `aestheticBias`, `densityFieldBias`, and
/// archetype-controlled per-feature signs.
class ScorerWeights {
  /// Linear weight on the [_unlockFanout] feature.
  final double unlockFanout;

  /// Linear weight on the [_mrvBonus] feature (CSP minimum-remaining-values).
  final double mrvBonus;

  /// Linear weight on the [_isolationPenalty] feature (subtracted, not added).
  final double isolationPenalty;

  /// Softmax temperature. Lower = more deterministic; higher = more random.
  /// Clamped to a positive minimum at sampling time.
  final double temperature;

  const ScorerWeights({
    this.unlockFanout = 1.0,
    this.mrvBonus = 0.6,
    this.isolationPenalty = 1.2,
    this.temperature = 1.0,
  });

  ScorerWeights copyWith({
    double? unlockFanout,
    double? mrvBonus,
    double? isolationPenalty,
    double? temperature,
  }) {
    return ScorerWeights(
      unlockFanout: unlockFanout ?? this.unlockFanout,
      mrvBonus: mrvBonus ?? this.mrvBonus,
      isolationPenalty: isolationPenalty ?? this.isolationPenalty,
      temperature: temperature ?? this.temperature,
    );
  }
}

/// A single placement option — a cell paired with a specific direction whose
/// ray is currently clear.
class Candidate {
  /// Packed cell key (matches [gridCellKey]).
  final int cellKey;

  /// `(x, y)` of [cellKey], for convenience.
  final Point<int> cell;

  /// The direction whose ray is clear.
  final Direction direction;

  /// Number of directions whose ray is clear from [cell] in the current state
  /// (1–4). Used as input to the MRV feature.
  final int clearDirectionCount;

  /// True when the chosen direction's ray hits a placed node before exiting.
  final bool isBlockingRay;

  const Candidate({
    required this.cellKey,
    required this.cell,
    required this.direction,
    required this.clearDirectionCount,
    this.isBlockingRay = false,
  });
}

/// Snapshot of the retrograde construction state that the scorer needs to
/// compute its features. Passed by reference; the scorer does not mutate it.
class ConstructionState {
  final int gridWidth;
  final int gridHeight;
  final Set<int> silhouette;
  final Set<int> placed;
  final FrontierSet frontier;
  final SightlineTable sightlines;
  final bool eightConnected;

  /// Retrograde fill ratio (`placed / target`) for phase-based scorer bias.
  final double? occupancyRatio;

  /// Optional center point of the cascade/liberation hub to draw rays toward.
  final Point<int>? liberationPosition;

  const ConstructionState({
    required this.gridWidth,
    required this.gridHeight,
    required this.silhouette,
    required this.placed,
    required this.frontier,
    required this.sightlines,
    this.eightConnected = false,
    this.occupancyRatio,
    this.liberationPosition,
  });
}

/// Softmax pre-filter: prefer blocking rays during crunch-zone construction.
const double kCrunchBlockingProbability = 0.72;

/// Bonus when a blocking direction is picked in the crunch zone.
const double kBlockingDirectionBonus = 1.5;

/// Per-intercept weight along a candidate ray.
const double kRayInterceptWeight = 0.40;

/// Hard penalty for blocking directions during the opening phase.
const double kBlockingDirectionPenalty = 8.0;

/// Count of placed nodes intersected along `(pos, dir)` before grid exit.
int rayInterceptCount(
  Point<int> pos,
  Direction dir,
  Iterable<Point<int>> placed,
  int gridWidth,
  int gridHeight,
) {
  final obstacles = {
    for (final p in placed) gridCellKey(p.x, p.y),
  };
  var count = 0;
  var x = pos.x;
  var y = pos.y;
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
    if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return count;
    if (obstacles.contains(gridCellKey(x, y))) count++;
  }
}

/// Count of other nodes sharing the same row or column as `(x, y)`.
int crossBlockCountAt(int x, int y, Iterable<Point<int>> others) {
  var count = 0;
  for (final o in others) {
    if (o.x == x || o.y == y) count++;
  }
  return count;
}

/// Weighted-sum scorer with softmax sampling.
///
/// Stateless apart from [weights]; pass the per-step [ConstructionState] into
/// [pick] / [score] / [featureBreakdown].
class CandidateScorer {
  final ScorerWeights weights;

  /// Crunch-zone softmax pre-filter strength; lowered on solvability retries.
  double crunchBlockingProbability;

  /// Debug telemetry — blocking rays offered / picked this construction.
  int blockingDirCandidatesOffered = 0;
  int blockingDirCandidatesPicked = 0;

  /// Blocking picks in crunch zone (occ 0.35–0.65) vs release fallback (occ < 0.35).
  int crunchZoneBlockingPicked = 0;
  int releaseZoneFallbackPicked = 0;

  CandidateScorer({
    this.weights = const ScorerWeights(),
    this.crunchBlockingProbability = kCrunchBlockingProbability,
  });

  /// Picks one candidate via softmax over [score]; returns null on empty input.
  Candidate? pick(
    List<Candidate> candidates,
    ConstructionState state,
    Random random,
  ) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) {
      _recordBlockingPick(candidates.first, state.occupancyRatio);
      return candidates.first;
    }

    var pool = candidates;
    final occ = state.occupancyRatio;
    if (occ != null && occ >= 0.35 && occ <= 0.65) {
      final blocking =
          candidates.where((c) => c.isBlockingRay).toList(growable: false);
      if (blocking.isNotEmpty &&
          random.nextDouble() < crunchBlockingProbability) {
        pool = blocking;
      }
    }

    final scores = List<double>.generate(
      pool.length,
      (i) => score(pool[i], state),
      growable: false,
    );
    final picked = _softmaxPick(pool, scores, random);
    _recordBlockingPick(picked, occ);
    return picked;
  }

  void _recordBlockingPick(Candidate? picked, double? occ) {
    if (picked == null || !picked.isBlockingRay) return;
    blockingDirCandidatesPicked++;
    if (occ == null) return;
    if (occ >= 0.35 && occ <= 0.65) {
      crunchZoneBlockingPicked++;
    } else if (occ < 0.35) {
      releaseZoneFallbackPicked++;
    }
  }

  /// Linear combination of the Phase-1 features with optional Phase-3C
  /// occupancy-phase bias (retrograde construction arc).
  double score(Candidate c, ConstructionState state) {
    var unlockW = weights.unlockFanout;
    var isolationW = weights.isolationPenalty;
    final occ = state.occupancyRatio;
    if (occ != null) {
      if (occ <= 0.30) {
        unlockW *= 1.35; // cascade finale
      } else if (occ <= 0.55) {
        isolationW *= 1.25; // lock-cluster crunch zone
      } else if (occ >= 0.85) {
        unlockW *= 1.25;
        isolationW *= 0.75; // easy opening taps
      }
    }
    var total = unlockW * _unlockFanout(c, state) +
        weights.mrvBonus * _mrvBonus(c) -
        isolationW * _isolationPenalty(c, state);
    if (occ != null) {
      final placedPoints = _placedPoints(state);
      if (occ >= 0.35 && occ <= 0.65) {
        if (c.isBlockingRay) total += kBlockingDirectionBonus;
        total += rayInterceptCount(
              c.cell,
              c.direction,
              placedPoints,
              state.gridWidth,
              state.gridHeight,
            ) *
            kRayInterceptWeight;
        
        total += _calculateLiberationAxisBonus(c, state.liberationPosition, occ);
      } else if (occ > 0.65 && c.isBlockingRay) {
        total -= kBlockingDirectionPenalty;
      }
    }
    return total;
  }

  double _calculateLiberationAxisBonus(Candidate candidate, Point<int>? liberationPos, double occupancy) {
    if (liberationPos == null || occupancy < 0.35 || occupancy > 0.65) return 0.0;
    
    // Check if the candidate coordinate shares a clean X or Y axis with the liberation hub
    bool sharesAxis = candidate.cell.x == liberationPos.x || candidate.cell.y == liberationPos.y;
    
    if (sharesAxis) {
      int manhattanDistance = (candidate.cell.x - liberationPos.x).abs() + 
                              (candidate.cell.y - liberationPos.y).abs();
      // Heavily reward close proximity along the same orthogonal lanes
      if (manhattanDistance <= 4) return 3.5;
      return 1.5;
    }
    return 0.0;
  }

  /// Per-feature breakdown — handy for tests and (later) analytics.
  ({double unlockFanout, double mrvBonus, double isolationPenalty})
      featureBreakdown(Candidate c, ConstructionState state) {
    return (
      unlockFanout: _unlockFanout(c, state),
      mrvBonus: _mrvBonus(c),
      isolationPenalty: _isolationPenalty(c, state),
    );
  }

  /// How many silhouette neighbours of [c] that are NOT currently in the
  /// frontier will gain at least one clear direction once [c] is placed.
  ///
  /// In retrograde terms: how many "fresh" cells the placement unlocks for
  /// the next step.
  double _unlockFanout(Candidate c, ConstructionState state) {
    final placedAfter = <int>{...state.placed, c.cellKey};
    var count = 0;
    final x = c.cell.x;
    final y = c.cell.y;
    for (final off in _offsetsFor(state.eightConnected)) {
      final nx = x + off.$1;
      final ny = y + off.$2;
      if (nx < 0 ||
          nx >= state.gridWidth ||
          ny < 0 ||
          ny >= state.gridHeight) {
        continue;
      }
      final nkey = gridCellKey(nx, ny);
      if (!state.silhouette.contains(nkey)) continue;
      if (placedAfter.contains(nkey)) continue;
      if (state.frontier.contains(nkey)) continue;
      for (final d in Direction.values) {
        if (state.sightlines.hasClearRay(nx, ny, d, placedAfter)) {
          count++;
          break;
        }
      }
    }
    return count.toDouble();
  }

  /// CSP MRV: prefer placements at cells with few clear directions remaining.
  /// Returns 0 if all 4 directions are clear, up to 3 if only one is.
  double _mrvBonus(Candidate c) {
    return (4 - c.clearDirectionCount).toDouble();
  }

  List<Point<int>> _placedPoints(ConstructionState state) {
    return [
      for (final key in state.placed)
        Point<int>(key & 0xffff, (key >> 16) & 0xffff),
    ];
  }

  /// Cheap "small island" proxy: count empty silhouette cells in the
  /// 8-neighbourhood. Penalty grows as this count drops below 3.
  ///
  /// True island detection would require a flood-fill per candidate, which is
  /// too expensive for the inner loop. This proxy catches the common case
  /// where a placement plugs a single-cell pocket.
  double _isolationPenalty(Candidate c, ConstructionState state) {
    var emptyNeighbours = 0;
    final x = c.cell.x;
    final y = c.cell.y;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 ||
            nx >= state.gridWidth ||
            ny < 0 ||
            ny >= state.gridHeight) {
          continue;
        }
        final nkey = gridCellKey(nx, ny);
        if (!state.silhouette.contains(nkey)) continue;
        if (state.placed.contains(nkey) || nkey == c.cellKey) continue;
        emptyNeighbours++;
      }
    }
    if (emptyNeighbours >= 3) return 0.0;
    return (3 - emptyNeighbours).toDouble();
  }

  List<(int, int)> _offsetsFor(bool eightConnected) {
    if (eightConnected) {
      return const [
        (-1, 0),
        (1, 0),
        (0, -1),
        (0, 1),
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1),
      ];
    }
    return const [
      (-1, 0),
      (1, 0),
      (0, -1),
      (0, 1),
    ];
  }

  Candidate _softmaxPick(
    List<Candidate> candidates,
    List<double> scores,
    Random random,
  ) {
    final t = weights.temperature < 1e-3 ? 1e-3 : weights.temperature;
    var maxS = scores[0];
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > maxS) maxS = scores[i];
    }
    final exps = List<double>.generate(
      scores.length,
      (i) => exp((scores[i] - maxS) / t),
      growable: false,
    );
    var total = 0.0;
    for (final e in exps) {
      total += e;
    }
    if (total == 0.0) return candidates[random.nextInt(candidates.length)];
    var r = random.nextDouble() * total;
    for (var i = 0; i < exps.length; i++) {
      r -= exps[i];
      if (r <= 0) return candidates[i];
    }
    return candidates.last;
  }

  /// Soft topology preference for Hard/Expert in-band candidate ranking (B3).
  static double topologyPreferenceScore(
    DependencyGraph graph,
    DifficultyTier tier,
  ) {
    return DifficultyProfile.forTier(tier).topologySoftScoreFromGraph(graph);
  }
}
