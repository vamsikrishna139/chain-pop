import 'difficulty_mode.dart';

/// The contract version for Level Generator outputs.
///
/// Folded into seed derivation so a future bump deliberately re-rolls content,
/// and stamped on every analytics event and every corpus CSV row.
const int kGenerationVersion = 1;

/// The T0.0c content identity for one generated board:
/// `'$levelId/$mode/v$generationVersion/$recipeId'`.
///
/// Single source of truth for the format. The generator stamps it on every
/// emission event, and the corpus reports stamp it on every CSV row, so a
/// board measured offline can always be traced back to the exact inputs that
/// produced it. [recipeId] stays `neutral` until P4 introduces recipes.
String contentIdentityFor({
  required int levelId,
  required DifficultyMode mode,
  String recipeId = 'neutral',
}) =>
    '$levelId/${mode.name}/v$kGenerationVersion/$recipeId';
