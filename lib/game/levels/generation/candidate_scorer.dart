import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
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

  const Candidate({
    required this.cellKey,
    required this.cell,
    required this.direction,
    required this.clearDirectionCount,
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

  const ConstructionState({
    required this.gridWidth,
    required this.gridHeight,
    required this.silhouette,
    required this.placed,
    required this.frontier,
    required this.sightlines,
    this.eightConnected = false,
  });
}

/// Weighted-sum scorer with softmax sampling.
///
/// Stateless apart from [weights]; pass the per-step [ConstructionState] into
/// [pick] / [score] / [featureBreakdown].
class CandidateScorer {
  final ScorerWeights weights;

  const CandidateScorer({this.weights = const ScorerWeights()});

  /// Picks one candidate via softmax over [score]; returns null on empty input.
  Candidate? pick(
    List<Candidate> candidates,
    ConstructionState state,
    Random random,
  ) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;

    final scores = List<double>.generate(
      candidates.length,
      (i) => score(candidates[i], state),
      growable: false,
    );
    return _softmaxPick(candidates, scores, random);
  }

  /// Linear combination of the Phase-1 features.
  double score(Candidate c, ConstructionState state) {
    return weights.unlockFanout * _unlockFanout(c, state) +
        weights.mrvBonus * _mrvBonus(c) -
        weights.isolationPenalty * _isolationPenalty(c, state);
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
}
