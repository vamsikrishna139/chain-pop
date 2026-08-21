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
/// was blocked on a generator bug: the `timeBudget` did not bound the seeded
/// Director path, so a high pinned count sent some slots into a pathological
/// search — measured at 66s on slot 750 (with the 9x9 override) and 181s on
/// slot 950 (count only), against a ~210ms baseline.
///
/// **That bound now exists** (2026-08-20): the seeded path runs `timeBudget`
/// on its own stopwatch and passes its own `overBudget` callback into the
/// Director. Pinning the count is therefore worth re-trying — but re-measure,
/// do not assume: a single retrograde construction still cannot be preempted
/// mid-flight, so the budget is a bound on *attempts*, not a hard wall-clock
/// cap (milestone slots measure up to ~356ms against a 200ms budget today).
/// See `milestone_latency_test.dart` (ceiling) and
/// `milestone_seed_audit_test.dart` (funnel + per-slot cost).
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
