import 'archetype.dart';
import 'difficulty_profile.dart';
import 'motifs.dart';
import 'silhouettes.dart';

/// A hand-authorable "seed" — the designer's pinned choices for one level.
///
/// Seeds bypass the Director's random archetype + silhouette sampling and let
/// the team pin down specific levels (tutorials, opening sequence, milestones,
/// Specials). The Director still runs the constructor, evaluator, and
/// diversity ledger — the seed only fixes the *style* knobs.
///
/// `seedRng` is an optional deterministic offset used when the caller wants a
/// repeatable, hand-blessed RNG stream (e.g. a tutorial board that must look
/// identical every replay). The Director adds it to `primarySeed` so the same
/// level id + seed always produces the same board.
class LevelSeed {
  /// Stable identifier used for analytics + tests.
  final String id;

  /// Pins the silhouette family.
  final SilhouetteId silhouetteId;

  /// Pins the generation archetype. The constructor uses
  /// `GenerationArchetypeSpec.forArchetype(archetypeId)` for scorer weights.
  final GenerationArchetype archetypeId;

  /// Pins the difficulty band the Evaluator targets.
  final DifficultyTier difficultyTier;

  /// Optional preferred motif id. When set, the Director attempts to place
  /// this exact motif first; if it doesn't fit, falls back to a free roll.
  final MotifId? motifMixId;

  /// Optional deterministic RNG offset; null defers to the caller's seed.
  final int? seedRng;

  /// Optional fixed node count. When null the Director picks one inside the
  /// `difficultyTier` band.
  final int? targetNodeCount;

  const LevelSeed({
    required this.id,
    required this.silhouetteId,
    required this.archetypeId,
    required this.difficultyTier,
    this.motifMixId,
    this.seedRng,
    this.targetNodeCount,
  });

  @override
  String toString() =>
      'LevelSeed($id silhouette=$silhouetteId archetype=$archetypeId '
      'tier=$difficultyTier motif=$motifMixId)';
}
