import 'dart:math';

import '../grid_cell_key.dart';
import 'archetype.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_configuration.dart';
import 'level_seed.dart';
import 'motifs.dart';
import 'sightline_table.dart';
import 'silhouettes.dart';

/// Concrete generation plan the Director hands to one Retrograde (or legacy)
/// attempt. Immutable; the Director produces a fresh [GenerationPlan] on
/// each call to [Director.choosePlan] or [Director.renegotiate].
class GenerationPlan {
  final GenerationArchetype archetype;
  final GenerationArchetypeSpec spec;
  final SilhouetteId silhouette;
  final Set<int> silhouetteMask;
  final int targetNodeCount;
  final DifficultyTier tier;
  final DifficultyProfile profile;

  /// True when the Director chose to honour the Experimental archetype's
  /// "use the legacy greedy path" option. The caller routes accordingly.
  final bool useLegacyGreedyPath;

  /// 0-based renegotiation depth; incremented when [Director.renegotiate]
  /// is called. Plain `choosePlan` returns plans with depth 0.
  final int renegotiationDepth;

  /// Motif placements the Retrograde Constructor must honour (§4.6). Empty
  /// for archetypes whose `motifBudget == 0` or when the Director failed to
  /// place a motif on the silhouette.
  final List<MotifPlacement> motifs;

  const GenerationPlan({
    required this.archetype,
    required this.spec,
    required this.silhouette,
    required this.silhouetteMask,
    required this.targetNodeCount,
    required this.tier,
    required this.profile,
    required this.useLegacyGreedyPath,
    this.renegotiationDepth = 0,
    this.motifs = const <MotifPlacement>[],
  });

  /// Convenience: flattened list of all reservations from all motif blocks.
  List<MotifReservation> get reservations => [
        for (final m in motifs) ...m.reservations,
      ];

  GenerationPlan copyWith({
    SilhouetteId? silhouette,
    Set<int>? silhouetteMask,
    int? targetNodeCount,
    bool? useLegacyGreedyPath,
    int? renegotiationDepth,
    List<MotifPlacement>? motifs,
  }) {
    return GenerationPlan(
      archetype: archetype,
      spec: spec,
      silhouette: silhouette ?? this.silhouette,
      silhouetteMask: silhouetteMask ?? this.silhouetteMask,
      targetNodeCount: targetNodeCount ?? this.targetNodeCount,
      tier: tier,
      profile: profile,
      useLegacyGreedyPath: useLegacyGreedyPath ?? this.useLegacyGreedyPath,
      renegotiationDepth: renegotiationDepth ?? this.renegotiationDepth,
      motifs: motifs ?? this.motifs,
    );
  }
}

/// Generation Director — §4.1.
///
/// Per-attempt responsibilities:
/// 1. Sample an archetype from §5's `[GenerationArchetypeSpec.distribution]`.
/// 2. Pick a silhouette consistent with the archetype.
/// 3. Decide the [DifficultyTier] (caller may pass an override for Daily).
/// 4. Pre-reserve Motif Transactions — **Phase 4 work**; Phase 3 stubs
///    `motifBudget = 0` everywhere.
/// 5. Hand the [GenerationPlan] back to the caller.
///
/// On retrograde failure the caller invokes [renegotiate], which scales the
/// node count down by 10% or swaps to another silhouette in the same
/// archetype family. After [maxRenegotiations] swaps the Director gives up
/// (returns null); the caller then escalates to the next K-loop attempt.
class Director {
  /// Maximum renegotiation depth before the Director gives up on the
  /// current plan and the K-loop must start fresh.
  final int maxRenegotiations;

  /// Invoked when a silhouette-specific mask fails [buildSilhouetteMask]'s
  /// size gates and construction falls back to the full rectangular field
  /// (interpreted here as resolving to [SilhouetteId.rectangle]'s mask —
  /// [resolved] is always `rectangle`).
  ///
  /// Optional test/offline tooling only — production defaults to null.
  final void Function(SilhouetteId attempted, SilhouetteId resolved)?
      onMaskRectangleFallback;

