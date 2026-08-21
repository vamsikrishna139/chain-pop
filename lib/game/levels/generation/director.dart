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

/// T2.2 — the mask cell floor, as a fraction of the tier's node-band floor.
///
/// **Held at 1.0. T2.2's specified change is a no-go, on measurement — but the
/// base it multiplies did change; see `_buildOrFallbackMask`.**
///
/// The plan proposed `max(8, (minNodes * 0.6).round())` — 15 on Hard — on the
/// grounds that "the mask only needs room for the target, and
/// `_pickTargetNodeCount` already clamps `hi = min(profile.nodeCount.max,
/// mask.length)`". The premise is true and the conclusion does not follow, for
/// the third time in this plan: that clamp does not *reject* an undersized
/// mask, it silently lowers the target through the floor. `lo` is
/// `max(profile.nodeCount.min, minNodes) = 25` on Hard, and when `hi <= lo` the
/// routine returns `hi` — the mask size — not `lo`.
///
/// Measured over Hard L1-200 at 0.6: **34 of 200 levels shipped under the
/// 25-node floor**, down to 15 nodes, on masks as small as 16 cells. At 1.0 it
/// is 200/200 at 25 or above. Hard's node floor is load-bearing for the
/// evaluator's FSR-vs-nodeCount cap and the per-level perf budget, so this is
/// not a floor a mask-geometry task gets to move as a side effect.
///
/// The variety 0.6 bought was real but small next to that: lattice share
/// 72.2% -> 69.2%, Hard L45-56 rect boards 4 -> 2, Hard topology classes
/// 38 -> 33 (i.e. *worse*), all measured with T2.1 and T2.3 already in.
/// T2.1 and T2.3 deliver the P2 variety targets without it.
///
/// **The underlying complaint is still valid** — `diamond` and `hollowDiamond`
/// genuinely lose rolls to this floor (measured medians at 8x8: diamond 29,
/// hollowDiamond 24, against a floor of 25). The fix that does not touch the
/// node floor is to bias those two builders' jitter ranges toward area
/// preservation, exactly as T2.1 already did for `_pentagonCells` and
/// `_spiralCells`. That is a separate, seed-moving task; it is not this one.
///
/// Kept as a named constant rather than reverted to a bare expression so the
/// experiment is re-runnable: set it to 0.6 and the report in
/// `p2_variety_report_test.dart` reproduces the numbers above.
const double kMaskCellFloorRatio = 1.0;

/// T2.3 — how much larger than the target node count a silhouette mask may be
/// before [Director._refinePlanMaskDensity] swaps it for a dense one.
///
/// Was a bare `1.15` literal. At that value a Hard board targeting 25 nodes was
/// allowed a 29-cell mask, which almost nothing except a rectangle, a ring or a
/// cross can be at 8x8 — so the clamp fired constantly and substituted, and it
/// is the direct cause of the 73% geometric-lattice share measured in
/// `docs/playtests/p2_variety_pre_bundle.md`.
///
/// Named rather than inlined **so it can be bisected**: it is the single knob
/// that trades silhouette variety against the Dense Strategy Phase 1C symptom
/// (sparse Hard boards with large voids), and if `bboxOccupancy` /
/// `largestEmptyRegion` regress this is the first value to walk back.
const double kMaskAreaSlack = 1.5;

/// T2.3 — archetypes whose whole point is an irregular outline, and which the
/// density clamp therefore must not silhouette-substitute.
///
/// Substituting here is self-defeating: the archetype was *chosen* to produce
/// an organic or sparse board, and swapping its mask for a ring or a rectangle
/// discards the choice while keeping the archetype's scorer weights, which
/// yields the worst of both. The clamp still applies to every other archetype.
const Set<GenerationArchetype> _organicArchetypes = {
  GenerationArchetype.organicMessy,
};

