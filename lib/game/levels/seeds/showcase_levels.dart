import '../generation/archetype.dart';
import '../generation/difficulty_profile.dart';
import '../generation/level_seed.dart';
import '../generation/motifs.dart';
import '../generation/silhouettes.dart';

/// Hand-authored showcase / boss moments — pinned seeds for memorable levels.
///
/// EVERY SEED HERE PINS `difficultyTier: hard`, ON EVERY MODE.
///
/// `showcaseSeedFor` is keyed by level id alone, so an Easy player reaching
/// L40/L45/L55 gets a Hard-tier board. Measured node counts on Easy:
///
///   L38 12 · L39 14 · **L40 25** · L41 13 · L42 12 · ... · **L45 25** ·
///   L46 13 · ... · L54 14 · **L55 25** · L56 10
///
/// against Easy neighbours of 8-14. That is roughly a 2x spike, three times
/// across the Easy campaign.
///
/// **This is accepted for Gen V1, deliberately.** It is not new and it is not
/// a side effect of the T2.22 seed re-declaration below: L40 has shipped 25
/// nodes on Easy all along. L45 and L55 only *appeared* smaller because their
/// seeds declared unbuildable silhouettes, fell back to the full rectangle and
/// renegotiated down to 12 and 16 nodes. Fixing the seeds removed that
/// accident, so all three showcase slots now behave the same way — which is
/// the behaviour L40 always had.
///
/// Every mechanical gate is green on it: Easy autoplay 1800/1800 with zero
/// stranded boards, the F1 / core-triviality floor, and the Easy difficulty
/// contract. What is unverified is *feel* — whether a 2x board reads as a
/// memorable showcase or as a wall, on the mode least equipped for it.
///
/// If it reads as a wall, the fix belongs HERE, not in the generator, and it
/// is the same fix for all three slots: give the seed a per-mode difficulty
/// tier (same authored silhouette and archetype, mode-appropriate target), or
/// skip showcase seeds on Easy entirely. Do not clamp node count after
/// generation — that keeps the spike's shape and discards its structure.
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
  // P2b T2.22 — was `diamond`, which cannot be built here.
  //
  // On the seeded path `varied: false` disables jitter, so `_diamond` runs
  // with `rx == ry == min(w,h)/2 - 0.3 + wobble`, which tops out below 4.0 on
  // an 8x8 board and admits only the Manhattan rings summing to <= 3 — 24
  // cells, against a 25-cell Hard floor. Measured 0/200 seeds. The canonical
  // path is exempt from the family ladder in `_resolveMask`, so the only
  // outcome was the 64-cell full rectangle: this showcase beat shipped as the
  // blandest board in the game, geometrically identical (Jaccard 1.0) to the
  // `milestone-overload` full grid five levels later at L50.
  //
  // `cross` keeps the sharp, symmetric, geometric read the beat was authored
  // for and builds at 200/200 seeds for 39 cells. Diamond becomes available
  // again at 7x7 (exactly 25) and 9x9 (41) if these slots ever move.
  //
  // T2.25 — LEFT AS `cross` ON PURPOSE, having tried the alternative.
  //
  // This ships a plus-form next to L46, which the procedural path also draws
  // as a cross (6x8, 33 cells). Same family AND same concrete shape, back to
  // back — a fair perceptual complaint, so `organicBlob` was measured as the
  // replacement. It fixes THIS pair (L45 becomes a compact 30-cell blob, and
  // even gains the difficulty band) and then reproduces the identical problem
  // one level later:
  //
  //   cross : L45 cross 8x8/39 | L46 cross 6x8/33 | L47 corridor 8x6/28
  //   blob  : L45 blob  8x8/30 | L46 cross 6x8/33 | L47 cross    8x6/33
  //
  // L46 and L47 then both ship a 33-cell cross on transposed grids, which is a
  // tighter echo than the pair it was meant to remove, and Hard in-band falls
  // 25/51 -> 24/51. The cause is that a seeded slot feeds the silhouette
  // session tracker, so re-shaping one authored board re-rolls its neighbours.
  //
  // At this constraint density a single-slot nudge relocates the collision
  // rather than removing it. Accepted as-is for Gen V1.
  45: LevelSeed(
    id: 'showcase-seal-breaker',
    silhouetteId: SilhouetteId.cross,
    archetypeId: GenerationArchetype.cleanAuthored,
    difficultyTier: DifficultyTier.hard,
    motifMixId: MotifId.lockCluster,
    seedRng: 4501,
  ),

  // P2b T2.22 — was `corridor`, unbuildable here for the same reason:
  // `bandWidth = max(2, 8 ~/ 3) = 2` gives 16 cells whichever way `nextBool`
  // falls, so 0/200 seeds clear the floor and this beat also shipped as the
  // full rectangle. No member of the corridor family is buildable at 8x8, so
  // the family cannot be preserved; `asymmetric` (39 cells, 200/200) is the
  // most distinct outline available, and being organic it also breaks the
  // lattice family run that used to span L52-L56.
  55: LevelSeed(
    id: 'showcase-phase-shift',
    silhouetteId: SilhouetteId.asymmetric,
    archetypeId: GenerationArchetype.cleanAuthored,
    difficultyTier: DifficultyTier.hard,
    seedRng: 5501,
  ),
};
