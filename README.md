# Chain Pop

A minimalist extraction-based logic puzzle game built with **Flutter + Flame**.

Tap nodes in the right order. Each node has a directional arrow — it can only be removed when nothing blocks its path. Clear the board to win. Levels are procedurally generated and always solvable.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              App Shell                                  │
│                                                                         │
│   main.dart ──► Hive + StorageService (progress, stars, difficulty)      │
│       │                                                                 │
│       ▼                                                                 │
│   MainMenuScreen ─── difficulty picker, progress summary                │
│       │                                                                 │
│       ▼                                                                 │
│   LevelSelectScreen ─── paginated chapters with drill-down              │
│       │                    (20 / 100 / 500 level tiers)                 │
│       │                                                                 │
│       ▼                                                                 │
│   GameScreen ─── generates level once, hosts Flame + HUD + win panel    │
│       │                                                                 │
├───────┼─────────────────────────────────────────────────────────────────┤
│       │               Level Pipeline                                    │
│       ▼                                                                 │
│   LevelManager.getLevel(id, mode)                                       │
│       │                                                                 │
│       ▼                                                                 │
│   LevelGenerator ─── backward-generation algorithm                      │
│       │                 positions → solution order → direction assignment│
│       │                                                                 │
│       ├──► LevelValidator ── simulates removal to verify solution path   │
│       ├──► LevelSolver ──── counts removal waves for difficulty tuning   │
│       └──► LevelConfiguration ── grid size, node count, density          │
│                                                                         │
│       ▼                                                                 │
│   LevelData ─── immutable puzzle: grid, nodes, directions, colors       │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                         Flame Engine                                    │
│                                                                         │
│   ChainPopGame (FlameGame)                                              │
│       ├── NodeComponent ──── per-node sprite: tap, extract, jam, animate│
│       ├── BoardMaskComponent ── renders void cells on irregular boards  │
│       ├── ArrowAxisGuideComponent ── optional row/column guides         │
│       └── LevelSolver ──── runtime legality (canRemove) + hints         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data flow

```
Player taps node
  → NodeComponent asks ChainPopGame.canExtract(node)
    → LevelSolver.canRemove(node, activeNodes) — ray walk along grid
      → blocked? JAM animation
      → clear?  POP animation → update activeNodes → check win
        → win? → GameScreen saves stars + unlocks next level via StorageService
```

---

## Folder Structure

```
lib/
├── main.dart                        # Bootstrap: Hive init, theme, home screen
├── screens/
│   ├── main_menu_screen.dart        # Difficulty selector, progress summary, play button
│   ├── level_select_screen.dart     # Paginated chapter view with dynamic drill-down
│   ├── game_screen.dart             # Flame GameWidget + HUD + win panel
│   └── win_overlay.dart             # Star reveal + next/retry controls
├── game/
│   ├── chain_pop_game.dart          # FlameGame: board layout, extraction logic, win check
│   ├── components/
│   │   ├── node_component.dart      # Individual node: tap handling, animations
│   │   ├── board_mask_component.dart # Dark fill for irregular board shapes
│   │   └── arrow_axis_guide_component.dart
│   └── levels/
│       ├── level.dart               # NodeData, LevelData, Direction
│       ├── level_solver.dart        # Ray-walk legality, hints, removal waves
│       ├── level_manager.dart       # Safe wrapper: generator → always-valid LevelData
│       └── generation/
│           ├── generation.dart      # Barrel export
│           ├── level_generator.dart # Backward-generation algorithm
│           ├── level_validator.dart  # Solution path verification
│           ├── level_configuration.dart
│           ├── layout_mask.dart     # Irregular board shapes (medium/hard)
│           ├── difficulty_mode.dart  # easy / medium / hard enum
│           └── difficulty_parameters.dart
├── models/
│   └── difficulty.dart              # UI metadata: colors, icons, star thresholds
└── services/
    └── storage_service.dart         # Hive persistence: unlocks, stars, preferences
```

---

## Gameplay

Each level presents a grid of nodes with directional arrows. Tap a node to extract it — but only if its path (in the arrow's direction) is clear. Tap in the wrong order and the node will jam. Clear the board to win.

Three difficulty modes scale the challenge:

| Mode   | Grid       | Nodes  | Density | Removal waves |
|--------|------------|--------|---------|---------------|
| Easy   | 4×4 – 6×6  | 4–12   | 25%     | 2–4           |
| Medium | 6×6 – 10×10| 10–30  | 45%     | 2–6           |
| Hard   | 6×6 – 16×16| 5–60   | 40%     | 5–10          |

*Removal waves = how many parallel rounds of "extract everything currently free" it takes to clear the board.*

---

## Level Generation

All levels are procedurally generated using a **backward-generation algorithm** that guarantees solvability by construction:

1. **Pick positions** — Select N random positions on the grid
2. **Define solution order** — Shuffle positions into a removal sequence
3. **Assign directions** — For each node at index `i`, assign a direction whose ray avoids all nodes at `i+1..N-1` (the ones still on the board when this node should be removed)
4. **Validate** — `LevelValidator` simulates the removal path; `LevelSolver` checks wave count fits the difficulty band
5. **Fallback** — If retries exhaust, a guaranteed-solvable strip layout is returned

Because directions are chosen against future nodes, deadlocks are impossible.

### Quick start

```dart
import 'package:chain_pop/game/levels/generation/generation.dart';

final generator = LevelGenerator();

// Auto-derive difficulty from level ID
final result = generator.generate(15); // level 15 → medium

// Explicit difficulty
final result = generator.generate(50, mode: DifficultyMode.easy);

if (result.isSuccess) {
  final level = result.value; // LevelData
}
```

---

## Level Selection UX

The level select screen uses a **dynamic telescoping** navigation that adapts to player progress:

| Progress    | Pill strip                                    |
|-------------|-----------------------------------------------|
| ≤ 100 levels| Individual 20-level pills                     |
| 100 – 500  | 100-level groups (old) + 20-level pills (recent)|
| 500+       | 500-level groups with drill-down → 100-level sub-groups → 20-level pages |

Tapping a 500-level group opens a drill-down showing its 100-level sub-groups. The screen always auto-opens on the chapter containing the player's next level, with a floating "Jump to Lvl N" button if they scroll away.

---

## Tech Stack

| Component | Library |
|-----------|---------|
| Engine    | Flutter 3.x + Flame |
| Language  | Dart |
| Storage   | Hive |
| Haptics   | haptic_feedback |

---

## Running

```bash
# Run the app
flutter run

# Run all tests
flutter test

# Run by category
flutter test test/deadlock_test.dart           # 1000-level deadlock check
flutter test test/regression_test.dart         # Levels 1–5 playthroughs
flutter test test/game/levels/generation/      # Generation subsystem

# Build APK
flutter build apk --release --target-platform android-arm64 --split-per-abi
```

### Performance Requirements

| Level size | Time limit |
|-----------|-----------|
| ≤ 50 nodes | 100 ms |
| ≤ 100 nodes | 500 ms |
| ≤ 400 nodes | 2000 ms |
