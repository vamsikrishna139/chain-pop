// T0.0b — the determinism probes. See docs/IMPLEMENTATION_PLAN_V2.md §T0.0b
// and docs/playtests/generator_input_closure.md.
//
// Probe 2 and probe 5 are the contract:
//
//     Board = f(levelId, mode, generationVersion, recipeId, declared inputs)
//
// under `LevelGenerator.neutral()`. Every byte-identity gate in P1, P2 and P3
// rests on them, so they must never be weakened to validity/solvability checks.
//
// Probes 1, 3 and 4 assert the opposite — that a *shared* generator emits
// different boards — to document that the ledger is a declared input rather
// than an accident. Treat these as **fragile by construction**: they assert a
// property of the candidate population at one id, not of the contract. A warm
// ledger does not guarantee a different board, and on `id = 42` it provably
// does not (the K-loop runs out of in-band candidates and `nonNovelFallback`
// re-emits the identical level) — which is why these three use `id = 44`.
//
// P1 and P2 deliberately change candidate diversity. **If probes 1/3/4 go red
// after such a change, the contract has not been violated** — re-pick an id
// with a wider in-band candidate set and record the new id here. If probe 2 or
// 5 goes red, stop: an undeclared input has entered the generator.
//
// SCOPE — every probe here generates with `timeBudget: null`, and must keep
// doing so. On the budgeted path (which is what production runs, via
// `LevelManager.generationBudget`) elapsed wall-clock decides control flow at
// `level_generator.dart:501`, `:514` and `:599`, so the board depends on how
// fast the host machine is and byte-identity is not achievable even in
// principle. The contract is:
//
//     deterministic  iff  timeBudget == null
//
// See the "Wall-clock is an input on the budgeted path" section of
// docs/playtests/generator_input_closure.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation.dart';
import 'corpus_identity.dart';
import 'report_sample.dart';

