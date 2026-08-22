// The permanent "no board moved" regression instrument (T0 DoD).
//
// The Gen V1 corpus fingerprint is pinned below. Any change that moves a board
// under `LevelGenerator.neutral()` turns this red and names the first board
// that moved — which is the whole point: a bare hash mismatch tells you
// something broke, this tells you what.
//
// WHEN THIS GOES RED
//
//   * P1 (core placement) — core selection is a PURE function of the solved
//     board and consumes no randomness (§0.1), so P1 must NOT change geometry.
//     `isCore` is part of the fingerprint, so re-picking cores WILL move the
//     hash. Update the constant, and check the reported mismatch is an
//     `isCore` flag and never an x/y/dir.
//   * P2 (T2.2/T2.3/T2.4c) — deliberately moves the Hard RNG stream. Expect a
//     wholesale change and re-baseline as one event.
//   * Anything else — stop. Instrumentation is not supposed to move boards.
//
// Never "fix" this by widening the assertion. Re-pin it deliberately, in the
// same commit as the change that justified it.
import 'package:flutter_test/flutter_test.dart';

import 'corpus_identity.dart';

/// 120 ids × 3 modes = 360 boards, generated with `timeBudget: null`.
///
/// **Re-pinned by P1, 2026-08-19** (was `-5474c579aa0323d5`). The hash moved and
/// the serialised length did **not**: 164853 bytes before and after. That is
/// the useful part of this result. `isCore` serialises as `true`/`false`, so a
/// board that gained or lost a core would change the byte count — an identical
/// length over 360 boards says the core *count* is unchanged everywhere in
/// ids 1..120 and only *which* nodes are cores moved. Ids 1..120 are sector 1,
/// where Easy and Medium ship no cores at all, so what this fingerprint
/// actually pins is Hard's three cores landing on different nodes: precisely
/// T1.1, and nothing else.
/// **Re-pinned by the milestone-seed fix, 2026-08-20** (was
/// `4d648468b45c6c63` / 164853 bytes). Exactly one board moved, and it was
/// named rather than assumed: dumping the corpus with and without the change
/// and diffing it reports `50/medium` and nothing else.
///
/// The mover is the Step 2 silhouette pin, not the shortfall fix — flipping
/// `GenerationPlan.pinnedSilhouette` back to false restores the old hash
/// exactly, so Step 1 moves no board in ids 1..120 (consistent with the audit:
/// no slot below 120 ever hits a mechanic shortfall). L50 is the overload
/// milestone, whose seed pins `SilhouetteId.rectangle`; renegotiation used to
/// be able to swap that away on odd depths and ship the milestone as some
/// other shape. Now it cannot, so the board is drawn from a different RNG
/// path.
///
/// The move is a re-layout, not a re-scale: header is `50/medium/9x9/28`
/// before and after — same grid, same node count — and only node coordinates
/// differ. The 7-byte drop is coordinate digit widths.
/// **Re-pinned by P2b, 2026-08-22** (was `52f44d1b347398a1` / 165623 bytes).
/// This event covers the whole P2b working tree, not one commit: an
/// intermediate dump of the tree *without* the two changes below already read
/// `1ff5bf517cd3d920` / 164347, so T2.21 (resolved-silhouette reporting) had
/// moved boards before this. The pin now covers all of it.
///
/// The eight boards that moved were named, not assumed — dumped with and
/// without the change and diffed:
///
///   45/easy   8x6  12 -> 25 nodes    55/easy   8x8  16 -> 25 nodes
///   25/medium 9x9  23 -> 25 nodes    50/medium 9x9  28 -> 26 nodes
///   45/medium 9x9  23 nodes, re-laid out
///   55/medium 9x9  25 nodes, re-laid out
///   45/hard   8x8  25 nodes, re-laid out
///   55/hard   8x8  25 nodes, re-laid out
///
/// Two causes, both deliberate:
///
///   * T2.22 re-declared the L45/L55 showcase seeds (`diamond` -> `cross`,
///     `corridor` -> `asymmetric`), because the originals cannot be built at
///     8x8 against a 25-cell floor — 0/200 seeds each — and so shipped as the
///     64-cell full rectangle.
///   * T2.23 made `pinnedSilhouette` survive `_refinePlanMaskDensity`, which
///     is what moves the two *milestone* rows (25/medium, 50/medium). This
///     completes the work the 2026-08-20 note above started: that fix stopped
///     `renegotiate` swapping a pinned silhouette, and this one stops the
///     density refiner it tail-calls from doing the same thing.
///
/// NODE COUNTS ON EASY. `45/easy` and `55/easy` doubling to 25 nodes is real
/// and is NOT a defect of these changes: showcase seeds pin
/// `difficultyTier: hard` and apply on every mode, so they were always going
/// to spike an Easy slot. `40/easy` has shipped 25 nodes against neighbours of
/// 8-14 all along; L45 and L55 only escaped it because their broken seeds
/// renegotiated down. All three showcase slots now behave the same way. If
/// that spike is wrong, it is wrong at L40 too and the fix is a content
/// decision about showcase seeds on Easy, not a generator change.
///
/// `milestone_identity_test` and `level_seed_test` stayed GREEN throughout —
/// no milestone board moved on the surfaces those pin. Per the note below,
/// this is a sanctioned re-baseline only because Gen V1 is not frozen yet.
const String kGenV1CorpusHash = '7ad43c963aa0d9ae';
const int kGenV1CorpusBoards = 360;
const int kGenV1CorpusBytes = 164918;