  Director({this.maxRenegotiations = 3, this.onMaskRectangleFallback});

  /// Builds the initial plan for [config].
  ///
  /// If [overrideTier] is non-null it takes precedence over the tier derived
  /// from `config.difficulty.mode` — used by Daily callers that want the
  /// Expert band.
  GenerationPlan choosePlan(
    LevelConfiguration config,
    Random random, {
    DifficultyTier? overrideTier,
  }) {
    final archetype =
        GenerationArchetypeSpec.sample(random, config.difficulty.mode);
    final spec = GenerationArchetypeSpec.forArchetype(archetype);
    final useLegacy = archetype == GenerationArchetype.experimental &&
        random.nextDouble() < spec.legacyGreedyProbability;
    final silhouette = _pickSilhouette(spec, random);
    final mask = _buildOrFallbackMask(
      silhouette: silhouette,
      config: config,
      random: random,
    );
    final tier =
        overrideTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    final profile = DifficultyProfile.forTier(tier);
    final target = _pickTargetNodeCount(
      config: config,
      mask: mask,
      tier: tier,
      random: random,
    );
    final motifs = _reserveMotifs(
      spec: spec,
      useLegacyGreedyPath: useLegacy,
      config: config,
      mask: mask,
      target: target,
      random: random,
    );
    return GenerationPlan(
      archetype: archetype,
      spec: spec,
      silhouette: silhouette,
      silhouetteMask: mask,
      targetNodeCount: target,
      tier: tier,
      profile: profile,
      useLegacyGreedyPath: useLegacy,
      motifs: motifs,
    );
  }

  /// §9 Phase 5 — builds a plan from a hand-authored [LevelSeed], bypassing
  /// the random archetype + silhouette sampling. The seed pins the style;
  /// the rest of the pipeline (constructor, evaluator, diversity ledger)
  /// still runs.
  GenerationPlan choosePlanFromSeed(
    LevelSeed seed,
    LevelConfiguration config,
    Random random,
  ) {
    final spec = GenerationArchetypeSpec.forArchetype(seed.archetypeId);
    // Seeded levels never roll the Experimental greedy-path coin so that the
    // seed's intent is honoured deterministically.
    const useLegacy = false;
    final mask = _buildOrFallbackMask(
      silhouette: seed.silhouetteId,
      config: config,
      random: random,
    );
    final profile = DifficultyProfile.forTier(seed.difficultyTier);
    final target = seed.targetNodeCount ??
        _pickTargetNodeCount(
          config: config,
          mask: mask,
          tier: seed.difficultyTier,
          random: random,
        );
    final clampedTarget = target.clamp(1, mask.length);
    final motifs = _reserveSeededMotifs(
      seed: seed,
      spec: spec,
      config: config,
      mask: mask,
      target: clampedTarget,
      random: random,
    );
    return GenerationPlan(
      archetype: seed.archetypeId,
      spec: spec,
      silhouette: seed.silhouetteId,
      silhouetteMask: mask,
      targetNodeCount: clampedTarget,
      tier: seed.difficultyTier,
      profile: profile,
      useLegacyGreedyPath: useLegacy,
      motifs: motifs,
    );
  }

