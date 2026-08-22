import 'package:chain_pop/game/levels/generation/generation_version.dart';

/// T0.2 — the version stamp carried by every corpus artifact, CSV or log.
///
/// Without it a P3-era benchmark silently diffs against a Gen-V1 one and the
/// comparison is meaningless. Single source of truth, so the CSV header and
/// the printed report banner can never disagree.
///
/// - `corpusVersion` — the shape of the artifact itself (columns, encodings).
/// - `generationVersion` — the generator contract; bumping it re-rolls content.
/// - `strategyVersion` — stays 0 until P3's strategy composer exists.
/// - `seedContractVersion` — the seed-derivation contract declared in T0.0c.
const int kCorpusVersion = 1;
const int kStrategyVersion = 0;
const int kSeedContractVersion = 1;

/// Version of the `topologyClass` definition itself (T0.2).
///
/// This exists because the *previous* topology definition was lost: the
/// 30/18/14 figures quoted in `MASTER_PLAN_V2.md` cannot be reproduced by any
/// encoding of the triple the plan names, so a P2 target expressed against
/// them was unmeasurable. Versioning the definition is what stops that
/// happening a second time.
///
/// **v1 — the exact formula. Do not change without bumping this constant.**
///
/// ```
/// topologyClass = "<components>/<enclosedHoles>/<bboxFillBucket>"
///
///   components      = count of 4-connected components of OCCUPIED cells
///                     (nodes as placed, not the silhouette mask)
///   enclosedHoles   = count of 4-connected EMPTY regions inside the grid
///                     that do not touch any grid border
///   bboxFillBucket  = floor(bboxOccupancy * 4), clamped to 0..3
///                     where bboxOccupancy = nodes / (bboxW * bboxH)
///                     0 = sparse [0,.25)  1 = open [.25,.5)
///                     2 = dense  [.5,.75) 3 = solid [.75,1]
/// ```
///
/// Gen V1 baselines under this definition, 300 ids/mode
/// (`sampleLevelIds(count: 300, minId: 1, maxId: 1500, seed: 7)`):
/// **Easy 40 · Medium 25 · Hard 23**. See
/// `docs/playtests/topology_class_calibration.md`.
const int kTopologyDefinitionVersion = 1;

/// The comment block prefixed to every corpus CSV.
String get kCorpusVersionHeader => '# corpusVersion: $kCorpusVersion\n'
    '# generationVersion: $kGenerationVersion\n'
    '# strategyVersion: $kStrategyVersion\n'
    '# seedContractVersion: $kSeedContractVersion\n'
    '# topologyDefinitionVersion: $kTopologyDefinitionVersion\n';

/// The same stamp for reports that print rather than write a CSV.
void printCorpusVersionBanner(String label) {
  // ignore: avoid_print
  print('===== $label — corpusVersion: $kCorpusVersion, '
      'generationVersion: $kGenerationVersion, '
      'strategyVersion: $kStrategyVersion, '
      'seedContractVersion: $kSeedContractVersion, '
      'topologyDefinitionVersion: $kTopologyDefinitionVersion =====');
}