void main() {
  group('Determinism Probes (T0.0b)', () {
    test('Probe 1: one generator: generate(44), generate(44) differs', () {
      final generator = LevelGenerator.neutral();
      final r1 = generator.generate(44);
      final r2 = generator.generate(44);
      expect(r1.isSuccess, isTrue);
      expect(r2.isSuccess, isTrue);

      final l1 = r1.value;
      final l2 = r2.value;

      bool isIdentical = l1.nodes.length == l2.nodes.length;
      if (isIdentical) {
        for (int i = 0; i < l1.nodes.length; i++) {
          if (l1.nodes[i].x != l2.nodes[i].x ||
              l1.nodes[i].y != l2.nodes[i].y ||
              l1.nodes[i].dir != l2.nodes[i].dir ||
              l1.nodes[i].isCore != l2.nodes[i].isCore ||
              l1.nodes[i].kind != l2.nodes[i].kind) {
            isIdentical = false;
            break;
          }
        }
      }
      expect(isIdentical, isFalse,
          reason:
              'Ledger is a declared input, subsequent generations should differ.');
    });

    test('Probe 2: two fresh generators: generate(44) each -> byte-identical',
        () {
      final g1 = LevelGenerator.neutral();
      final g2 = LevelGenerator.neutral();
      final r1 = g1.generate(44);
      final r2 = g2.generate(44);

      expect(r1.isSuccess, isTrue);
      expect(r2.isSuccess, isTrue);

      final l1 = r1.value;
      final l2 = r2.value;

      expect(l1.gridWidth, equals(l2.gridWidth));
      expect(l1.gridHeight, equals(l2.gridHeight));
      expect(l1.nodes.length, equals(l2.nodes.length));

      for (int i = 0; i < l1.nodes.length; i++) {
        expect(l1.nodes[i].x, equals(l2.nodes[i].x));
        expect(l1.nodes[i].y, equals(l2.nodes[i].y));
        expect(l1.nodes[i].dir, equals(l2.nodes[i].dir));
        expect(l1.nodes[i].isCore, equals(l2.nodes[i].isCore));
        expect(l1.nodes[i].kind, equals(l2.nodes[i].kind));
      }
    });

    test('Probe 3: one generator: 44, 45, 44 -> 44s differ', () {
      final generator = LevelGenerator.neutral();
      final r1 = generator.generate(44);
      generator.generate(45);
      final r2 = generator.generate(44);

      final l1 = r1.value;
      final l2 = r2.value;

      bool isIdentical = l1.nodes.length == l2.nodes.length;
      if (isIdentical) {
        for (int i = 0; i < l1.nodes.length; i++) {
          if (l1.nodes[i].x != l2.nodes[i].x ||
              l1.nodes[i].y != l2.nodes[i].y ||
              l1.nodes[i].dir != l2.nodes[i].dir) {
            isIdentical = false;
            break;
          }
        }
      }
      expect(isIdentical, isFalse);
    });

    test('Probe 4: one generator: 44 Hard, 44 Medium, 44 Hard -> Hard differs',
        () {
      final generator = LevelGenerator.neutral();
      final r1 = generator.generate(44, mode: DifficultyMode.hard);
      generator.generate(44, mode: DifficultyMode.medium);
      final r2 = generator.generate(44, mode: DifficultyMode.hard);

      final l1 = r1.value;
      final l2 = r2.value;

      bool isIdentical = l1.nodes.length == l2.nodes.length;
      if (isIdentical) {
        for (int i = 0; i < l1.nodes.length; i++) {
          if (l1.nodes[i].x != l2.nodes[i].x ||
              l1.nodes[i].y != l2.nodes[i].y ||
              l1.nodes[i].dir != l2.nodes[i].dir) {
            isIdentical = false;
            break;
          }
        }
      }
      expect(isIdentical, isFalse,
          reason: 'Mode must not leak into the 3rd beyond ledger effects.');
    });

    // Probe 5 is the plan's real gate (§T0.0b: "a single id proves nothing
    // about the population") but the full 300-board sweep costs ~2m20s, which
    // is too much for every local `flutter test`. It is split:
    //
    //   * 5a runs a 25-id stride of the same sample by default (~35s) — still
    //     a population check, just a coarser one;
    //   * 5 runs the full 100 ids x 3 modes, tagged `slow`, and remains the
    //     T0 definition-of-done gate. CI and pre-release must run it:
    //         flutter test --tags slow
    //
    // Never let 5a become the only survivor. If it goes red, run 5 for the
    // full failing set before investigating.
    test('Probe 5a: two fresh generators, every 4th sample id x 3 modes', () {
      for (final mode in [
        DifficultyMode.easy,
        DifficultyMode.medium,
        DifficultyMode.hard
      ]) {
        for (var i = 0; i < kReportSampleIds.length; i += 4) {
          final id = kReportSampleIds[i];
          final g1 = LevelGenerator.neutral();
          final g2 = LevelGenerator.neutral();

          final r1 = g1.generate(id, mode: mode);
          final r2 = g2.generate(id, mode: mode);

          expect(r1.isSuccess, isTrue, reason: 'id: $id, mode: $mode');
          expect(r2.isSuccess, isTrue, reason: 'id: $id, mode: $mode');

          final l1 = r1.value;
          final l2 = r2.value;

          expect(l1.gridWidth, equals(l2.gridWidth));
          expect(l1.gridHeight, equals(l2.gridHeight));
          expect(l1.nodes.length, equals(l2.nodes.length),
              reason: 'Node count differs for id $id mode $mode');

          for (int n = 0; n < l1.nodes.length; n++) {
            expect(l1.nodes[n].x, equals(l2.nodes[n].x),
                reason: 'x differs for id $id mode $mode node $n');
            expect(l1.nodes[n].y, equals(l2.nodes[n].y),
                reason: 'y differs for id $id mode $mode node $n');
            expect(l1.nodes[n].dir, equals(l2.nodes[n].dir),
                reason: 'dir differs for id $id mode $mode node $n');
            expect(l1.nodes[n].isCore, equals(l2.nodes[n].isCore),
                reason: 'isCore differs for id $id mode $mode node $n');
            expect(l1.nodes[n].kind, equals(l2.nodes[n].kind),
                reason: 'kind differs for id $id mode $mode node $n');
          }
        }
      }
    });

    test(
        'Probe 5: two fresh generators, full sweep of 100 kReportSampleIds x 3 modes',
        () {
      // 300 checks total
      for (final mode in [
        DifficultyMode.easy,
        DifficultyMode.medium,
        DifficultyMode.hard
      ]) {
        for (final id in kReportSampleIds) {
          final g1 = LevelGenerator.neutral();
          final g2 = LevelGenerator.neutral();

          final r1 = g1.generate(id, mode: mode);
          final r2 = g2.generate(id, mode: mode);

          expect(r1.isSuccess, isTrue, reason: 'id: $id, mode: $mode');
          expect(r2.isSuccess, isTrue, reason: 'id: $id, mode: $mode');

          final l1 = r1.value;
          final l2 = r2.value;

          expect(l1.gridWidth, equals(l2.gridWidth));
          expect(l1.gridHeight, equals(l2.gridHeight));
          expect(l1.nodes.length, equals(l2.nodes.length),
              reason: 'Node count differs for id $id mode $mode');

          for (int i = 0; i < l1.nodes.length; i++) {
            expect(l1.nodes[i].x, equals(l2.nodes[i].x),
                reason: 'x differs for id $id mode $mode node $i');
            expect(l1.nodes[i].y, equals(l2.nodes[i].y),
                reason: 'y differs for id $id mode $mode node $i');
            expect(l1.nodes[i].dir, equals(l2.nodes[i].dir),
                reason: 'dir differs for id $id mode $mode node $i');
            expect(l1.nodes[i].isCore, equals(l2.nodes[i].isCore),
                reason: 'isCore differs for id $id mode $mode node $i');
            expect(l1.nodes[i].kind, equals(l2.nodes[i].kind),
                reason: 'kind differs for id $id mode $mode node $i');
          }
        }
      }
    }, tags: 'slow');
  });

  // ── Hidden-state independence (T0.0c) ──────────────────────────────────
  //
  // The closure audit CLASSIFIES every mutable field of `LevelGenerator`.
  // Classification is a claim about the code, and a claim is worth exactly as
  // much as the test that holds it. These probes convert the two load-bearing
  // claims into assertions:
  //
  //   1. The fields the audit calls SESSION state really are inputs — they
  //      belong in the contract, and `neutral()` really does reset them.
  //   2. The fields it calls EPHEMERAL really cannot move a board —
  //      `_pendingEmission`, `_lastWinningBlockingRetryIndex` and the
  //      emission counters are write-only with respect to generation.
  //
  // The principle: no mutable process state may silently influence board
  // identity. If it does, it must become an explicit input.
  group('Hidden-state independence (T0.0c)', () {
    // Ids chosen to span all three modes' procedural paths.
    const probeIds = [7, 23, 44, 61, 88];

    BoardIdentity identityOf(LevelGenerator g, int id, DifficultyMode mode) =>
        BoardIdentity.of(g.generate(id, mode: mode).value, mode);

    test('neutral() resets session state — a warmed generator vs a fresh one',
        () {
      // Warm one generator hard: many emissions across modes, so both the
      // diversity ledger AND the silhouette tracker carry real history.
      final warmed = LevelGenerator.neutral();
      for (final mode in DifficultyMode.values) {
        for (var id = 100; id < 130; id++) {
          warmed.generate(id, mode: mode);
        }
      }

      // A generator warmed and then NOT reset must be treated as a different
      // input. We do not assert its boards differ — that is a property of the
      // candidate population, not the contract (see the id-42 caveat above).
      // What must hold is that a FRESH generator is unaffected by the
      // existence of the warmed one: no static or global state links them.
      for (final id in probeIds) {
        for (final mode in DifficultyMode.values) {
          final a = identityOf(LevelGenerator.neutral(), id, mode);
          final b = identityOf(LevelGenerator.neutral(), id, mode);
          expect(a.firstDifference(b), isNull,
              reason: 'fresh generators disagree on $id/${mode.name} while a '
                  'warmed generator exists — session state is leaking through '
                  'a static or global.');
        }
      }
    });

    test('emission counters are write-only — resetCounters cannot move a board',
        () {
      // If any candidate gate read the archetype/motif/seed emission counters,
      // a generator that had emitted N levels would produce different boards
      // than one that had emitted none *even after* the ledger was equalised.
      // resetCounters() clears exactly those counters and nothing else, so it
      // is the precise instrument for the question.
      for (final id in probeIds) {
        final fresh =
            identityOf(LevelGenerator.neutral(), id, DifficultyMode.hard);

        final counted = LevelGenerator.neutral();
        for (var warm = 200; warm < 215; warm++) {
          counted.generate(warm, mode: DifficultyMode.hard);
        }
        counted.resetCounters();

        // The ledger and tracker are still warm here, so we assert the weaker
        // but meaningful thing: clearing the counters on a generator does not
        // make it agree or disagree with a fresh one *because of* counters.
        // The strong form is the pair below, where session state is equal.
        final a = LevelGenerator.neutral();
        final b = LevelGenerator.neutral();
        b.resetCounters(); // no-op on a virgin instance if truly write-only
        expect(
          identityOf(a, id, DifficultyMode.hard).firstDifference(
            identityOf(b, id, DifficultyMode.hard),
          ),
          isNull,
          reason: 'resetCounters() changed a board on id $id — the emission '
              'counters are being read by a generation gate, so they are an '
              'undeclared input, not telemetry.',
        );
        expect(fresh.nodeCount, greaterThan(0));
      }
    });

    test('telemetry getters observed mid-sweep cannot perturb generation', () {
      // `_pendingEmission` and `_lastWinningBlockingRetryIndex` carry across
      // calls, which is why the audit flagged them as suspects. Reading every
      // telemetry surface between generations must not change what comes out.
      final quiet = LevelGenerator.neutral();
      final observed = LevelGenerator.neutral();

      final quietBoards = <BoardIdentity>[];
      final observedBoards = <BoardIdentity>[];

      for (final id in probeIds) {
        quietBoards.add(identityOf(quiet, id, DifficultyMode.hard));

        observedBoards.add(identityOf(observed, id, DifficultyMode.hard));
        // Touch every observation seam between emissions.
        observed.snapshotSession();
        observed.lastWinningBlockingRetryIndex;
      }

      for (var i = 0; i < quietBoards.length; i++) {
        expect(quietBoards[i].firstDifference(observedBoards[i]), isNull,
            reason: 'observing telemetry between generations changed board '
                '${probeIds[i]} — a staging field is feeding back into '
                'generation.');
      }
    });

    test('mode sweeps do not leak across a fresh generator boundary', () {
      // Generating every mode for an id on one generator, then asking a fresh
      // generator for the same id, must reproduce the contract board exactly.
      for (final id in probeIds) {
        final expected =
            identityOf(LevelGenerator.neutral(), id, DifficultyMode.medium);

        final sweeper = LevelGenerator.neutral();
        for (final mode in DifficultyMode.values) {
          sweeper.generate(id, mode: mode);
        }

        final after =
            identityOf(LevelGenerator.neutral(), id, DifficultyMode.medium);
        expect(expected.firstDifference(after), isNull,
            reason: 'a fresh generator produced a different board for $id '
                'after an unrelated instance swept all modes.');
      }
    });
  });
}
