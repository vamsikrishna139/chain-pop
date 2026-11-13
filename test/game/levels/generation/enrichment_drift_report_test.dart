// W2.6 / audit P2-1 — how far do difficulty metrics move between the board the
// band is checked on and the board the player gets?
//
// The generator scores the *raw* retrograde board (`LevelMetrics.compute` in
// `_attemptDirectorDrivenGeneration`) and only afterwards runs `enrichLevel`,
// which adds cores, locks, relays and phase groups. Locks and phase gates
// change what is legal to tap, so every band guarantee is about a board that
// never ships. This measures the gap; it changes nothing.
//
// Raw reconstruction: enrichment never moves a node or turns its arrow on the
// shipped board (the only `rotatedCw` is inside the relay-safety simulation),
// so resetting kind / isCore / phaseGroup recovers the scored board exactly.
//
// DECISION RULE — fixed before the first run:
//   For each tier, let LEAVE = boards whose raw metrics pass the tier's
//   `DifficultyProfile.passes` but whose enriched metrics do not, as a share of
//   boards that pass raw.
//   * LEAVE < 5% in every tier  -> document the drift and close P2-1.
//   * LEAVE >= 5% in any tier   -> open a follow-up to re-check the band after
//     enrichment. That changes shipped boards, so it falls under the Gen V1
//     freeze rule (WAVE2 plan §2) and needs its own sign-off.
//
// Run one population per process (they are independent and slow):
//   flutter test test/game/levels/generation/enrichment_drift_report_test.dart \
//     --plain-name "drift medium"
// Each writes docs/playtests/enrichment_drift/<population>.md.
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:io';

import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

LevelData _raw(LevelData l) => LevelData(
      levelId: l.levelId,
      gridWidth: l.gridWidth,
      gridHeight: l.gridHeight,
      playCells: l.playCells,
      portalPairs: l.portalPairs,
      silhouetteId: l.silhouetteId,
      nodes: [
        for (final n in l.nodes)
          n.copyWith(kind: NodeKind.normal, isCore: false, phaseGroup: 0),
      ],
    );

bool _hasMechanics(LevelData l) => l.nodes.any(
    (n) => n.kind != NodeKind.normal || n.phaseGroup != 0);

class _Metric {
  _Metric(this.name, this.read);
  final String name;
  final num Function(LevelMetrics) read;
  final deltas = <double>[];
}

class _Drift {
  _Drift(this.population, this.tier);

  final String population;
  final DifficultyTier tier;
  late final profile = DifficultyProfile.forTier(tier);

  final metrics = [
    _Metric('firstLegalMoveCount', (m) => m.firstLegalMoveCount),
    _Metric('waveZeroWidth', (m) => m.waveZeroWidth),
    _Metric('waveDepth', (m) => m.waveDepth),
    _Metric('FSR', (m) => m.forcedSequenceRatio),
    _Metric('avgBF', (m) => m.averageBranchingFactor),
    _Metric('CUD', (m) => m.criticalUnlockDepth),
  ];

  int n = 0, withMechanics = 0, passRaw = 0, passEnr = 0, leave = 0, enter = 0;
  final leaveReasons = <String, int>{};
  final leaveExamples = <String>[];

  void add(String label, LevelData shipped) {
    n++;
    if (!_hasMechanics(shipped)) {
      // Cores alone do not change legality, so raw == enriched for metrics.
      final m = LevelMetrics.compute(shipped);
      for (final x in metrics) {
        x.deltas.add(0);
      }
      if (profile.passes(m)) {
        passRaw++;
        passEnr++;
      }
      return;
    }
    withMechanics++;
    final raw = LevelMetrics.compute(_raw(shipped));
    final enr = LevelMetrics.compute(shipped);
    for (final x in metrics) {
      x.deltas.add((x.read(enr) - x.read(raw)).toDouble());
    }
    final r = profile.passes(raw), e = profile.passes(enr);
    if (r) passRaw++;
    if (e) passEnr++;
    if (r && !e) {
      leave++;
      final why = _firstFailure(enr);
      leaveReasons[why] = (leaveReasons[why] ?? 0) + 1;
      if (leaveExamples.length < 8) {
        leaveExamples.add('$label ($why: raw ${_show(raw, why)} -> '
            'enriched ${_show(enr, why)})');
      }
    }
    if (!r && e) enter++;
  }

  String _firstFailure(LevelMetrics m) {
    final p = profile;
    if (!p.averageBranchingFactor.contains(m.averageBranchingFactor)) {
      return 'avgBF';
    }
    if (!p.firstLegalMoveCount.contains(m.firstLegalMoveCount)) {
      return 'firstLegalMoveCount';
    }
    if (!p.criticalUnlockDepth.contains(m.criticalUnlockDepth)) return 'CUD';
    if (!p.forcedSequenceRatio.contains(m.forcedSequenceRatio)) return 'FSR';
    if (!p.waveDepth.contains(m.waveDepth)) return 'waveDepth';
    if (m.forcedSequenceRatio >
        DifficultyProfile.fsrCapForNodeCount(m.nodeCount)) {
      return 'FSR cap';
    }
    return 'waveZeroWidth';
  }

