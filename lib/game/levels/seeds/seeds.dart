/// Library barrel for hand-authored [LevelSeed]s shipping with the game.
///
/// New seed packs live in sibling files under `lib/game/levels/seeds/` and
/// register themselves through [seedRegistry] / [milestoneSeedFor].
library seeds;

export 'showcase_levels.dart';
export 'milestone_seeds.dart';
export 'opening_seeds.dart';
export 'seed_registry.dart';
