// The shared, deterministic level sample used by the Hard and Medium reports.
// Both modes measure the *same* ids so the two batches are directly comparable.

import 'board_report_utils.dart';

const int kReportSampleSeed = 20260813;

final List<int> kReportSampleIds = sampleLevelIds(
  count: 100,
  minId: 1,
  maxId: 1500,
  seed: kReportSampleSeed,
);
