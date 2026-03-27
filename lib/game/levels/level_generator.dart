/// Re-export of the new generation system for backward compatibility.
///
/// This file maintains the old import path while delegating to the new
/// generation subsystem. Existing code can continue to import:
/// ```dart
/// import 'package:chain_pop/game/levels/level_generator.dart';
/// ```
///
/// For new code, prefer importing the generation barrel file directly:
/// ```dart
/// import 'package:chain_pop/game/levels/generation/generation.dart';
/// ```
library level_generator;

export 'generation/generation.dart';