  /// §4.1 Renegotiation. Returns null when the renegotiation budget has been
  /// exhausted so the caller can move on to the next outer attempt.
  GenerationPlan? renegotiate(
    GenerationPlan previous,
    LevelConfiguration config,
    Random random,
  ) {
    if (previous.renegotiationDepth >= maxRenegotiations) return null;

    final downscaled =
        max(config.difficulty.minNodes, (previous.targetNodeCount * 0.9).round());
    SilhouetteId nextSilhouette = previous.silhouette;
    Set<int> nextMask = previous.silhouetteMask;
    // Every other renegotiation, swap silhouette as well to escape silhouette
    // starvation rather than just shrinking node count.
    if (previous.renegotiationDepth.isOdd) {
      final candidates = previous.spec.preferredSilhouettes
          .where((s) => s != previous.silhouette)
          .toList();
      if (candidates.isNotEmpty) {
        nextSilhouette = candidates[random.nextInt(candidates.length)];
        nextMask = _buildOrFallbackMask(
          silhouette: nextSilhouette,
          config: config,
          random: random,
        );
      }
    }
    // Re-roll motifs on every renegotiation — the silhouette and node count
    // may have changed, and the previous reservation may now starve the
    // constructor. Failed reservations decay to an empty motif list rather
    // than blocking renegotiation entirely.
    final remappedMotifs = _reserveMotifs(
      spec: previous.spec,
      useLegacyGreedyPath: previous.useLegacyGreedyPath,
      config: config,
      mask: nextMask,
      target: downscaled,
      random: random,
    );
    return previous.copyWith(
      silhouette: nextSilhouette,
      silhouetteMask: nextMask,
      targetNodeCount: downscaled,
      renegotiationDepth: previous.renegotiationDepth + 1,
      motifs: remappedMotifs,
    );
  }

  /// After the legacy greedy path honestly fails elimination ordering, relax
  /// density first (−2..−3 nodes toward [minNodes]), then apply the same
  /// alternating silhouette carousel as [renegotiate] on odd depths.
  GenerationPlan? renegotiateAfterGreedyFailure(
    GenerationPlan previous,
    LevelConfiguration config,
    Random random,
  ) {
    if (previous.renegotiationDepth >= maxRenegotiations) return null;

    final drop = 2 + random.nextInt(2); // 2 or 3
    var downscaled = max(
      config.difficulty.minNodes,
      previous.targetNodeCount - drop,
    );

    SilhouetteId nextSilhouette = previous.silhouette;
    Set<int> nextMask = previous.silhouetteMask;
    // After relaxing density, every other renegotiation swaps silhouette.
    if (previous.renegotiationDepth.isOdd) {
      final candidates = previous.spec.preferredSilhouettes
          .where((s) => s != previous.silhouette)
          .toList();
      if (candidates.isNotEmpty) {
        nextSilhouette = candidates[random.nextInt(candidates.length)];
        nextMask = _buildOrFallbackMask(
          silhouette: nextSilhouette,
          config: config,
          random: random,
        );
        downscaled = downscaled.clamp(1, nextMask.length);
      }
    } else {
      nextMask = _buildOrFallbackMask(
        silhouette: nextSilhouette,
        config: config,
        random: random,
      );
      downscaled = downscaled.clamp(1, nextMask.length);
    }

    final remappedMotifs = _reserveMotifs(
      spec: previous.spec,
      useLegacyGreedyPath: previous.useLegacyGreedyPath,
      config: config,
      mask: nextMask,
      target: downscaled,
      random: random,
    );
    return previous.copyWith(
      silhouette: nextSilhouette,
      silhouetteMask: nextMask,
      targetNodeCount: downscaled,
      renegotiationDepth: previous.renegotiationDepth + 1,
      motifs: remappedMotifs,
    );
  }

  /// §4.6 — picks the per-attempt motif count (`1..motifBudget`) and tries to
  /// place them on the current silhouette. Returns an empty list when the
  /// archetype has no budget, the level is too small, or every roll failed.
  List<MotifPlacement> _reserveMotifs({
    required GenerationArchetypeSpec spec,
    required bool useLegacyGreedyPath,
    required LevelConfiguration config,
    required Set<int> mask,
    required int target,
    required Random random,
  }) {
    if (spec.motifBudget <= 0) return const [];
    // The legacy greedy path cannot honour reservations.
    if (useLegacyGreedyPath) return const [];
    // Don't burn half the level on motif cells — keep at most ~40% reserved.
    final maxReservationCells = (target * 0.4).floor();
    if (maxReservationCells < 3) return const [];

    final desired = 1 + random.nextInt(spec.motifBudget);
    final sightlines = SightlineTable.forGrid(
      config.gridWidth,
      config.gridHeight,
    );

    final placed = <MotifPlacement>[];
    final usedCells = <int>{};
    var reservedSoFar = 0;
    final catalogue = [...motifCatalogue()]..shuffle(random);
    for (final motif in catalogue) {
      if (placed.length >= desired) break;
      final placement = motif.place(
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        silhouette: mask,
        sightlines: sightlines,
        random: random,
      );
      if (placement == null) continue;
      // Reject overlaps with already-reserved motifs and over-budget rolls.
      final keys = placement.reservations.map((r) => r.cellKey).toSet();
      if (keys.any(usedCells.contains)) continue;
      if (reservedSoFar + keys.length > maxReservationCells) continue;
      placed.add(placement);
      usedCells.addAll(keys);
      reservedSoFar += keys.length;
    }
    return placed;
  }

