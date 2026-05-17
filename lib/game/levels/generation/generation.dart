/// Barrel file exporting all classes from the generation subsystem.
///
/// Prefer importing `difficulty_parameters.dart` (and other leaf libraries)
/// directly when you only need tuning types — avoids accidental transitive
/// coupling through this barrel.
///
/// Import this single file to access the entire generation API:
/// ```dart
/// import 'package:chain_pop/game/levels/generation/generation.dart';
/// ```
library generation;

export 'difficulty_mode.dart';
export 'difficulty_parameters.dart';
export 'generation_error.dart';
export 'level_configuration.dart';
export 'level_generator.dart';
export 'level_validator.dart';
export 'result.dart';
export 'validation_result.dart';
