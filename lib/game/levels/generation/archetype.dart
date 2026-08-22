import 'dart:math';

import 'candidate_scorer.dart';
import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'silhouettes.dart';

/// The five generation archetypes from §5. The Director samples one per
/// level from [GenerationArchetypeSpec.distribution]; this is what protects
/// emergence and prevents the generator from feeling sterile.
///
/// Distinct from the legacy `LevelArchetype` enum (which controls
/// grid-shape biases in `LevelConfiguration`). The two can co-exist.
enum GenerationArchetype {
  /// 25% — symmetric, readable, "designed"-feeling. Tight composition score,
  /// low scorer temperature, high aesthetic bias.
  cleanAuthored,

  /// 35% — asymmetric, blob-like, alive. High scorer temperature, relaxed
  /// composition threshold, no motif reservation.
  organicMessy,

  /// 20% — built around a recognisable Motif Transaction (Phase 4 wires the
  /// actual reservation; Phase 3 spec just records the intent).
  strongMotif,

  /// 15% — easy, open, low-pressure. Wide BF target, no motif, minimal
  /// aesthetic bias.
  relaxedFreeFlow,

  /// 5% — legacy greedy path OR retrograde with inverted scorer weights.
  /// Preserves "happy accidents" the optimised path never picks.
  experimental,
}

/// Bundle of per-archetype knobs the Director hands to the constructor.
class GenerationArchetypeSpec {
  final GenerationArchetype kind;
  final ScorerWeights scorerWeights;

  /// Number of Motif Transaction Blocks the Director may pre-reserve. Always
  /// 0 in Phase 3; Phase 4 wires the actual reservation.
  final int motifBudget;

  /// Silhouette IDs preferred for this archetype (sampled uniformly from this
  /// list). The Director may swap to another silhouette during renegotiation.
  final List<SilhouetteId> preferredSilhouettes;

  /// Probability that an Experimental-archetype roll picks the legacy greedy
  /// path (§5). Set to 0 for non-Experimental archetypes.
  final double legacyGreedyProbability;

  const GenerationArchetypeSpec({
    required this.kind,
    required this.scorerWeights,
    required this.motifBudget,
    required this.preferredSilhouettes,
    this.legacyGreedyProbability = 0.0,
  });

  /// §5 distribution (Medium baseline). Sums to 1.0.
  static const Map<GenerationArchetype, double> distribution = {
    GenerationArchetype.cleanAuthored: 0.25,
    GenerationArchetype.organicMessy: 0.35,
    GenerationArchetype.strongMotif: 0.20,
    GenerationArchetype.relaxedFreeFlow: 0.15,
    GenerationArchetype.experimental: 0.05,
  };

  /// Per-[DifficultyMode] archetype weights. Hard shifts mass off
  /// [GenerationArchetype.cleanAuthored] toward organic / relaxed /
  /// experimental so later peaks feel less "authored-rinse-repeat".
  static Map<GenerationArchetype, double> distributionForDifficulty(
    DifficultyMode mode,
  ) {
    switch (mode) {
      case DifficultyMode.easy:
        return const {
          GenerationArchetype.cleanAuthored: 0.30,
          GenerationArchetype.organicMessy: 0.22,
          GenerationArchetype.strongMotif: 0.12,
          GenerationArchetype.relaxedFreeFlow: 0.31,
          GenerationArchetype.experimental: 0.05,
        };
      case DifficultyMode.medium:
        return distribution;
      case DifficultyMode.hard:
        // Dense Strategy Phase 1A: zero Relaxed Free Flow (root cause of
        // sparse Hard boards), shift mass to Strong Motif + Clean Authored
        // for structured tension.
        return const {
          GenerationArchetype.cleanAuthored: 0.22,
          GenerationArchetype.organicMessy: 0.30,
          GenerationArchetype.strongMotif: 0.40,
          GenerationArchetype.relaxedFreeFlow: 0.00,
          GenerationArchetype.experimental: 0.08,
        };
    }
  }

  /// Per-[DifficultyTier] archetype weights. Expert mirrors Hard for Daily.
  static Map<GenerationArchetype, double> distributionForTier(
    DifficultyTier tier,
  ) {
    switch (tier) {
      case DifficultyTier.easy:
        return distributionForDifficulty(DifficultyMode.easy);
      case DifficultyTier.medium:
        return distributionForDifficulty(DifficultyMode.medium);
      case DifficultyTier.hard:
      case DifficultyTier.expert:
        return distributionForDifficulty(DifficultyMode.hard);
    }
  }

  /// Samples an archetype using [distributionForDifficulty] ([mode]).
  static GenerationArchetype sample(Random random, DifficultyMode mode) {
    return sampleForTier(random, DifficultyProfile.tierFromMode(mode));
  }

