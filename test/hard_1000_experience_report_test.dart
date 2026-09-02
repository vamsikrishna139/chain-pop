// Diagnostic harness: prints a human-readable "player experience" report for
// 1000 Hard campaign levels. Not production code, not an assertion suite.
// ignore_for_file: avoid_print

@Tags(['corpus', 'report'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';

class Rec {
  late int id;
  late int nodes;
  late int gw;
  late int gh;
  late int maskArea;
  late int waves;
  late int open;
  late double fsr;
  late double bf;
  late int cud;
  late int chokes;
  late int cores;
  late int locks;
  late int relays;
  late int phases;
  late int portals;
  late String maskSig;
  late String boardSig;
  late String dirHist;
  late LevelDirective directive;
  late int timeLimit;
  late int genMs;
}

void main() {
  test('HARD 1000 — player experience report', () {
    final gen = LevelGenerator();
    final recs = <Rec>[];
    final sw = Stopwatch();
    final csv = File('/tmp/hard1000.csv');
    if (csv.existsSync()) csv.deleteSync();
    csv.writeAsStringSync('id,nodes,gw,gh,maskArea,waves,open,fsr,bf,cud,'
        'chokes,cores,locks,relays,phases,portals,directive,timeLimit,genMs,'
        'dirHist,maskHash,boardHash\n');

    for (var i = 1; i <= 1000; i++) {
      sw.reset();
      sw.start();
      final res = gen.generate(i,
          mode: DifficultyMode.hard,
          timeBudget: const Duration(milliseconds: 200));
      sw.stop();
      if (!res.isSuccess) {
        print('!! generation FAILED at level $i: ${res.error}');
        continue;
      }
      final lv = res.value;
      final m = LevelMetrics.compute(lv);
      final r = Rec()
        ..id = i
        ..nodes = lv.nodes.length
        ..gw = lv.gridWidth
        ..gh = lv.gridHeight
        ..maskArea = lv.playCells?.length ?? lv.gridWidth * lv.gridHeight
        ..waves = m.waveDepth
        ..open = m.waveZeroWidth
        ..fsr = m.forcedSequenceRatio
        ..bf = m.averageBranchingFactor
        ..cud = m.criticalUnlockDepth
        ..chokes = m.chokePointCount
        ..cores = lv.nodes.where((n) => n.isCore).length
        ..locks = lv.nodes.where((n) => n.kind == NodeKind.locked).length
        ..relays = lv.nodes.where((n) => n.kind == NodeKind.relay).length
        ..phases = lv.nodes.map((n) => n.phaseGroup).toSet().length
        ..portals = lv.portalPairs.length
        ..genMs = sw.elapsedMilliseconds
        ..directive = directiveFor(levelId: i, mode: DifficultyMode.hard)
        ..timeLimit =
            computeGameTimeLimit(DifficultyMode.hard, lv.nodes.length, i) ?? 0;

      final cells = (lv.playCells?.toList() ?? <String>[])..sort();
      r.maskSig = '${lv.gridWidth}x${lv.gridHeight}|${cells.join(';')}';
      final bs = [for (final n in lv.nodes) '${n.x},${n.y},${n.dir.index}']
        ..sort();
      r.boardSig = '${lv.gridWidth}x${lv.gridHeight}|${bs.join(';')}';
      final dh = <int, int>{};
      for (final n in lv.nodes) {
        dh[n.dir.index] = (dh[n.dir.index] ?? 0) + 1;
      }
      r.dirHist = [0, 1, 2, 3].map((d) => dh[d] ?? 0).join('/');
      recs.add(r);
      csv.writeAsStringSync(
        '${r.id},${r.nodes},${r.gw},${r.gh},${r.maskArea},${r.waves},'
        '${r.open},${r.fsr.toStringAsFixed(4)},${r.bf.toStringAsFixed(3)},'
        '${r.cud},${r.chokes},${r.cores},${r.locks},${r.relays},${r.phases},'
        '${r.portals},${r.directive.label},${r.timeLimit},${r.genMs},'
        '${r.dirHist},${r.maskSig.hashCode},${r.boardSig.hashCode}\n',
        mode: FileMode.append,
      );
      if (const [1, 40, 120, 300, 500, 625, 750, 900, 1000].contains(i)) {
        _render(lv, i);
      }
    }

    print('\n#### GENERATED ${recs.length}/1000 HARD LEVELS');

    // ── 1. Progression: does anything change over 1000 levels? ────────────
    print('\n== 1. PROGRESSION BY 100-LEVEL BUCKET ==');
    print('bucket | nodes | grid | fill% | waves | open | FSR  | BF   | CUD |'
        ' cores locks relay phase portal | timer | gen ms');
    for (var b = 0; b < 10; b++) {
      final s =
          recs.where((r) => r.id > b * 100 && r.id <= (b + 1) * 100).toList();
      if (s.isEmpty) continue;
      double avg(num Function(Rec) f) =>
          s.map(f).fold<double>(0, (a, x) => a + x) / s.length;
      print(
          '${(b * 100 + 1).toString().padLeft(4)}-${((b + 1) * 100).toString().padRight(5)}'
          '| ${avg((r) => r.nodes).toStringAsFixed(1).padLeft(5)} '
          '| ${avg((r) => r.gw).toStringAsFixed(1)}x${avg((r) => r.gh).toStringAsFixed(1)} '
          '| ${(avg((r) => r.nodes) / avg((r) => r.maskArea) * 100).toStringAsFixed(0).padLeft(4)} '
          '| ${avg((r) => r.waves).toStringAsFixed(2).padLeft(5)} '
          '| ${avg((r) => r.open).toStringAsFixed(1).padLeft(4)} '
          '| ${avg((r) => r.fsr).toStringAsFixed(2)} '
          '| ${avg((r) => r.bf).toStringAsFixed(2)} '
          '| ${avg((r) => r.cud).toStringAsFixed(1).padLeft(3)} '
          '| ${avg((r) => r.cores).toStringAsFixed(1)}   '
          '${avg((r) => r.locks).toStringAsFixed(1)}   '
          '${avg((r) => r.relays).toStringAsFixed(1)}   '
          '${avg((r) => r.phases).toStringAsFixed(1)}   '
          '${avg((r) => r.portals).toStringAsFixed(1)} '
          '| ${avg((r) => r.timeLimit).toStringAsFixed(0).padLeft(4)}s '
          '| ${avg((r) => r.genMs).toStringAsFixed(0).padLeft(4)}');
    }

    // ── 2. Board-shape repetition ─────────────────────────────────────────
    print('\n== 2. BOARD SHAPE (silhouette) REPETITION ==');
    final maskCounts = <String, int>{};
    for (final r in recs) {
      maskCounts[r.maskSig] = (maskCounts[r.maskSig] ?? 0) + 1;
    }
    final sortedMasks = maskCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('distinct silhouettes across 1000 levels: ${maskCounts.length}');
    print('top 15 most-repeated silhouettes:');
    for (final e in sortedMasks.take(15)) {
      final label = e.key.split('|')[0];
      final isFull = e.key.endsWith('|');
      print('  ${e.value.toString().padLeft(4)}x  $label'
          '${isFull ? "  (FULL RECTANGLE, no mask)" : ""}');
    }
    final fullRect = recs.where((r) => r.maskSig.endsWith('|')).length;
    print('levels on a plain full rectangle: $fullRect '
        '(${(fullRect / recs.length * 100).toStringAsFixed(1)}%)');

    // grid dimension distribution
    final dims = <String, int>{};
    for (final r in recs) {
      dims['${r.gw}x${r.gh}'] = (dims['${r.gw}x${r.gh}'] ?? 0) + 1;
    }
    final sd = dims.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print(
        'grid dimensions: ${sd.map((e) => "${e.key}:${e.value}").join("  ")}');

    // consecutive identical silhouette runs
    var runs = 0, maxRun = 1, cur = 1;
    for (var i = 1; i < recs.length; i++) {
      if (recs[i].maskSig == recs[i - 1].maskSig) {
        cur++;
        if (cur == 2) runs++;
      } else {
        maxRun = max(maxRun, cur);
        cur = 1;
      }
    }
    maxRun = max(maxRun, cur);
    print(
        'back-to-back identical silhouette runs: $runs (longest run: $maxRun)');

    // ── 3. Duplicate boards ───────────────────────────────────────────────
    print('\n== 3. DUPLICATE / NEAR-DUPLICATE BOARDS ==');
    final boardCounts = <String, List<int>>{};
    for (final r in recs) {
      boardCounts.putIfAbsent(r.boardSig, () => []).add(r.id);
    }
    final dupes = boardCounts.entries.where((e) => e.value.length > 1).toList();
    print(
        'EXACT duplicate boards (same cells + same arrows): ${dupes.length} groups');
    for (final e in dupes.take(10)) {
      print('  levels ${e.value.join(", ")}');
    }
    // near-dup: same silhouette + same node count + same direction histogram
    final nearCounts = <String, List<int>>{};
    for (final r in recs) {
      nearCounts
          .putIfAbsent('${r.maskSig}#${r.nodes}#${r.dirHist}', () => [])
          .add(r.id);
    }
    final nearGroups = nearCounts.values.where((v) => v.length > 1).toList();
    final inNear = nearGroups.fold<int>(0, (a, v) => a + v.length);
    print(
        'NEAR-duplicate groups (same shape+count+arrow mix): ${nearGroups.length}'
        ' covering $inNear levels (${(inNear / recs.length * 100).toStringAsFixed(1)}%)');

    // ── 4. Mechanic delivery vs promise ───────────────────────────────────
    print('\n== 4. MECHANIC BUDGET: PROMISED vs SHIPPED ==');
    print('sector | levels | locks want/got | relay want/got | gates want/got |'
        ' portal want/got | cores want/got');
    for (var s = 1; s <= 8; s++) {
      final sub = recs.where((r) {
        final want = budgetFor(levelId: r.id, mode: DifficultyMode.hard);
        return _sectorOf(r.id) == s && want.coreCount >= 0;
      }).toList();
      if (sub.isEmpty) continue;
      final want = budgetFor(levelId: sub.first.id, mode: DifficultyMode.hard);
      double got(int Function(Rec) f) =>
          sub.map(f).fold<double>(0, (a, x) => a + x) / sub.length;
      print('   $s   | ${sub.length.toString().padLeft(5)}  '
          '| ${want.lockCount} / ${got((r) => r.locks).toStringAsFixed(2)}      '
          '| ${want.relayCount} / ${got((r) => r.relays).toStringAsFixed(2)}      '
          '| ${want.phaseGateCount} / ${(got((r) => r.phases) - 1).toStringAsFixed(2)}      '
          '| ${want.portalPairCount} / ${got((r) => r.portals).toStringAsFixed(2)}      '
          '| ${want.coreCount} / ${got((r) => r.cores).toStringAsFixed(2)}');
    }
    final noRelayWhenWanted = recs.where((r) {
      final w = budgetFor(levelId: r.id, mode: DifficultyMode.hard);
      return w.relayCount > 0 && r.relays < w.relayCount;
    }).length;
    final noLockWhenWanted = recs.where((r) {
      final w = budgetFor(levelId: r.id, mode: DifficultyMode.hard);
      return w.lockCount > 0 && r.locks < w.lockCount;
    }).length;
    print('levels shipping FEWER relays than budgeted: $noRelayWhenWanted');
    print('levels shipping FEWER locks  than budgeted: $noLockWhenWanted');

    // ── 5. Difficulty band health ─────────────────────────────────────────
    print('\n== 5. DIFFICULTY SPREAD ==');
    void hist(String name, num Function(Rec) f, List<num> edges) {
      final buckets = List<int>.filled(edges.length + 1, 0);
      for (final r in recs) {
        final v = f(r);
        var idx = edges.length;
        for (var i = 0; i < edges.length; i++) {
          if (v < edges[i]) {
            idx = i;
            break;
          }
        }
        buckets[idx]++;
      }
      final parts = <String>[];
      for (var i = 0; i < buckets.length; i++) {
        final lo = i == 0 ? '-inf' : edges[i - 1].toString();
        final hi = i == edges.length ? 'inf' : edges[i].toString();
        parts.add('[$lo,$hi):${buckets[i]}');
      }
      print('$name  ${parts.join("  ")}');
    }

    hist('nodeCount ', (r) => r.nodes, [25, 28, 31, 34, 37, 40, 43]);
    hist('waveDepth ', (r) => r.waves, [4, 5, 6, 7, 8, 9]);
    hist('opening   ', (r) => r.open, [3, 5, 7, 9, 11, 13]);
    hist('FSR       ', (r) => r.fsr, [0.4, 0.5, 0.6, 0.7, 0.8]);
    hist('CUD       ', (r) => r.cud, [5, 7, 9, 11, 13]);
    hist('chokePts  ', (r) => r.chokes, [1, 2, 3, 5]);

    // ── 6. Three-star goal (directive) ────────────────────────────────────
    print('\n== 6. THREE-STAR DIRECTIVES ==');
    final dcount = <LevelDirective, int>{};
    for (final r in recs) {
      dcount[r.directive] = (dcount[r.directive] ?? 0) + 1;
    }
    dcount.forEach((k, v) => print('  ${k.label.padRight(10)} $v levels '
        '(${(v / recs.length * 100).toStringAsFixed(1)}%)'));
    for (var b = 0; b < 10; b++) {
      final s = recs.where((r) => r.id > b * 100 && r.id <= (b + 1) * 100);
      final set = <String>{};
      for (final r in s) {
        set.add(r.directive.label);
      }
      print('  levels ${b * 100 + 1}-${(b + 1) * 100}: ${set.join(", ")}');
    }

    // SWIFT feasibility: must clear N nodes in timeLimit/2 seconds
    final swift =
        recs.where((r) => r.directive == LevelDirective.swift).toList();
    if (swift.isNotEmpty) {
      final secsPerTap = swift
              .map((r) => (r.timeLimit / 2) / r.nodes)
              .fold<double>(0, (a, x) => a + x) /
          swift.length;
      print('  SWIFT: avg budget = ${secsPerTap.toStringAsFixed(2)} s per tap '
          '(incl. thinking time), over ${swift.length} levels');
    }
    final cascade =
        recs.where((r) => r.directive == LevelDirective.cascade).length;
    print('  CASCADE requires clearing the board in <= nodes/2 moves '
        '($cascade levels) — only possible via core-win.');

    // ── 7. Session load ───────────────────────────────────────────────────
    print('\n== 7. SESSION LOAD ==');
    final totalTaps = recs.fold<int>(0, (a, r) => a + r.nodes);
    print('total taps to clear all 1000 levels: $totalTaps');
    print('avg taps/level: ${(totalTaps / recs.length).toStringAsFixed(1)}');
    final avgTimer =
        recs.map((r) => r.timeLimit).fold<int>(0, (a, x) => a + x) /
            recs.length;
    print('avg countdown: ${avgTimer.toStringAsFixed(0)}s; '
        'range ${recs.map((r) => r.timeLimit).reduce(min)}s..'
        '${recs.map((r) => r.timeLimit).reduce(max)}s');
    final slow = recs.where((r) => r.genMs > 150).length;
    print('levels that hit/neared the 200ms generation budget: $slow');
    print('worst generation time: ${recs.map((r) => r.genMs).reduce(max)}ms');

    print('\n== REPORT COMPLETE ==');
  });
}

int _sectorOf(int levelId) {
  // 5 worlds of 25 per sector => 125 levels per sector.
  return ((levelId - 1) ~/ 125 + 1).clamp(1, 8);
}

void _render(LevelData lv, int id) {
  final m = LevelMetrics.compute(lv);
  final grid = List.generate(
      lv.gridHeight, (_) => List<String>.filled(lv.gridWidth, ' . '));
  if (lv.playCells != null) {
    for (var y = 0; y < lv.gridHeight; y++) {
      for (var x = 0; x < lv.gridWidth; x++) {
        if (!lv.playCells!.contains('$x,$y')) grid[y][x] = '   ';
      }
    }
  }
  for (final n in lv.nodes) {
    final a = switch (n.dir) {
      Direction.up => '^',
      Direction.down => 'v',
      Direction.left => '<',
      Direction.right => '>',
    };
    final tag = n.isCore
        ? '*'
        : n.kind == NodeKind.locked
            ? 'L'
            : n.kind == NodeKind.relay
                ? 'R'
                : ' ';
    grid[n.y][n.x] = '$tag$a ';
  }
  print('\n--- LEVEL $id  ${lv.gridWidth}x${lv.gridHeight}  '
      '${lv.nodes.length} nodes  waves=${m.waveDepth}  open=${m.waveZeroWidth}  '
      'FSR=${m.forcedSequenceRatio.toStringAsFixed(2)}  '
      'goal=${directiveFor(levelId: id, mode: DifficultyMode.hard).label} ---');
  for (final row in grid) {
    print(row.join());
  }
}
