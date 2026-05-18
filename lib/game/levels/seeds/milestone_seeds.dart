import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/silhouettes.dart';

/// §9 Phase 5 — the milestone seeds. The Ring milestone moves *off* its
/// bespoke `_generateRing` branch in `level_generator.dart` and onto the
/// seed pipeline by using [ringMilestoneSeed].
const LevelSeed ringMilestoneSeed = LevelSeed(
  id: 'milestone-ring',
  silhouetteId: SilhouetteId.ring,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
);

/// "Diamond gauntlet" — Hard symmetric layouts on the diamond silhouette.
const LevelSeed diamondMilestoneSeed = LevelSeed(
  id: 'milestone-diamond',
  silhouetteId: SilhouetteId.diamond,
  archetypeId: GenerationArchetype.cleanAuthored,
  difficultyTier: DifficultyTier.hard,
);
