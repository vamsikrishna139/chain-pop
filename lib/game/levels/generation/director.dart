import 'dart:math';

import '../grid_cell_key.dart';
import 'archetype.dart';
import 'candidate_scorer.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_configuration.dart';
import 'level_seed.dart';
import 'motifs.dart';
import 'sightline_table.dart';
import 'silhouettes.dart';

/// Dense silhouettes favoured by the Phase 1C bias for Hard/Expert tiers.
/// These shapes produce tight boards with minimal dead canvas space.
const List<SilhouetteId> _denseSilhouettes = [
  SilhouetteId.ring,
  SilhouetteId.cross,
  SilhouetteId.diamond,
  SilhouetteId.rectangle,
];

/// Silhouettes demoted under Phase 1C bias — they tend toward sparse layouts.
const List<SilhouetteId> _sparseSilhouettes = [
  SilhouetteId.archipelago,
  SilhouetteId.organicBlob,
];

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
    GenerationArchetype? overrideArchetype,
  }) {
    final tier =
        overrideTier ?? DifficultyProfile.tierFromMode(config.difficulty.mode);
    final archetype = overrideArchetype ?? GenerationArchetypeSpec.sampleForTier(random, tier);
    // Dense Strategy Phase 1B: clamp isolation penalty + temperature for
    // Hard/Expert so high-isolation or high-temperature archetypes don't
    // produce sparse boards.
    var spec = GenerationArchetypeSpec.forArchetype(archetype);
    spec = _applyDensityOverrides(spec, tier);
    final useLegacy = archetype == GenerationArchetype.experimental &&
        random.nextDouble() < spec.legacyGreedyProbability;
    final silhouette = _pickSilhouette(spec, random, tier: tier);
    final mask = _buildOrFallbackMask(
      silhouette: silhouette,
      config: config,
      random: random,
    );
    final profile = DifficultyProfile.forTier(tier);
    final target = _pickTargetNodeCount(
      config: config,
      mask: mask,
      tier: tier,
      random: random,
    );
    final motifs = _reserveMotifs(
      spec: spec,
      tier: tier,
      useLegacyGreedyPath: useLegacy,
      config: config,
      mask: mask,
      target: target,
      random: random,
    );
    var plan = GenerationPlan(
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
    plan = _refinePlanMaskDensity(plan, config, random);
    return plan;
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
      tier: previous.tier,
      useLegacyGreedyPath: previous.useLegacyGreedyPath,
      config: config,
      mask: nextMask,
      target: downscaled,
      random: random,
    );
    var plan = previous.copyWith(
      silhouette: nextSilhouette,
      silhouetteMask: nextMask,
      targetNodeCount: downscaled,
      renegotiationDepth: previous.renegotiationDepth + 1,
      motifs: remappedMotifs,
    );
    return _refinePlanMaskDensity(plan, config, random);
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
      tier: previous.tier,
      useLegacyGreedyPath: previous.useLegacyGreedyPath,
      config: config,
      mask: nextMask,
      target: downscaled,
      random: random,
    );
    var plan = previous.copyWith(
      silhouette: nextSilhouette,
      silhouetteMask: nextMask,
      targetNodeCount: downscaled,
      renegotiationDepth: previous.renegotiationDepth + 1,
      motifs: remappedMotifs,
    );
    return _refinePlanMaskDensity(plan, config, random);
  }

  /// §4.6 — picks the per-attempt motif count (`1..motifBudget`) and tries to
  /// place them on the current silhouette. Returns an empty list when the
  /// archetype has no budget, the level is too small, or every roll failed.
  List<MotifPlacement> _reserveMotifs({
    required GenerationArchetypeSpec spec,
    required DifficultyTier tier,
    required bool useLegacyGreedyPath,
    required LevelConfiguration config,
    required Set<int> mask,
    required int target,
    required Random random,
  }) {
    if (useLegacyGreedyPath) return const [];
    final maxReservationCells = (target * 0.4).floor();
    if (maxReservationCells < 3) return const [];

    final sightlines = SightlineTable.forGrid(
      config.gridWidth,
      config.gridHeight,
    );

    final placed = <MotifPlacement>[];
    final usedCells = <int>{};
    var reservedSoFar = 0;
    final isDenseTier =
        tier == DifficultyTier.hard || tier == DifficultyTier.expert;

    bool tryPlace(Motif motif) {
      final placement = motif.place(
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        silhouette: mask,
        sightlines: sightlines,
        random: random,
      );
      if (placement == null) return false;
      final keys = placement.reservations.map((r) => r.cellKey).toSet();
      if (keys.any(usedCells.contains)) return false;
      if (reservedSoFar + keys.length > maxReservationCells) return false;
      placed.add(placement);
      usedCells.addAll(keys);
      reservedSoFar += keys.length;
      return true;
    }

    // Phase 2B: Hard/Expert attempts cascade hub first ~45% of the time.
    if (isDenseTier && random.nextDouble() < 0.45) {
      final cascadeHub = motifById(MotifId.cascadeHub);
      if (cascadeHub != null) {
        tryPlace(cascadeHub);
      }
    }

    if (spec.motifBudget <= 0) return placed;

    final desiredTotal = isDenseTier
        ? max(placed.length + 1, 1 + random.nextInt(spec.motifBudget))
        : 1 + random.nextInt(spec.motifBudget);

    var attempts = 0;
    while (placed.length < desiredTotal && attempts < desiredTotal * 8) {
      attempts++;
      final hasLockCluster =
          placed.any((p) => p.id == MotifId.lockCluster);
      final motif = sampleMotifForTier(
        tier,
        random,
        excludeLockCluster: hasLockCluster,
      );
      tryPlace(motif);
    }
    return placed;
  }

  /// Phase 1C — when mask area exceeds 1.15× target, prefer a tighter dense
  /// silhouette so Hard/Expert boards avoid large voids.
  GenerationPlan _refinePlanMaskDensity(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random,
  ) {
    if (plan.tier != DifficultyTier.hard &&
        plan.tier != DifficultyTier.expert) {
      return plan;
    }
    final maxArea = (plan.targetNodeCount * 1.15).ceil();
    if (plan.silhouetteMask.length <= maxArea) return plan;

    for (final sid in _denseSilhouettes) {
      if (sid == plan.silhouette) continue;
      final mask = _buildOrFallbackMask(
        silhouette: sid,
        config: config,
        random: random,
      );
      if (mask.length <= maxArea && mask.length >= plan.targetNodeCount) {
        final remapped = _reserveMotifs(
          spec: plan.spec,
          tier: plan.tier,
          useLegacyGreedyPath: plan.useLegacyGreedyPath,
          config: config,
          mask: mask,
          target: plan.targetNodeCount,
          random: random,
        );
        return plan.copyWith(
          silhouette: sid,
          silhouetteMask: mask,
          motifs: remapped,
        );
      }
    }
    return plan;
  }

  SilhouetteId _pickSilhouette(
    GenerationArchetypeSpec spec,
    Random random, {
    DifficultyTier? tier,
  }) {
    final pool = spec.preferredSilhouettes;
    // Dense Strategy Phase 1C: for Hard/Expert, bias 70% toward dense
    // silhouettes and demote sparse ones (Archipelago, Organic Blob).
    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      final denseInPool =
          pool.where((s) => _denseSilhouettes.contains(s)).toList();
      if (denseInPool.isNotEmpty && random.nextDouble() < 0.70) {
        return denseInPool[random.nextInt(denseInPool.length)];
      }
      // If the 30% non-dense roll fires, pick from non-sparse entries first.
      final nonSparse =
          pool.where((s) => !_sparseSilhouettes.contains(s)).toList();
      if (nonSparse.isNotEmpty) {
        return nonSparse[random.nextInt(nonSparse.length)];
      }
    }
    return pool[random.nextInt(pool.length)];
  }

  /// Dense Strategy Phase 1B: for Hard/Expert tiers, clamp isolation penalty
  /// to 0.5 (prevents high-isolation archetypes from carving sparse voids)
  /// and cap temperature at 1.0 (prevents Organic Messy's 1.6 from exploding
  /// into sparse chaos).
  static GenerationArchetypeSpec _applyDensityOverrides(
    GenerationArchetypeSpec spec,
    DifficultyTier tier,
  ) {
    if (tier != DifficultyTier.hard && tier != DifficultyTier.expert) {
      return spec;
    }
    final w = spec.scorerWeights;
    final clampedIsolation =
        w.isolationPenalty > 0.5 ? 0.5 : w.isolationPenalty;
    final clampedTemp = w.temperature > 1.0 ? 1.0 : w.temperature;
    if (clampedIsolation == w.isolationPenalty &&
        clampedTemp == w.temperature) {
      return spec; // no change needed
    }
    return GenerationArchetypeSpec(
      kind: spec.kind,
      scorerWeights: w.copyWith(
        isolationPenalty: clampedIsolation,
        temperature: clampedTemp,
      ),
      motifBudget: spec.motifBudget,
      preferredSilhouettes: spec.preferredSilhouettes,
      legacyGreedyProbability: spec.legacyGreedyProbability,
    );
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
    final profile = DifficultyProfile.forTier(tier);
    final lo = max(profile.nodeCount.min, config.difficulty.minNodes);
    final hi = min(profile.nodeCount.max, mask.length);

      // Dense Strategy: Hard/Expert target 28–40% silhouette fill.
      // Fixes sparse boards when the mask has many more cells
      // than the old 20–30 node cap allowed.
      if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
        // Small masks / opening seeds: `lo` (minNodes) can exceed `hi`.
        if (hi <= lo) return hi.clamp(1, mask.length);
        final fillRatio = 0.28 + random.nextDouble() * 0.12;
        final densityTarget = (mask.length * fillRatio).round();
        return densityTarget.clamp(lo, hi);
      }

    // Easy/Medium: sample uniformly in the §6 node-count band.
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
    final isDenseTier =
        seed.difficultyTier == DifficultyTier.hard ||
        seed.difficultyTier == DifficultyTier.expert;
    if (seed.motifMixId == null) {
      return _reserveMotifs(
        spec: spec,
        tier: seed.difficultyTier,
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
    final preferred = motifById(seed.motifMixId!);
    if (preferred == null) {
      return isDenseTier
          ? _reserveMotifs(
              spec: spec,
              tier: seed.difficultyTier,
              useLegacyGreedyPath: false,
              config: config,
              mask: mask,
              target: target,
              random: random,
            )
          : const [];
    }
    final maxReservationCells = (target * 0.4).floor();
    if (maxReservationCells < 3) return const [];

    final placed = <MotifPlacement>[];
    final usedCells = <int>{};
    var reservedSoFar = 0;

    bool tryPlace(Motif motif) {
      final placement = motif.place(
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        silhouette: mask,
        sightlines: sightlines,
        random: random,
      );
      if (placement == null) return false;
      if (placement.reservations.length > maxReservationCells) return false;
      final keys = placement.reservations.map((r) => r.cellKey).toSet();
      if (keys.any(usedCells.contains)) return false;
      if (reservedSoFar + keys.length > maxReservationCells) return false;
      placed.add(placement);
      usedCells.addAll(keys);
      reservedSoFar += keys.length;
      return true;
    }

    if (isDenseTier) {
      final cascadeHub = motifById(MotifId.cascadeHub);
      if (cascadeHub != null) {
        tryPlace(cascadeHub);
      }
    }
    if (!placed.any((p) => p.id == seed.motifMixId)) {
      tryPlace(preferred);
    }
    return placed;
  }

  /// Maps the legacy [DifficultyMode] to its tier (helper exposed for
  /// callers that don't want to import [DifficultyProfile.tierFromMode]).
  static DifficultyTier tierFromMode(DifficultyMode mode) =>
      DifficultyProfile.tierFromMode(mode);
}