/// Dense silhouettes favoured by the Phase 1C bias for Hard/Expert tiers.
/// These shapes produce tight boards with minimal dead canvas space.
const List<SilhouetteId> _denseSilhouettes = [
  SilhouetteId.ring,
  SilhouetteId.cross,
  SilhouetteId.diamond,
  SilhouetteId.rectangle,
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

  /// True when this plan came from a hand-authored [LevelSeed], whose whole
  /// point is the silhouette it pins. [Director.renegotiate] swaps silhouette
  /// on odd depths to escape starvation, which for a seeded plan quietly
  /// destroys the thing the seed exists to deliver: a milestone could ship as
  /// some other shape and still be counted as that seed's emission.
  /// Renegotiation still runs for pinned plans — it just escapes by shrinking
  /// the node count and re-rolling motifs, never by changing what the board
  /// looks like.
  final bool pinnedSilhouette;

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
    this.pinnedSilhouette = false,
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
    bool? pinnedSilhouette,
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
      pinnedSilhouette: pinnedSilhouette ?? this.pinnedSilhouette,
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
      minCells: _proceduralMaskFloor(tier, config),
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
    // Hand-authored seeds pin a deliberate silhouette; honour the canonical
    // rendering (no shape-pool variety) so the showcase looks as designed and
    // the seed's RNG stream stays byte-stable.
    final mask = _buildOrFallbackMask(
      silhouette: seed.silhouetteId,
      config: config,
      random: random,
      // Deliberately the OLD floor, not [_proceduralMaskFloor].
      //
      // A seed carries its own `difficultyTier` for showcase purposes and it
      // need not match the mode the slot ships on: `milestone-diamond` is a
      // Hard-tier seed emitted on Medium campaign slots. Flooring by the seed's
      // tier would demand 25 cells of a Medium 8x8 diamond that has ~24, and
      // measured, that is not hypothetical — it collapsed slots 325, 625, 825
      // and 925 to the rectangle fallback and took `milestone_identity_test`
      // red.
      //
      // The seeded path also does not have the defect the procedural floor was
      // raised to fix: it clamps `target.clamp(1, mask.length)` itself a few
      // lines below, so an undersized mask cannot push a board out of band
      // here. Milestone boards must not move, and this keeps them still.
      minCells: config.difficulty.minNodes,
      varied: false,
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
      pinnedSilhouette: true,
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
    // starvation rather than just shrinking node count. Seeded plans are
    // exempt: the silhouette *is* the seed, so escaping starvation by
    // abandoning it trades the milestone away to save the attempt. They keep
    // the node-count downscale and the motif re-roll below, which are escapes
    // that leave the landmark intact — and skipping the swap also spares a
    // mask rebuild.
    if (previous.renegotiationDepth.isOdd && !previous.pinnedSilhouette) {
      final candidates = previous.spec.preferredSilhouettes
          .where((s) => s != previous.silhouette)
          .toList();
      if (candidates.isNotEmpty) {
        nextSilhouette = candidates[random.nextInt(candidates.length)];
        nextMask = _buildOrFallbackMask(
          silhouette: nextSilhouette,
          config: config,
          random: random,
          minCells: _proceduralMaskFloor(previous.tier, config),
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
    // After relaxing density, every other renegotiation swaps silhouette —
    // except for seeded plans, for the reason given in [renegotiate].
    if (previous.renegotiationDepth.isOdd && !previous.pinnedSilhouette) {
      final candidates = previous.spec.preferredSilhouettes
          .where((s) => s != previous.silhouette)
          .toList();
      if (candidates.isNotEmpty) {
        nextSilhouette = candidates[random.nextInt(candidates.length)];
        nextMask = _buildOrFallbackMask(
          silhouette: nextSilhouette,
          config: config,
          random: random,
          minCells: _proceduralMaskFloor(previous.tier, config),
        );
        downscaled = downscaled.clamp(1, nextMask.length);
      }
    } else {
      nextMask = _buildOrFallbackMask(
        silhouette: nextSilhouette,
        config: config,
        random: random,
        // A pinned silhouette means this renegotiation is continuing a seeded
        // plan, so it inherits that path's floor rather than the procedural one.
        minCells: previous.pinnedSilhouette
            ? config.difficulty.minNodes
            : _proceduralMaskFloor(previous.tier, config),
        // Seeds pin the canonical rendering (`choosePlanFromSeed` builds with
        // `varied: false`); re-rolling shape variety here would drift the
        // authored look and the seed's RNG stream along with it.
        varied: !previous.pinnedSilhouette,
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

  /// Phase 1C — when mask area exceeds [kMaskAreaSlack]x target, prefer a
  /// tighter dense silhouette so Hard/Expert boards avoid large voids.
  ///
  /// T2.3 loosened the slack from a hardcoded 1.15 and exempted the organic
  /// archetypes. Both halves attack the same thing: this routine silently
  /// discards the silhouette the Director just chose, and at 1.15 it did so
  /// often enough to be the dominant source of Hard's lattice share.
  GenerationPlan _refinePlanMaskDensity(
    GenerationPlan plan,
    LevelConfiguration config,
    Random random,
  ) {
    if (plan.tier != DifficultyTier.hard &&
        plan.tier != DifficultyTier.expert) {
      return plan;
    }
    if (_organicArchetypes.contains(plan.archetype)) return plan;
    final maxArea = (plan.targetNodeCount * kMaskAreaSlack).ceil();
    if (plan.silhouetteMask.length <= maxArea) return plan;

    for (final sid in _denseSilhouettes) {
      if (sid == plan.silhouette) continue;
      final mask = _buildOrFallbackMask(
        silhouette: sid,
        config: config,
        random: random,
        minCells: _proceduralMaskFloor(plan.tier, config),
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
    // Dense Strategy Phase 1C: for Hard/Expert, bias 40% toward dense
    // silhouettes to keep structured tension, but allow full variety.
    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      final denseInPool =
          pool.where((s) => _denseSilhouettes.contains(s)).toList();
      if (denseInPool.isNotEmpty && random.nextDouble() < 0.40) {
        return denseInPool[random.nextInt(denseInPool.length)];
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

  /// Cells a procedural mask must have to seat the tier's node band.
  ///
  /// T2.2, as the measurements actually left it — and note the correction runs
  /// **opposite** to the direction the plan proposed.
  ///
  /// The floor used to be `config.difficulty.minNodes`. That is not what a
  /// board needs: `_pickTargetNodeCount` floors the target at
  /// `lo = max(profile.nodeCount.min, difficulty.minNodes)`, and on Medium
  /// those differ — `minNodes` is 10 while the profile band starts at 14. A
  /// mask of 10..13 cells therefore passed the floor and then produced a board
  /// *below its own difficulty band*, because when `hi <= lo` that routine
  /// returns `hi`, i.e. the mask size.
  ///
  /// Latent until T2.1: masks that small were barely reachable before jitter
  /// reached the nine builders that had been dropping it. Afterwards
  /// **L194/medium shipped 13 nodes and was won in 3 taps**, taking
  /// `core_triviality_test`'s F1 gate red — the gate P1 exists to hold, and the
  /// only P1 result this bundle disturbed.
  ///
  /// Flooring at the same `lo` the target computation uses closes it by
  /// construction. Medium's floor rises 10 -> 14 and Easy's 4 -> 8; Hard is
  /// unchanged at 25.
  ///
  /// This is the honest version of "decouple `minCells` from `minNodes`": the
  /// plan wanted the floor *lowered* to buy silhouette variety, and measurement
  /// says the coupling was wrong in the other direction. Lowering it further
  /// (`kMaskCellFloorRatio: 0.6`) broke Hard's node floor on 34 of 200 levels.
  ///
  /// **Seeded plans do not use this** — see the call site in
  /// `choosePlanFromSeed`.
  int _proceduralMaskFloor(DifficultyTier tier, LevelConfiguration config) {
    final tierFloor = max(
      DifficultyProfile.forTier(tier).nodeCount.min,
      config.difficulty.minNodes,
    );
    return max(8, (tierFloor * kMaskCellFloorRatio).round());
  }

  Set<int> _buildOrFallbackMask({
    required SilhouetteId silhouette,
    required LevelConfiguration config,
    required Random random,
    required int minCells,
    bool varied = true,
  }) {
    final mask = buildSilhouetteMask(
      id: silhouette,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      random: random,
      minCells: minCells,
      varied: varied,
      // Level-isolated jitter seed (procedural path only). +1 so level 0 still
      // jitters; does not consume from `random`, so the stream is unchanged.
      jitterSeed: varied ? config.levelId + 1 : 0,
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

      if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
        if (hi <= lo) return hi.clamp(1, mask.length);
        final fillRatio = 0.32 + random.nextDouble() * 0.12;
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