  String _show(LevelMetrics m, String metric) => switch (metric) {
        'avgBF' => m.averageBranchingFactor.toStringAsFixed(2),
        'firstLegalMoveCount' => '${m.firstLegalMoveCount}',
        'CUD' => '${m.criticalUnlockDepth}',
        'FSR' || 'FSR cap' => m.forcedSequenceRatio.toStringAsFixed(2),
        'waveDepth' => '${m.waveDepth}',
        _ => '${m.waveZeroWidth}',
      };

  String report() {
    String pct(int a, int b) =>
        b == 0 ? '—' : '${(100 * a / b).toStringAsFixed(1)}%';
    double q(List<double> s, double p) => s[((s.length - 1) * p).round()];
    final b = StringBuffer()
      ..writeln('## $population (tier: ${tier.name})')
      ..writeln()
      ..writeln('- boards: $n; with locks/relays/phase gates: '
          '$withMechanics (${pct(withMechanics, n)})')
      ..writeln('- pass band raw: $passRaw (${pct(passRaw, n)}); '
          'pass band enriched: $passEnr (${pct(passEnr, n)})')
      ..writeln('- **LEAVE** (pass raw, fail enriched): $leave = '
          '**${pct(leave, passRaw)} of raw-passing boards**')
      ..writeln('- ENTER (fail raw, pass enriched): $enter')
      ..writeln()
      ..writeln('| metric (enriched − raw) | mean | p5 | p50 | p95 | '
          'boards changed |')
      ..writeln('|---|---|---|---|---|---|');
    for (final x in metrics) {
      final s = [...x.deltas]..sort();
      final mean = s.isEmpty ? 0 : s.reduce((a, c) => a + c) / s.length;
      final changed = s.where((d) => d != 0).length;
      String f(num v) => v is int || v == v.roundToDouble()
          ? v.toStringAsFixed(v.abs() < 1 && v != 0 ? 2 : 0)
          : v.toStringAsFixed(2);
      b.writeln('| ${x.name} | ${mean.toStringAsFixed(2)} | '
          '${s.isEmpty ? '—' : f(q(s, 0.05))} | '
          '${s.isEmpty ? '—' : f(q(s, 0.5))} | '
          '${s.isEmpty ? '—' : f(q(s, 0.95))} | ${pct(changed, n)} |');
    }
    if (leaveReasons.isNotEmpty) {
      final sorted = leaveReasons.entries.toList()
        ..sort((a, c) => c.value.compareTo(a.value));
      b
        ..writeln()
        ..writeln('LEAVE by first failing check: '
            '${sorted.map((e) => '${e.key}=${e.value}').join(', ')}')
        ..writeln()
        ..writeln('Examples: ${leaveExamples.join('; ')}');
    }
    return b.toString();
  }
}

void _write(_Drift d) {
  final out = File('docs/playtests/enrichment_drift/${d.population}.md');
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(d.report());
  print(d.report());
}

void _campaign(DifficultyMode mode) {
  final d = _Drift('campaign_${mode.name}_L1-1000',
      DifficultyProfile.tierFromMode(mode));
  final gen = LevelGenerator.neutral();
  for (var id = 1; id <= 1000; id++) {
    final r = gen.generate(id, mode: mode);
    expect(r.isSuccess, isTrue, reason: '${mode.name} L$id');
    d.add('L$id', r.value);
  }
  _write(d);
}

void main() {
  test('drift easy', () => _campaign(DifficultyMode.easy),
      timeout: const Timeout(Duration(minutes: 60)));
  test('drift medium', () => _campaign(DifficultyMode.medium),
      timeout: const Timeout(Duration(minutes: 60)));
  test('drift hard', () => _campaign(DifficultyMode.hard),
      timeout: const Timeout(Duration(minutes: 60)));

  test('drift daily', () {
    final d = _Drift('daily_2027', DifficultyTier.expert);
    var day = DateTime(2027, 1, 1);
    while (day.year == 2027) {
      final key = day.year * 10000 + day.month * 100 + day.day;
      final r = LevelGenerator.neutral().generateDailyChallenge(
        key,
        workBudget: LevelManager.dailyWorkBudget,
      );
      expect(r.isSuccess, isTrue, reason: 'daily $key');
      d.add('$key', r.value);
      day = day.add(const Duration(days: 1));
    }
    _write(d);
  }, timeout: const Timeout(Duration(minutes: 60)));
}