  /// Samples an archetype using [distributionForTier] ([tier]).
  static GenerationArchetype sampleForTier(Random random, DifficultyTier tier) {
    final dist = distributionForTier(tier);
    final r = random.nextDouble();
    var cumulative = 0.0;
    for (final entry in dist.entries) {
      cumulative += entry.value;
      if (r < cumulative) return entry.key;
    }
    return dist.keys.last;
  }

  /// Specifications per archetype. The scorer-weight choices follow §4.3 /
  /// §5: cleanAuthored = low temp, strong unlock/aesthetic; organicMessy =
  /// high temp, flat weights; experimental = inverted unlock.
  static GenerationArchetypeSpec forArchetype(GenerationArchetype a) {
    switch (a) {
      case GenerationArchetype.cleanAuthored:
        return const GenerationArchetypeSpec(
          kind: GenerationArchetype.cleanAuthored,
          scorerWeights: ScorerWeights(
            unlockFanout: 1.4,
            mrvBonus: 0.8,
            isolationPenalty: 1.6,
            temperature: 0.55,
          ),
          motifBudget: 0,
          preferredSilhouettes: [
            SilhouetteId.rectangle,
            SilhouetteId.diamond,
            SilhouetteId.cross,
            SilhouetteId.ring,
          ],
        );
      case GenerationArchetype.organicMessy:
        return const GenerationArchetypeSpec(
          kind: GenerationArchetype.organicMessy,
          scorerWeights: ScorerWeights(
            unlockFanout: 0.9,
            mrvBonus: 0.4,
            isolationPenalty: 0.9,
            temperature: 1.6,
          ),
          motifBudget: 0,
          // P2b T2.12: `rectangle` purged. It was the ONLY member of this pool
          // that intersects `_denseSilhouettes`, so the Hard/Expert 40% dense
          // coin-flip in `Director._pickSilhouette` resolved to rectangle
          // 100% of the times it fired — making a nominally organic archetype
          // request lattice 54.5% of the time (measured). With no dense member
          // the branch cannot fire at all and this pool is purely organic.
          preferredSilhouettes: [
            SilhouetteId.organicBlob,
            SilhouetteId.archipelago,
            SilhouetteId.asymmetric,
          ],
        );
      case GenerationArchetype.strongMotif:
        // Dense Strategy Phase 1C: Strong Motif now favours dense geometric
        // silhouettes (Ring, Cross, Diamond, Rectangle) so motif crunch
        // zones sit inside tight boards rather than sparse organic shapes.
        return const GenerationArchetypeSpec(
          kind: GenerationArchetype.strongMotif,
          scorerWeights: ScorerWeights(
            unlockFanout: 1.1,
            mrvBonus: 0.6,
            isolationPenalty: 1.3,
            temperature: 0.9,
          ),
          // Phase 4: reserve 1–2 Motif Transactions per Strong-Motif level.
          // The Director rolls the actual count from `[1, 2]` per attempt.
          motifBudget: 2,
          preferredSilhouettes: [
            SilhouetteId.ring,
            SilhouetteId.cross,
            SilhouetteId.diamond,
            SilhouetteId.rectangle,
            SilhouetteId.corridor,
          ],
        );
      case GenerationArchetype.relaxedFreeFlow:
        return const GenerationArchetypeSpec(
          kind: GenerationArchetype.relaxedFreeFlow,
          scorerWeights: ScorerWeights(
            unlockFanout: 1.0,
            mrvBonus: 0.3,
            isolationPenalty: 0.7,
            temperature: 1.2,
          ),
          motifBudget: 0,
          preferredSilhouettes: [
            SilhouetteId.rectangle,
            SilhouetteId.organicBlob,
            SilhouetteId.corridor,
          ],
        );
      case GenerationArchetype.experimental:
        return const GenerationArchetypeSpec(
          kind: GenerationArchetype.experimental,
          // Inverted unlock + high temperature → surprising layouts.
          scorerWeights: ScorerWeights(
            unlockFanout: -0.4,
            mrvBonus: 0.2,
            isolationPenalty: 0.2,
            temperature: 2.0,
          ),
          motifBudget: 0,
          // P2b T2.12: `rectangle` purged — same dense-pool pollution as
          // organicMessy (measured 57.9% lattice from a pool of three
          // non-lattice shapes plus rectangle).
          preferredSilhouettes: [
            SilhouetteId.archipelago,
            SilhouetteId.asymmetric,
            SilhouetteId.corridor,
          ],
          // 50% chance an Experimental roll uses the legacy greedy path
          // (preserves emergence as §5 demands).
          legacyGreedyProbability: 0.5,
        );
    }
  }
}