// ═══════════════════════════════════════════════════════════════════════════
// RE-PINNED BY P2'S BUNDLE, 2026-08-21. The canary went red once, as designed.
//
// T2.1 (jitter propagation) + T2.3 (mask-density slack + organic exemption) +
// T2.4c (composition rules as ranking terms) landed together as the plan's
// single re-baselining event. Pins moved
// `6a19bb9b24d846e3` / 164846 bytes -> `52f44d1b347398a1` / **165623**.
//
// The mask cell floor moved with them, and that part was not in the plan: it
// now floors at `max(profile.nodeCount.min, difficulty.minNodes)` rather than
// `minNodes` alone, so Medium's floor is 14 instead of 10 and Easy's is 8
// instead of 4. That was forced by a real regression the bundle caused and the
// gates caught — L194/medium shipped a 13-node board won in 3 taps, taking
// `core_triviality_test`'s F1 gate red. See `_buildOrFallbackMask`.
//
// T2.2 is deliberately absent from that list: its specified `minCells`
// 25 -> 15 was measured and rejected — 34 of 200 Hard levels shipped under the
// 25-node floor at 0.6 — so `kMaskCellFloorRatio` ships at 1.0 and moves no
// board. See its doc comment in `director.dart`.
//
// The previous note here predicted T2.1 alone would move 134 of 360 boards to
// hash `-5ad773fce4e6666e` / 164511 bytes. The bundle's actual figure is
// larger and the prediction is left above deliberately: it was measured on
// T2.1 in isolation and is the "before" half of this event's record.
//
// Seeded and milestone boards are NOT affected (varied:false => jitter null);
// `level_seed_test` and `milestone_identity_test` stayed green throughout, and
// that is what makes this a re-baseline rather than a regression. If either of
// those goes red, that is a real defect, not this canary.
//
// WHAT THE NEXT REDNESS MEANS. P2 was the plan's last sanctioned board-moving
// phase before the Gen V1 freeze. After the freeze, no change may move a board
// under `(levelId, mode, generationVersion=1, recipeId=neutral)` — generator
// changes bump `generationVersion` instead. So from here this canary going red
// is a defect report, not a re-baselining prompt, unless the commit that turns
// it red also bumps `kGenerationVersion`.
//
// See docs/IMPLEMENTATION_PLAN_V2.md §T2.1-T2.4c.
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  test('Gen V1 corpus is byte-identical (360 boards)', () {
    final fp = CorpusFingerprint.generate(
      levelIds: [for (var id = 1; id <= 120; id++) id],
    );

    // Population first: a sweep that silently shrank would otherwise read as
    // an ordinary hash mismatch.
    expect(fp.boards, kGenV1CorpusBoards, reason: 'corpus population changed');
    expect(fp.byteLength, kGenV1CorpusBytes,
        reason: 'serialised corpus length changed — ${fp.summary}');
    expect(fp.hash, kGenV1CorpusHash,
        reason: 'a board moved. Re-run with the previous build and diff via '
            'CorpusFingerprint.firstMismatch to name it. ${fp.summary}');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('fingerprinting is itself deterministic, and names a real mismatch', () {
    final ids = [1, 2, 3, 42, 44];
    final a = CorpusFingerprint.generate(levelIds: ids);
    final b = CorpusFingerprint.generate(levelIds: ids);

    expect(a.hash, b.hash);
    expect(a.firstMismatch(b), isNull);

    // A hand-corrupted copy must be located precisely, not merely detected.
    final corrupted = CorpusFingerprint(
      boards: b.boards,
      byteLength: b.byteLength,
      hash: b.hash,
      identities: [
        for (var i = 0; i < b.identities.length; i++)
          if (i != 2)
            b.identities[i]
          else
            BoardIdentity(
              levelId: b.identities[i].levelId,
              mode: b.identities[i].mode,
              gridWidth: b.identities[i].gridWidth,
              gridHeight: b.identities[i].gridHeight,
              nodeCount: b.identities[i].nodeCount,
              nodeLines: [
                'TAMPERED',
                ...b.identities[i].nodeLines.skip(1),
              ],
            ),
      ],
    );

    final mismatch = a.firstMismatch(corrupted);
    expect(mismatch, isNotNull);
    expect(mismatch, contains('node[0]'));
    expect(mismatch, contains('TAMPERED'));
  });
}
