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
const String kGenV1CorpusHash = '-5474c579aa0323d5';
const int kGenV1CorpusBoards = 360;
const int kGenV1CorpusBytes = 164853;

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
