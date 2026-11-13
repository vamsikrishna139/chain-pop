// The Daily contract: `dayKey -> identical board`, for every player, on every
// call, regardless of what they played first.
//
// This is stronger than `level_manager_test`'s "same date yields identical
// layout", which calls twice in a row from one state. The contract that
// actually matters to players is that the board does not depend on **session
// history**, and that is the form the bug took: `LevelManager.generator` is
// static, and its `DiversityLedger` and `SilhouetteSessionTracker` are mutable
// state the T0.0a closure audit classifies as generation *inputs*.
//
// It was invisible for as long as the novelty gate was unreachable — with
// `isNovel` almost always false, every call fell through to the same
// last-resort candidate and the board looked stable. T2.6/T2.7 made the gate
// reachable and two calls for one date began returning different boards.
//
// `getDailyChallengeAsync` sidesteps it with a worker isolate that starts from
// fresh statics, but the synchronous path is both a public API and the async
// path's own fallback when `Isolate.run` throws, so the isolate cannot be the
// correctness story. `_generateDaily` now uses a fresh generator.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

String _signature(LevelData l) => l.nodes
    .map((n) => '${n.x},${n.y},${n.dir.name},${n.kind.name},${n.isCore}')
    .join('|');

void main() {
  test('the Daily board is independent of campaign history', () {
    final date = DateTime(2026, 8, 22);

    // A pristine process.
    LevelManager.generator = LevelGenerator();
    final pristine = _signature(LevelManager.getDailyChallenge(date));

    // A player who has been through a long campaign session first, so the
    // shared ledger and silhouette tracker are full.
    LevelManager.generator = LevelGenerator();
    for (var id = 1; id <= 60; id++) {
      LevelManager.generator.generate(id, mode: DifficultyMode.hard);
      LevelManager.generator.generate(id, mode: DifficultyMode.medium);
    }
    final afterCampaign = _signature(LevelManager.getDailyChallenge(date));

    expect(afterCampaign, equals(pristine),
        reason: 'The Daily board changed because campaign play preceded it. '
            'It must be a pure function of the date key — generate it from a '
            'fresh generator, never LevelManager.generator, whose diversity '
            'ledger and silhouette tracker are session state.');

    // And repeated calls must not drift, since each call also records into
    // whatever state it used.
    final again = _signature(LevelManager.getDailyChallenge(date));
    final third = _signature(LevelManager.getDailyChallenge(date));
    expect(again, equals(pristine));
    expect(third, equals(pristine),
        reason: 'Repeated Daily calls drifted, so generation is still '
            'recording into state it later reads.');

    LevelManager.generator = LevelGenerator();
  });

  // W2.2: the other half of the contract — the board must not depend on how
  // fast the device is. It used to: the Daily ran on a 400 ms stopwatch, and
  // the over-budget escape ships whatever valid board it holds when the clock
  // trips, so a slow phone (or this suite under load) got a different board.
  // These keys need 93–172 constructions unbounded (probe, 2027), i.e. well
  // past both the old 400 ms and the new work budget, so they exercise the
  // escape on every run.
  test('the Daily board does not depend on CPU load', () async {
    final heavyKeys = [
      DateTime(2027, 12, 13),
      DateTime(2027, 4, 19),
      DateTime(2027, 11, 18),
      DateTime(2027, 12, 10),
    ];
    final quiet = [
      for (final d in heavyKeys) _signature(LevelManager.getDailyChallenge(d)),
    ];

    // Saturate every core while generating again on this isolate.
    final hogs = [
      for (var i = 0; i < Platform.numberOfProcessors; i++)
        Isolate.run(() {
          final until = DateTime.now().add(const Duration(seconds: 10));
          var x = 0;
          while (DateTime.now().isBefore(until)) {
            x = (x * 31 + 7) & 0xffff;
          }
          return x;
        }),
    ];
    final loaded = [
      for (final d in heavyKeys) _signature(LevelManager.getDailyChallenge(d)),
    ];
    await Future.wait(hogs);

    expect(loaded, equals(quiet),
        reason: 'A Daily changed under CPU load, so something on the Daily '
            'path is still wall-clock driven. The Daily budget must count '
            'work (LevelManager.dailyWorkBudget), never time.');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
