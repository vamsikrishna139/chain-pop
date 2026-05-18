// Phase 7 §9 — offline MAP-Elites runner.
//
// Runs `LevelGenerator.generate` N times across the difficulty modes, buckets
// each emission into the `(waveDepth × avgBranchingFactor)` feature grid,
// keeps the best level per bucket by `mapElitesQualityScore`, and writes
// `assets/level_banks/map_elites_v1.json`.
//
// Usage:
//   dart run tools/map_elites_runner.dart [--samples 2000] [--out path.json]
//
// Designed to be run **before commit** when the team wants to refresh the
// bank for Daily / Specials. Not invoked at runtime.

import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_bank.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/map_elites.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';

const _defaultSamples = 2000;
const _defaultOut = 'assets/level_banks/map_elites_v1.json';

void main(List<String> args) {
  var samples = _defaultSamples;
  var outPath = _defaultOut;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if ((a == '--samples' || a == '-n') && i + 1 < args.length) {
      samples = int.parse(args[++i]);
    } else if ((a == '--out' || a == '-o') && i + 1 < args.length) {
      outPath = args[++i];
    } else if (a == '--help' || a == '-h') {
      stdout.writeln('Usage: dart run tools/map_elites_runner.dart '
          '[--samples N] [--out path.json]');
      exit(0);
    }
  }

  final gen = LevelGenerator();
  final entries = <MapElitesEntry>[];
  var rejected = 0;
  for (var i = 0; i < samples; i++) {
    final mode = DifficultyMode.values[i % DifficultyMode.values.length];
    final result = gen.generate(i, mode: mode);
    if (result.isError) {
      rejected++;
      continue;
    }
    final level = result.value;
    final metrics = LevelMetrics.compute(level);
    final waveBucket = MapElitesFeature.waveDepthBucket(metrics.waveDepth);
    final bfBucket = MapElitesFeature.avgBranchingFactorBucket(
      metrics.averageBranchingFactor,
    );
    final quality = mapElitesQualityScore(metrics);
    entries.add(MapElitesEntry(
      waveBucket: waveBucket,
      bfBucket: bfBucket,
      qualityScore: quality,
      level: level,
    ));
    if (i % 250 == 0 && i > 0) {
      stdout.writeln('… $i samples, ${entries.length} kept, '
          '$rejected rejected');
    }
  }

  final archive = MapElitesArchive.fromEntries(entries, version: 1);
  final coverage = (archive.coverage * 100).toStringAsFixed(1);
  stdout.writeln('Done. Coverage: $coverage% '
      '(${archive.length} / ${MapElitesFeature.totalCells} cells)');

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(encodeMapElitesArchive(archive));
  stdout.writeln('Wrote $outPath');
}
