import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/motifs.dart';
import '../generation/silhouettes.dart';

/// Hand-authored showcase / boss moments — pinned seeds for memorable levels.
const Map<int, LevelSeed> showcaseLevelSeeds = {
  30: LevelSeed(
    id: 'showcase-first-fork',
    silhouetteId: SilhouetteId.asymmetric,
    archetypeId: GenerationArchetype.cleanAuthored,
    difficultyTier: DifficultyTier.hard,
    seedRng: 3001,
  ),
  35: LevelSeed(
    id: 'showcase-spiral',
    silhouetteId: SilhouetteId.organicBlob,
    archetypeId: GenerationArchetype.organicMessy,
    difficultyTier: DifficultyTier.hard,
    seedRng: 3501,
  ),
  40: LevelSeed(
    id: 'showcase-vault',
    silhouetteId: SilhouetteId.ring,
    archetypeId: GenerationArchetype.strongMotif,
    difficultyTier: DifficultyTier.hard,
    motifMixId: MotifId.lockCluster,
    seedRng: 4001,
  ),
  45: LevelSeed(
    id: 'showcase-seal-breaker',
    silhouetteId: SilhouetteId.diamond,
    archetypeId: GenerationArchetype.cleanAuthored,
    difficultyTier: DifficultyTier.hard,
    motifMixId: MotifId.lockCluster,
    seedRng: 4501,
  ),
  50: LevelSeed(
    id: 'showcase-boss-gridlock',
    silhouetteId: SilhouetteId.asymmetric,
    archetypeId: GenerationArchetype.strongMotif,
    difficultyTier: DifficultyTier.hard,
    seedRng: 5001,
  ),
  55: LevelSeed(
    id: 'showcase-phase-shift',
    silhouetteId: SilhouetteId.corridor,
    archetypeId: GenerationArchetype.cleanAuthored,
    difficultyTier: DifficultyTier.hard,
    seedRng: 5501,
  ),
  75: LevelSeed(
    id: 'showcase-boss-overload',
    silhouetteId: SilhouetteId.archipelago,
    archetypeId: GenerationArchetype.organicMessy,
    difficultyTier: DifficultyTier.hard,
    seedRng: 7501,
  ),
  100: LevelSeed(
    id: 'showcase-boss-blackout',
    silhouetteId: SilhouetteId.asymmetric,
    archetypeId: GenerationArchetype.experimental,
    difficultyTier: DifficultyTier.hard,
    seedRng: 10001,
  ),
};
