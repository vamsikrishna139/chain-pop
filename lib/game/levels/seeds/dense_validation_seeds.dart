import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/silhouettes.dart';

/// Dense Strategy Phase 1E — 10 quick-win validation seeds.
///
/// Ring silhouette, 75% fill, low isolation (0.4 via Clean Authored base +
/// Director density override clamp). These exercise the tightest "full board"
/// scenario and are wired into [denseValidationSeedOverrides] for
/// dev-only play-testing.
///
/// To activate: set `useDenseValidationSeeds = true` in
/// [seed_registry.dart] (or pass a flag through your dev build).

/// Maps campaign level IDs 30–39 to dense validation seeds.
/// Only consulted when [useDenseValidationSeeds] is true.
const Map<int, LevelSeed> denseValidationSeedOverrides = {
  30: _denseRingSeed30,
  31: _denseRingSeed31,
  32: _denseRingSeed32,
  33: _denseRingSeed33,
  34: _denseRingSeed34,
  35: _denseCrossSeed35,
  36: _denseDiamondSeed36,
  37: _denseRingSeed37,
  38: _denseRectSeed38,
  39: _denseRingSeed39,
};

const _denseRingSeed30 = LevelSeed(
  id: 'dense-ring-30',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 22,
);

const _denseRingSeed31 = LevelSeed(
  id: 'dense-ring-31',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.strongMotif,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 24,
);

const _denseRingSeed32 = LevelSeed(
  id: 'dense-ring-32',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 25,
);

const _denseRingSeed33 = LevelSeed(
  id: 'dense-ring-33',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.organicMessy,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 23,
);

const _denseRingSeed34 = LevelSeed(
  id: 'dense-ring-34',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.strongMotif,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 26,
);

// Levels 35–36: exercise Cross and Diamond to confirm Phase 1C bias.
const _denseCrossSeed35 = LevelSeed(
  id: 'dense-cross-35',
  silhouetteId: SilhouetteId.cross,
  archetypeId: GenerationArchetype.strongMotif,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 22,
);

const _denseDiamondSeed36 = LevelSeed(
  id: 'dense-diamond-36',
  silhouetteId: SilhouetteId.diamond,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 24,
);

const _denseRingSeed37 = LevelSeed(
  id: 'dense-ring-37',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.strongMotif,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 27,
);

const _denseRectSeed38 = LevelSeed(
  id: 'dense-rect-38',
  silhouetteId: SilhouetteId.rectangle,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 28,
);

const _denseRingSeed39 = LevelSeed(
  id: 'dense-ring-39',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.strongMotif,
  difficultyTier: DifficultyTier.hard,
  targetNodeCount: 25,
);
