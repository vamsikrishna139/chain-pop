import '../generation/difficulty_mode.dart';
import '../generation/level_configuration.dart';
import '../generation/level_seed.dart';
import 'milestone_seeds.dart';
import 'opening_seeds.dart';

/// Per-level-id seeds, picked up by `LevelGenerator.generate` before the
/// Director's random roll. `null` keys mean "no seed; use the regular
/// random pipeline".
const Map<int, LevelSeed> seedRegistry = <int, LevelSeed>{
  1: openingSeedLevel1,
  2: openingSeedLevel2,
  3: openingSeedLevel3,
};

/// Returns the milestone seed for [config], or null when [config] is a normal
/// (non-milestone) level. The current rotation matches the legacy
/// `_getMilestoneType` cadence (every 25th level for Medium / Hard only),
/// but instead of routing through a bespoke `_generateRing` etc., the seed
/// pipeline picks one of the [milestoneSeedRotation] entries.
LevelSeed? milestoneSeedFor(LevelConfiguration config) {
  final lvl = config.levelId;
  if (lvl < 25) return null;
  // Easy-tier levels keep the relaxed mix even at milestone slots.
  if (config.difficulty.mode == DifficultyMode.easy) return null;
  final mod = lvl % 100;
  if (mod == 75) return ringMilestoneSeed;
  if (mod == 25) return diamondMilestoneSeed;
  return null;
}
