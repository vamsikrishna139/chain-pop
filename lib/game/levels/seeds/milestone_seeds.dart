import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/silhouettes.dart';
import '../generation/progression_profile.dart';

const LevelSeed ringMilestoneSeed = LevelSeed(
  id: 'milestone-ring',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  mechanicOverride: MechanicBudgetOverride(portalPairCount: 0),
);

const LevelSeed diamondMilestoneSeed = LevelSeed(
  id: 'milestone-diamond',
  silhouetteId: SilhouetteId.diamond,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  mechanicOverride: MechanicBudgetOverride(portalPairCount: 0),
);

/// KNOWN GAP: this milestone does not currently feel like an "overload". It
/// pins only the silhouette, so every slot inherits the ordinary Hard shape —
/// 25 nodes, sometimes on a *smaller* 7x7 board than its neighbours. Measured
/// across all ten slots: overload avg 25.0 nodes vs ordinary neighbours 25.0.
///
/// The planned fix (`targetNodeCount: 36`, optionally `gridWidth/Height: 9`)
/// is NOT applied because it exposes a generator bug: the `timeBudget` does
/// not bound the seeded Director path, and a high pinned count sends some
/// slots into a pathological search — measured at 66s on slot 750 (with the
/// 9x9 override) and 181s on slot 950 (count only), against a ~210ms baseline.
/// A single attempt runs unbounded, so neither the between-attempts check nor
/// the `overBudget` callback preempts it.
///
/// Fix the latency bound first, then pin the count. See
/// `milestone_latency_test.dart`, which guards the ~2s ceiling.
const LevelSeed milestoneOverloadSeed = LevelSeed(
  id: 'milestone-overload',
  silhouetteId: SilhouetteId.rectangle,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  mechanicOverride: MechanicBudgetOverride(portalPairCount: 0),
);

const LevelSeed milestoneSniperSeed = LevelSeed(
  id: 'milestone-sniper',
  silhouetteId: SilhouetteId.archipelago,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  gridWidth: 10,
  gridHeight: 10,
  mechanicOverride: MechanicBudgetOverride(portalPairCount: 0),
);
