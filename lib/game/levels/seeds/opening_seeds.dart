import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/silhouettes.dart';

/// First-three levels — pinned to clean, low-pressure layouts so the new
/// player sees a tightly authored opening before the Director starts mixing
/// in organic / motif archetypes.
const LevelSeed openingSeedLevel1 = LevelSeed(
  id: 'opening-1',
  silhouetteId: SilhouetteId.rectangle,
  archetypeId: GenerationArchetype.relaxedFreeFlow,
  difficultyTier: DifficultyTier.easy,
  targetNodeCount: null,
  seedRng: 0xA1,
);

const LevelSeed openingSeedLevel2 = LevelSeed(
  id: 'opening-2',
  silhouetteId: SilhouetteId.rectangle,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.easy,
  targetNodeCount: null,
  seedRng: 0xB2,
);

const LevelSeed openingSeedLevel3 = LevelSeed(
  id: 'opening-3',
  silhouetteId: SilhouetteId.cross,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.easy,
  targetNodeCount: null,
  seedRng: 0xC3,
);
