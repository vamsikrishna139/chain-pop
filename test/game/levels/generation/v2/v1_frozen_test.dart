// Gen V2 gate G1a: V1 boards must never move. Compares fresh V1 generation
// (no time budget) against the snapshot captured before any V2 change.
@Tags(['corpus'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'v1_snapshot_capture_test.dart' show computeV1Snapshot, kV1SnapshotPath;

void main() {
  test('G1a: V1 boards identical to the pre-V2 snapshot', () {
    final expected = (jsonDecode(File(kV1SnapshotPath).readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
    final actual = computeV1Snapshot();
    final moved = [
      for (final e in expected.entries)
        if (actual[e.key] != e.value) e.key
    ];
    expect(moved, isEmpty, reason: 'V1 boards moved: ${moved.take(20)}');
    expect(actual.length, expected.length);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
