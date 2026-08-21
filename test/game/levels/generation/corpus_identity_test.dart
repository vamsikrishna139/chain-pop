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
const String kGenV1CorpusHash = '6a19bb9b24d846e3';
const int kGenV1CorpusBoards = 360;
const int kGenV1CorpusBytes = 164846;

// ═══════════════════════════════════════════════════════════════════════════
// GREEN today, and EXPECTED RED the moment T2.1 is un-parked.
//
// T2.1 (jitter propagation to the nine builders that dropped it) is
// implemented and measured but currently PARKED as
// docs/playtests/T2.1_parked.patch, because it cannot be validated on its own
// (see below). Applying that patch moves
// **134 of these 360 boards** — 49 Easy, 39 Medium, 46 Hard; bytes
// 164846 -> 164511, hash -5ad773fce4e6666e. That was measured, not assumed:
// the plan classified T2.1 as "zero seed impact" on the grounds that jitter
// never draws from the main RNG stream, which is true and is asserted in
// layout_mask_test.dart -- but the mask *shape* feeds node placement, so the
// boards move anyway. Same reasoning error as plan §0.1.
//
// The pins below are DELIBERATELY NOT UPDATED. Per the plan's "one
// re-baselining event" rule, T2.1 re-pins together with T2.2/T2.3/T2.4c, so
// this canary goes red once and green once — not twice. Do NOT re-pin it to
// make the suite green in the meantime; that would spend the instrument on an
// intermediate state that never ships.
//
// Why T2.1 is parked rather than merged-and-red: standing alone it also drove
// Daily key 20260905 to a 873,856 ms generation (the known in-constructor
// deadline, hit by relocated geometry) and flattened the diversity ledger on
// some ids -- both symptoms of downstream rejection pressure that T2.2's
// minCells 25->15 and T2.4c's composition-as-score exist to relieve. Keeping
// it in-tree would have made every subsequent suite run a 15-minute, 5-red
// slog for an intermediate state.
//
// Seeded and milestone boards are NOT affected (varied:false => jitter null);
// level_seed_test and milestone_identity_test must stay green throughout. If
// either of those goes red, that is a real regression, not this canary.
//
// See docs/IMPLEMENTATION_PLAN_V2.md §T2.1 (CORRECTED 2026-08-21).
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
