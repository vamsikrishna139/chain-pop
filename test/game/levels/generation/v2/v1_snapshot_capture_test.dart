// Captures V1 board fingerprints (no time budget => logic-only, machine
// independent). Run once BEFORE Gen V2 changes; v1_frozen_test compares.
//   CAPTURE_V1=1 flutter test test/game/levels/generation/v2/v1_snapshot_capture_test.dart
// ignore_for_file: avoid_print
@Tags(['report'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_fingerprint.dart';

const kV1SnapshotPath = 'test/game/levels/generation/v2/v1_snapshot.json';
const kV1SnapshotCount = 120;

Map<String, int> computeV1Snapshot() {
  final out = <String, int>{};
  for (final mode in DifficultyMode.values) {
    final gen = LevelGenerator();
    for (var id = 1; id <= kV1SnapshotCount; id++) {
      final r = gen.generate(id, mode: mode);
      out['${mode.name}:$id'] =
          r.isSuccess ? fingerprintHash(boardFingerprint(r.value)) : -1;
    }
  }
  for (var i = 0; i < 20; i++) {
    final d = DateTime(2026, 11, 1).add(Duration(days: i));
    final key = d.year * 10000 + d.month * 100 + d.day;
    final r = LevelGenerator.neutral().generateDailyChallenge(key, workBudget: 64);
    out['daily:$key'] = r.isSuccess ? fingerprintHash(boardFingerprint(r.value)) : -1;
  }
  return out;
}

void main() {
  test('capture v1 snapshot', () {
    if (Platform.environment['CAPTURE_V1'] != '1') {
      markTestSkipped('set CAPTURE_V1=1 to (re)capture');
      return;
    }
    final snap = computeV1Snapshot();
    File(kV1SnapshotPath)
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(snap));
    print('captured ${snap.length} fingerprints');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