  SilhouetteId _pickSilhouette(
    GenerationArchetypeSpec spec,
    Random random,
  ) {
    final pool = spec.preferredSilhouettes;
    return pool[random.nextInt(pool.length)];
  }

  Set<int> _buildOrFallbackMask({
    required SilhouetteId silhouette,
    required LevelConfiguration config,
    required Random random,
  }) {
    final minCells = config.difficulty.minNodes;
    final mask = buildSilhouetteMask(
      id: silhouette,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      random: random,
      minCells: minCells,
    );
    if (mask != null && mask.length >= minCells) return mask;
    onMaskRectangleFallback?.call(silhouette, SilhouetteId.rectangle);
    // Fall back to the full rectangle so the constructor always has room.
    final all = <int>{};
    for (var y = 0; y < config.gridHeight; y++) {
      for (var x = 0; x < config.gridWidth; x++) {
        all.add(gridCellKey(x, y));
      }
    }
    return all;
  }

  int _pickTargetNodeCount({
    required LevelConfiguration config,
    required Set<int> mask,
    required DifficultyTier tier,
    required Random random,
  }) {
    // Phase 3 puts node-count selection inside the §6 band so the Evaluator's
    // ≥ 90% in-band criterion becomes reachable. We honour `minNodes` as a
    // floor (because tests assert it) but otherwise sample uniformly in the
    // intersection of `[bandMin, bandMax]` and `[minNodes, mask.length]`.
    final profile = DifficultyProfile.forTier(tier);
    final lo = max(profile.nodeCount.min, config.difficulty.minNodes);
    final hi = min(profile.nodeCount.max, mask.length);
    if (hi <= lo) return lo.clamp(1, mask.length);
    return lo + random.nextInt(hi - lo + 1);
  }

  /// Phase 5 §9 — motif reservation for [LevelSeed]-driven plans. Honours
  /// `seed.motifMixId` (if set) by trying that motif first; otherwise falls
  /// back to `_reserveMotifs` so the archetype's normal budget applies.
  List<MotifPlacement> _reserveSeededMotifs({
    required LevelSeed seed,
    required GenerationArchetypeSpec spec,
    required LevelConfiguration config,
    required Set<int> mask,
    required int target,
    required Random random,
  }) {
    if (seed.motifMixId == null) {
      return _reserveMotifs(
        spec: spec,
        useLegacyGreedyPath: false,
        config: config,
        mask: mask,
        target: target,
        random: random,
      );
    }
    final sightlines = SightlineTable.forGrid(
      config.gridWidth,
      config.gridHeight,
    );
    Motif? preferred;
    for (final m in motifCatalogue()) {
      if (m.id == seed.motifMixId) {
        preferred = m;
        break;
      }
    }
    if (preferred == null) return const [];
    final maxReservationCells = (target * 0.4).floor();
    if (maxReservationCells < 3) return const [];
    final placement = preferred.place(
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      silhouette: mask,
      sightlines: sightlines,
      random: random,
    );
    if (placement == null) return const [];
    if (placement.reservations.length > maxReservationCells) return const [];
    return [placement];
  }

  /// Maps the legacy [DifficultyMode] to its tier (helper exposed for
  /// callers that don't want to import [DifficultyProfile.tierFromMode]).
  static DifficultyTier tierFromMode(DifficultyMode mode) =>
      DifficultyProfile.tierFromMode(mode);
}
