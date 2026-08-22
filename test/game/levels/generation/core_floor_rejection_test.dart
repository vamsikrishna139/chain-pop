// F1 regression — the generator must REJECT a board whose core floor cannot be
// met, not ship the deepest placement that happened to exist.
//
// `core_triviality_test` asserts the *outcome* (no trivially short Medium
// board). This asserts the *mechanism*, because the outcome can go green by
// luck — a corpus where no flat board happens to be selected passes it while
// the defect is still fully present, which is exactly the state the tree was
// in before T2.6/T2.7 made such a board reachable.
//
// THE FAILURE MODE, not the level id. `_ensureCoreQuality` repicks over three
// widening rungs, then escalates the core count one at a time to the mode's
// `maxCores`. When even that misses the floor it returns "best seen". On a
// geometrically flat board that is not a near miss: `medium L236` (16 nodes,
// 7x7) required tap depth 8 and its deepest reachable placement was **3** — it
// shipped as a three-tap win and took F1 red.
//
// §12 of the plan pre-committed the remedy for precisely this case: *"T1.2's
// bounded repick cannot fix these. Move the remedy upstream into candidate
// rejection — do not let it silently ship 'best seen'."*
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

void main() {
  test('a board that cannot meet its core floor is rejected, not shipped', () {
    final unmetSeen = <String>[];
    CoreSelectionTelemetry.sink = (rec) {
      if (rec.floorAchieved < rec.floorRequired) {
        unmetSeen.add('${rec.mode.name} L${rec.levelId} '
            'required=${rec.floorRequired} achieved=${rec.floorAchieved} '
            'requested=${rec.requested} selected=${rec.selected} '
            'rungs=${rec.repickRungs} escalated=${rec.escalated}');
      }
    };
    addTearDown(() => CoreSelectionTelemetry.sink = null);

    final gen = LevelGenerator();
    for (var id = 1; id <= 300; id++) {
      gen.generate(id, mode: DifficultyMode.medium, timeBudget: kProdBudget);
    }

    // 1. The mechanism is live. Without this the test passes vacuously on any
    //    corpus that happens not to contain a flat board, which is how this
    //    defect stayed invisible until selection changed underneath it.
    expect(gen.coreFloorRejects, greaterThan(0),
        reason: 'No candidate was rejected for an unmet core floor across 300 '
            'Medium levels. Either the rejection was removed, or the corpus no '
            'longer contains a board flat enough to trigger it — in which case '
            'this test is no longer guarding anything and needs a population '
            'that does. Do not delete the assertion to make it pass.');

    // 2. Every unmet floor the enricher saw belonged to a candidate that was
    //    then discarded — none of them reached a player.
    expect(unmetSeen, isNotEmpty,
        reason: 'sanity: the telemetry channel should have observed the '
            'unmet-floor candidates that were rejected');
  });
}
