// T0.4§a — the one-shot selection run that produced `adversarial_corpus.dart`.
//
//   flutter test --tags report \
//     test/game/levels/generation/adversarial_corpus_selection_test.dart
//
// ─────────────────────────────────────────────────────────────────────────────
//  THIS RUNS EXACTLY ONCE. It is checked in for provenance, not for reuse.
//
//  The corpus is a scientific instrument. Selection happens exactly once.
//
//  Severity membership is a function of *current* `tapsToWin`. Re-running this
//  after P1 would select a different set of boards and destroy the before/after
//  comparison while appearing to work — the failure mode that looks most like
//  success. The frozen ids in `adversarial_corpus.dart` are checked-in literals
//  and are never re-derived.
// ─────────────────────────────────────────────────────────────────────────────
//
// What it does:
//   1. Draws a ~600-id Medium pool from L1..1500, **excluding** the T0.3
//      canary's `kReportSampleIds` so that stays a genuine held-out set.
//   2. Generates and measures the pool unbudgeted, keyed on `tapsToWin`.
//   3. Splits the pool into five equal-rank quintiles and takes 20 from each,
//      round-robin across `(sector band x coreCount)` cells so a quintile is
//      not twenty near-identical boards testing one failure mode twenty times.
//   4. Draws 100 uniform Medium (representative) and 100 uniform Hard
//      (control), disjoint from everything above and from the canary.
//   5. Prints the Dart literals to paste into `adversarial_corpus.dart`.
//
// No sector filter and no core-count filter anywhere: T0.3 found the shallowest
// Medium boards are overwhelmingly sector 2, single-core, and a corpus that
// excludes them cannot see the fix. The eligible population is every board that
// can ship to a player.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/generation_version.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'corpus_version.dart';
import 'report_sample.dart';

/// Disjoint from [kReportSampleSeed] by construction, so the canary's 100 ids
/// stay held out of every selection decision made here.
const int kAdversarialPoolSeed = 20260819;

const int kPoolSize = 600;
const int kPerQuintile = 20;
const int kQuintiles = 5;
const int kRepresentativeSize = 100;
const int kHardControlSize = 100;

const int kMinLevelId = 1;
const int kMaxLevelId = 1500;

/// Uniform draw of [count] ids in `[kMinLevelId, kMaxLevelId]` avoiding
/// [exclude]. Deterministic in [seed]; the rejection loop keeps the draw
/// uniform over the *eligible* population rather than biasing toward whatever
/// happens to sit next to an excluded id.
List<int> _draw(int count, int seed, Set<int> exclude) {
  final rng = Random(seed);
  const span = kMaxLevelId - kMinLevelId + 1;
  final ids = <int>{};
  var guard = 0;
  while (ids.length < count) {
    if (++guard > count * 1000) {
      throw StateError('draw exhausted: too few eligible ids');
    }
    final id = kMinLevelId + rng.nextInt(span);
    if (exclude.contains(id)) continue;
    ids.add(id);
  }
  return ids.toList()..sort();
}

String _sectorBand(int sector) =>
    sector <= 2 ? 'S1-2' : (sector <= 4 ? 'S3-4' : 'S5+');

