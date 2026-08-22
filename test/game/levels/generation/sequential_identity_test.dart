// The freeze contract on the NON-NEUTRAL path.
//
// `corpus_identity_test` pins byte-identity under `LevelGenerator.neutral()`,
// which disables diversity gating — so it does not exercise the selection layer
// at all. Every change T2.6/T2.7 made lives in that layer, and the corpus test
// stayed green throughout, which is accurate but is not the reassurance it
// looks like.
//
// `determinism_contract_test` probes 2 and 5 cover *fresh generator per id*.
// Probes 1/3/4 document, correctly, that a **warmed** generator returns a
// different board — the diversity ledger is session state by design, and that
// is not a defect.
//
// What neither covers is the shape the player and the corpus actually meet:
// **a sequential campaign run from a fresh generator.** Each board depends on
// every board before it through the ledger, so the contract that matters at
// freeze time is that the whole *sequence* is reproducible:
//
//     (fresh generator, mode, generationVersion, recipeId, level order)
//         -> byte-identical sequence
//
// This is the gap P2b's own bugs argue for closing. The Daily defect was
// exactly a case of session state leaking into something contracted to be
// reproducible, and it went unnoticed because the broken novelty gate made
// every call collapse to the same fallback. A contract that only holds while a
// gate is broken is not a contract.
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry, facing, mechanic kind and core marking — everything a player sees
/// and everything the corpus fingerprint is built from.
String _signature(LevelData l) =>
    '${l.gridWidth}x${l.gridHeight}:${l.nodes.map((n) => '${n.x},${n.y},'
        '${n.dir.name},${n.kind.name},${n.isCore ? 1 : 0},${n.phaseGroup}').join('|')}';

const int _kLevels = 150;

void main() {
  test('a sequential campaign run is reproducible on the gated path', () {
    for (final mode in DifficultyMode.values) {
      final first = <int, String>{};
      final genA = LevelGenerator();
      for (var id = 1; id <= _kLevels; id++) {
        final r = genA.generate(id, mode: mode);
        if (r.isSuccess) first[id] = _signature(r.value);
      }

      final genB = LevelGenerator();
      final mismatches = <String>[];
      for (var id = 1; id <= _kLevels; id++) {
        final r = genB.generate(id, mode: mode);
        final sig = r.isSuccess ? _signature(r.value) : '<generation failed>';
        if (first[id] != sig) mismatches.add('${mode.name} L$id');
      }

      expect(mismatches, isEmpty,
          reason: 'Two fresh generators produced different boards for the same '
              'sequential run of ${mode.name}. Something outside '
              '(levelId, mode, generationVersion, recipeId, order) is feeding '
              'generation — check for state that survives construction, or a '
              'wall-clock/time-budget dependence in the K-loop.');
      expect(first, hasLength(_kLevels),
          reason: '${mode.name}: generation failed for some ids, which would '
              'let a mismatch hide behind a missing entry');
    }
  });
}
