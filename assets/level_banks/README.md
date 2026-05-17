# MAP-Elites Level Banks

This folder holds offline-built JSON archives produced by
`tools/map_elites_runner.dart`. The runtime loader is
`lib/game/levels/generation/level_bank.dart`.

The runner imports the live `LevelGenerator`, which in turn pulls Flutter via
the colour palette. Run it from a Flutter context (e.g. `flutter test`
harness) or refactor the colour import out before invoking with `dart run`.

The shipped `map_elites_v1.json` is an empty placeholder so the loader can
boot during development; replace it with a populated archive before
shipping Daily / Specials. The Phase 7 acceptance target is **≥ 80%
coverage** of the `(waveDepth, avgBranchingFactor)` grid (8 × 6 = 48 cells)
over a 2 000-sample run.