void main() {
  test('T0.4 — select the frozen adversarial corpus (RUN ONCE)', () {
    printCorpusVersionBanner('T0.4 CORPUS SELECTION');
    print('  pool seed        : $kAdversarialPoolSeed '
        '(canary seed $kReportSampleSeed — disjoint)');
    print('  generationVersion: $kGenerationVersion');
    print('  timeBudget       : null (unbudgeted; determinism contract)');

    final canary = kReportSampleIds.toSet();
    final poolIds = _draw(kPoolSize, kAdversarialPoolSeed, canary);
    print('\n  pool: ${poolIds.length} Medium ids, '
        'canary overlap = ${poolIds.toSet().intersection(canary).length}');

    // ── 1. Measure the pool ────────────────────────────────────────────────
    //
    // A fresh `LevelGenerator.neutral()` per id. The T0.0a closure audit
    // classifies the diversity ledger and the silhouette tracker as *session
    // state*, so a reused instance emits boards that depend on the whole
    // preceding sequence rather than on `(levelId, mode, generationVersion)`.
    // Selection has to key on exactly the triple the corpus is frozen on, or
    // the severity ranks describe boards the baseline will never regenerate.
    // (Measured, the first time round: L1411 came out at 17 nodes / 8 taps in
    // an ascending 600-id sweep and 18 nodes / 4 taps in the corpus sweep.)
    final rows = <BoardRow>[];
    for (final id in poolIds) {
      final gen = LevelGenerator.neutral();
      final r = gen.generate(id, mode: DifficultyMode.medium, timeBudget: null);
      expect(r.isSuccess, isTrue, reason: 'pool generation failed for L$id');
      final world = worldForLevel(id);
      rows.add(
        measure(
          r.value,
          label: 'L$id',
          levelId: id,
          mode: DifficultyMode.medium,
          profile: DifficultyProfile.medium,
          directive: '-',
          timeLimitSec: 0,
          genMs: 0,
          sector: world.sector.mechanicBudgetTier,
          worldName: world.name,
        ),
      );
      if (rows.length % 100 == 0) {
        print('    measured ${rows.length}/${poolIds.length}');
      }
    }

    // ── 2. Equal-rank quintiles ────────────────────────────────────────────
    //
    // Rank-based, not value-based. With 66% of Medium at <=6 taps the value
    // distribution is dominated by ties, so cutting on values would leave
    // quintiles empty or wildly uneven and the n=20 requirement unmeetable.
    // The tie-break is `levelId`, which is stable and independent of anything
    // P1 touches.
    final ranked = List<BoardRow>.from(rows)
      ..sort((a, b) {
        final d = a.tapsToWin.compareTo(b.tapsToWin);
        return d != 0 ? d : a.levelId.compareTo(b.levelId);
      });
    final per = ranked.length ~/ kQuintiles;
    final quintileOf = <int, int>{}; // levelId -> 1..5
    final severityRank = <int, int>{}; // levelId -> 1-based rank in pool
    for (var i = 0; i < ranked.length; i++) {
      severityRank[ranked[i].levelId] = i + 1;
      quintileOf[ranked[i].levelId] = min(kQuintiles, i ~/ per + 1);
    }

    print('\n  quintile boundaries (tapsToWin), n=${ranked.length}:');
    for (var q = 1; q <= kQuintiles; q++) {
      final members = ranked.where((r) => quintileOf[r.levelId] == q).toList();
      final taps = members.map((r) => r.tapsToWin).toList()..sort();
      print('    Q$q  n=${members.length.toString().padLeft(3)}  '
          'taps ${taps.first}..${taps.last}  '
          'median ${taps[taps.length ~/ 2]}');
    }

    // ── 3. 20 per quintile, round-robin over (sector band x coreCount) ─────
    final severity = <BoardRow>[];
    for (var q = 1; q <= kQuintiles; q++) {
      final members = ranked.where((r) => quintileOf[r.levelId] == q).toList();
      final cells = <String, List<BoardRow>>{};
      for (final r in members) {
        cells
            .putIfAbsent('${_sectorBand(r.sector)}/c${r.cores}', () => <BoardRow>[])
            .add(r);
      }
      final keys = cells.keys.toList()..sort();
      for (final k in keys) {
        cells[k]!.sort((a, b) => a.levelId.compareTo(b.levelId));
      }
      final picked = <BoardRow>[];
      var cursor = 0;
      while (picked.length < kPerQuintile) {
        var progressed = false;
        for (final k in keys) {
          if (picked.length >= kPerQuintile) break;
          final bucket = cells[k]!;
          if (cursor < bucket.length) {
            picked.add(bucket[cursor]);
            progressed = true;
          }
        }
        if (!progressed) break; // quintile smaller than kPerQuintile
        cursor++;
      }
      expect(picked, hasLength(kPerQuintile),
          reason: 'Q$q could not fill $kPerQuintile boards');
      print('\n  Q$q cells: ${keys.map((k) => "$k=${cells[k]!.length}").join("  ")}');
      severity.addAll(picked);
    }

    // ── 4. Representative and Hard control ─────────────────────────────────
    final severityIds = severity.map((r) => r.levelId).toSet();
    final blocked = <int>{...canary, ...severityIds};
    final representative =
        _draw(kRepresentativeSize, kAdversarialPoolSeed + 1, blocked);
    final hardControl = _draw(
      kHardControlSize,
      kAdversarialPoolSeed + 2,
      {...blocked, ...representative},
    );

    // ── 5. Disjointness, stated as an assertion rather than a hope ─────────
    final sets = <String, Set<int>>{
      'severity': severityIds,
      'representative': representative.toSet(),
      'hardControl': hardControl.toSet(),
      'canary': canary,
    };
    for (final a in sets.keys) {
      for (final b in sets.keys) {
        if (a == b) continue;
        expect(sets[a]!.intersection(sets[b]!), isEmpty,
            reason: '$a and $b overlap');
      }
    }

    // ── 6. Realised composition, for the README ────────────────────────────
    void composition(String label, List<BoardRow> rs) {
      final bySector = <int, int>{};
      final byCores = <int, int>{};
      for (final r in rs) {
        bySector[r.sector] = (bySector[r.sector] ?? 0) + 1;
        byCores[r.cores] = (byCores[r.cores] ?? 0) + 1;
      }
      final sk = bySector.keys.toList()..sort();
      final ck = byCores.keys.toList()..sort();
      print('  $label sectors: ${sk.map((s) => "S$s=${bySector[s]}").join("  ")}');
      print('  $label cores  : ${ck.map((c) => "$c=${byCores[c]}").join("  ")}');
    }

    print('\n===== REALISED COMPOSITION =====');
    composition('severity', severity);
    final poolById = {for (final r in rows) r.levelId: r};
    print('  (representative and hard sector counts are printed by the '
        'baseline run, which is where those boards are first generated)');
    print('  pool sector prevalence:');
    composition('pool', rows);

    // ── 7. The literals ────────────────────────────────────────────────────
    print('\n===== PASTE INTO adversarial_corpus.dart =====');
    print('  // medium severity — quintile, severityRank in a '
        '${rows.length}-board pool');
    for (final r in severity) {
      print('  CorpusEntry(${r.levelId}, DifficultyMode.medium, '
          'CorpusView.mediumSeverity, '
          'quintile: ${quintileOf[r.levelId]}, '
          'severityRank: ${severityRank[r.levelId]}), '
          '// taps=${r.tapsToWin} S${r.sector} cores=${r.cores} '
          'nodes=${r.nodes}');
    }
    print('  // medium representative');
    for (final id in representative) {
      print('  CorpusEntry($id, DifficultyMode.medium, '
          'CorpusView.mediumRepresentative),');
    }
    print('  // hard control');
    for (final id in hardControl) {
      print('  CorpusEntry($id, DifficultyMode.hard, '
          'CorpusView.hardControl),');
    }

    print('\n  quintile boundary literals:');
    for (var q = 1; q <= kQuintiles; q++) {
      final taps = ranked
          .where((r) => quintileOf[r.levelId] == q)
          .map((r) => r.tapsToWin)
          .toList()
        ..sort();
      print('  QuintileBounds($q, minTaps: ${taps.first}, '
          'maxTaps: ${taps.last}, poolCount: ${taps.length}),');
    }
    expect(poolById, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
