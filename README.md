# Chain Pop

A minimalist extraction-based logic puzzle game built with Flutter + Flame.

---

## Gameplay

Each level presents a grid of nodes with directional arrows. Tap a node to extract it — but only if its path (in the arrow's direction) is clear. Tap in the wrong order and the node will jam. Clear the board to win.

---

## Level Generation System

### Overview

All levels are generated procedurally using the **backward-generation algorithm**, which guarantees every puzzle is solvable by construction.

### Algorithm

1. **Select positions** — Pick N unique random positions on the grid.
2. **Define solution order** — Shuffle positions to create the removal sequence. Index 0 = first node the player taps; index N-1 = last.
3. **Assign directions** — For each node at index `i`, only nodes at `i+1..N-1` are still on the board. Assign a direction whose ray does **not** pass through any of those "future" nodes.
4. **Validate** — Run `LevelValidator`, then enforce removal-wave count within each mode’s chain-length band (see below).
5. **Fallback** — If all retries fail, return a guaranteed-solvable strip layout (validator bypass; wave band not applied).

Because every direction is chosen to avoid future nodes, no deadlock can ever occur.

### Difficulty Modes

| Mode   | Grid size (typ.) | Nodes (clamped) | Density | Removal waves¹ | Auto levels |
|--------|------------------|-----------------|---------|------------------|-------------|
| Easy   | 4×4–6×6          | 4–12            | 25%     | 2–4              | 0–9         |
| Medium | 6×6–10×10        | 10–30           | 45%     | 2–6              | 10–29       |
| Hard   | 6×6–16×16        | 5–60            | 40%     | 5–10             | 30+         |

¹ *Removal waves* = how many rounds of “remove every currently extractable node at once” are needed to clear the board (parallel depth). Hard uses a slightly lower density than Medium so backward direction assignment stays reliable on larger grids. `LevelGenerator.removalWaveBounds` tiers Hard’s minimum wave floor by node count (e.g. ≤18 → min 2, ≤35 → min 3, ≤55 → min 4) so generation usually succeeds without the emergency fallback.

### Usage

```dart
import 'package:chain_pop/game/levels/generation/generation.dart';

final generator = LevelGenerator();

// Auto-derive difficulty from level ID (level 15 → medium)
final result = generator.generate(15);

// Explicit difficulty mode
final easyResult = generator.generate(50, mode: DifficultyMode.easy);
final hardResult = generator.generate(5, mode: DifficultyMode.hard);

if (result.isSuccess) {
  final level = result.value; // LevelData
} else {
  print('Error: ${result.error}');
}
```

### LevelManager (game-side API)

```dart
import 'package:chain_pop/game/levels/level_manager.dart';

// Always returns a valid LevelData — handles errors internally
final level = LevelManager.getLevel(levelId);

// With explicit difficulty
final hardLevel = LevelManager.getLevel(levelId, mode: DifficultyMode.hard);
```

---

## Architecture

```
lib/game/levels/
├── level.dart               # NodeData, LevelData, Direction
├── level_manager.dart       # Thin adapter — LevelManager.getLevel()
├── level_solver.dart        # isSolvable, countRemovalWaves, canRemove, getHint
├── level_generator.dart     # Simple seeded generator (used by level_manager)
└── generation/
    ├── generation.dart      # Barrel file — import everything from here
    ├── level_generator.dart # Full Result-based generator (DifficultyMode support)
    ├── level_validator.dart # Validates solution path completeness
    ├── level_configuration.dart # Immutable config (grid, nodes, difficulty)
    ├── difficulty_mode.dart # DifficultyMode enum
    ├── difficulty_parameters.dart # Numeric params per mode
    ├── result.dart          # Result<T, E> type
    ├── generation_error.dart # Typed errors
    └── validation_result.dart # Typed validation result
```

---

## Running Tests

```bash
# All tests
flutter test

# By category
flutter test test/deadlock_test.dart                    # 1000-level deadlock check
flutter test test/regression_test.dart                  # Level 1-5 playthroughs
flutter test test/game/levels/generation/               # All generation tests

# Performance benchmarks
flutter test test/game/levels/generation/level_generator_performance_test.dart --reporter expanded
```

### Performance Requirements

| Level Size    | Limit  |
|--------------|--------|
| ≤50 nodes    | 100 ms |
| ≤100 nodes   | 500 ms |
| ≤400 nodes   | 2000 ms|

---

## Building

```bash
# ARM64 APK (for Pixel and modern Android phones)
flutter build apk --release --target-platform android-arm64 --split-per-abi

# Fat APK (all architectures)
flutter build apk --release
```

The output APK is at: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

---

## Tech Stack

| Component | Library |
|-----------|---------|
| Engine | Flutter 3.x + Flame |
| Language | Dart |
| Storage | Hive |
| Haptics | haptic_feedback |
| Ads *(planned)* | AppLovin MAX |
| Analytics *(planned)* | GameAnalytics |
| Remote Config *(planned)* | Firebase Remote Config |
