# Unbound (Chain-Pop) — Comprehensive End-to-End Architecture & Production State

This document is the master source of truth for **Unbound: Arrow Puzzle** (formerly Chain-Pop). It details the core gameplay mechanics, the procedural generation engine, UI/UX architecture, and the current production state (based on the latest codebase audit).

---

## 1. Game Overview & Mechanics

**Unbound** is an extraction-based spatial logic puzzle built on the Flame engine embedded within a Flutter application. 

### 1.1 The Core Loop
The player observes a grid of nodes (arrows). A node can be extracted only if its "ray" (its straight-line path to the edge of the board in the direction of its arrow) is completely unobstructed by other nodes. 
- **Extraction (Pop)**: Tapping a valid node removes it, plays a pop animation, increments the extraction streak, and potentially frees other nodes.
- **Blocked Tap (Jam)**: Tapping an obstructed node triggers a "Jam" animation, haptic feedback, and a penalty to **Network Integrity**.
- **Hint System**: After repeated jams on a single node, the engine visually flashes the blocking node as a hint.

### 1.2 Node Mechanics
1. **Normal Nodes**: Standard directional arrows.
2. **Locked Nodes**: Require adjacent (4-neighbor) nodes to be cleared before they become extractable.
3. **Relay Nodes**: Upon extraction, a relay node rotates its entire row or column 90° clockwise.
4. **Core Nodes**: Critical infrastructure. Instead of "clear 25/25 nodes", some levels define a win condition based on extracting N Core nodes. 
5. **Phase Gates & Portals**: Advanced mechanics intended for later worlds (Note: Portals currently suffer from coordinate decoding defects and rendering omissions).

### 1.3 Meaning & Stakes (Network Integrity)
The game is transitioning from anonymous Sudoku-like boards to a **Narrative System Incident**. 
- **Network Integrity**: Starts at 100%. A jammed tap reduces integrity by 8%. If integrity drops below 70%, the timer speed increases by 1.25x. Below 50%, atmospheric red vignettes and static appear.
- **Cascade Finale**: Once the final Core node is restored on a winning level, a rippling "Cascade Finale" auto-clears all remaining infrastructure nodes radially from the last core, creating a massive payoff.

---

## 2. Procedural Generation Engine (Retrograde Construction)

To guarantee that a level is 100% solvable without falling into NP-complete forward-solver searches, Unbound uses **Retrograde Construction**. Levels are generated backwards.

### 2.1 The Monotonicity Principle
> *Placing a node blocks a ray. Removing a node frees a ray. If a ray is clear when the node is placed during backward construction, it is guaranteed to be clear when the player encounters it moving forward.*

### 2.2 The Generation Pipeline
1. **Configuration**: Defines targets (grid span, node count) based on level ID and tier (Easy, Medium, Hard, Expert/Daily).
2. **The Director**: Chooses an **Archetype** (Clean Authored, Organic Messy, Strong Motif) which sets the Softmax Scorer temperature and heuristics. It selects a visual Silhouette (Cross, Archipelago, Diamond).
3. **Retrograde Constructor**: Starting from a single seed cell, the constructor maintains a `FrontierSet`. It evaluates all `(cell, direction)` pairs using a Scorer:
   - **Fanout**: Prioritizes placements that branch the structure.
   - **Minimum Remaining Values (MRV)**: Prioritizes highly constrained interior pockets.
   - **Isolation Penalty**: Prevents the generator from sealing single-cell dead ends.
   - **Motif Injection**: At specific occupancy thresholds (e.g., 55%), pre-reserved Motifs (e.g., lock clusters, escape chords) are force-injected into the sequence.
4. **Quality Evaluator (`DifficultyProfile`)**: The generated candidate is graded against the required difficulty band parameters.
5. **Diversity Ledger**: Candidate fingerprinting (23-bit hash). The candidate is rejected if its Hamming distance is too close to recently played levels, ensuring visual diversity.
6. **Grid Packing**: To prevent nodes from scattering thinly across a large 9x9 grid, `level_configuration` dynamically clamps the board to a tight 6x6 - 8x8 span, improving visual density and tap target sizes.

---

## 3. Difficulty Bands & Balancing Reality

The most significant structural constraint of the generator is the **Opening Width** (or `waveZeroWidth` - the number of nodes legally extractable on turn 1).

### 3.1 The "3-5" Opening Fallacy
The original design intent was for Hard/Expert boards to offer only 3-5 legal opening moves to create high cognitive tension. However, mathematical analysis proved that forcing a 3-5 opening is **structurally impossible** under the current retrograde logic due to *geometric starvation*. 
Because low-ID nodes (the first ones the player removes) are placed *last* by the backward generator, they do not land on the rays of other nodes to block them.
**Resolution**: The opening difficulty band has been honestly recalibrated to `[3, 11]`. The generator is designed to produce 8-11 width openings on Hard boards, and the validation tests reflect this truth.

### 3.2 Forced Sequence Ratio (FSR)
FSR dictates how much of the level is a "forced path" (only one valid move). Medium boards previously suffered a 0.65 FSR cap, forcing over 70% of generated candidates to be rejected. The FSR limits have been widened to respect the reality that **node density actually lowers FSR** (more nodes = more parallel options).

---

## 4. UI/UX Journey Architecture

The game uses a unified **Stack** approach: A full-bleed Flame `GameWidget` sits at the bottom, with Flutter HUD elements floating safely on top based on dynamic device insets.

### 4.1 Visual Hierarchy & Identity
- **Dynamic Themes**: The entire app's `ColorScheme` changes based on the selected mode: Easy (Cyan), Medium (Amber), Hard (Coral).
- **Zoom & Pan**: The Flame board supports pinch-to-zoom and panning. The layout mathematically caps the grid size so it perfectly fits the phone's playable safe-area. Tap targets dynamically scale to at least 40px on standard grids.
- **Accessibility**: Includes an Okabe-Ito high-contrast colorblind node palette, sound/haptic toggles, and ambient motion toggles (though reduced-motion coverage needs expanding).

### 4.2 Screens & Flow
- **Home/Level Select**: Telescoping breadcrumbs (e.g., 1-500 -> 501-600 -> 601-620) allowing players to navigate a campaign of 1000+ levels smoothly.
- **Play Screen**: Top HUD contains Back, Integrity %, Lives, Mode Label, Progress Bar. Bottom toolbar contains Hint, Align Lines, Zoom/Reset, and Undo/Restart.
- **Daily Calendar (Network Incident)**: Daily challenges presented as a monthly calendar. Past days can be unlocked via rewarded ads (Time Travel).

---

## 5. Current Production Audit (The Deficiencies)

A deep technical audit of branch `new_improvements` (`c747e4f`) has identified several P0 and P1 gaps that **must be fixed prior to launch**:

### 5.1 P0 Release Blockers (Critical)
1. **Unobservable Product**: No Analytics service exists. `FirebaseAnalytics.instance.logAppOpen()` is the only event tracking. Crashes silently fail due to a placeholder `google-services.json` API key.
2. **Ad-Flow Timers**: Rewarded ads for hints do not pause the game timer. A player watching a 30s ad can lose the level while watching it.
3. **Rewarded Ad Hangs**: If the AdMob SDK fails to deliver a terminal callback on dismissal, `await ad.show` hangs indefinitely with no timeout, soft-locking the UI.
4. **Loss of Won Levels**: The "Restart" button remains active during the ~1.7s Cascade Finale ripple effect. Tapping restart aborts the finale and the win is never recorded.
5. **Corrupt Save Boot-loop**: Hive box initialization (`Hive.openBox`) lacks a try/catch. A corrupted save file crashes the app on launch rather than purging the data.
6. **Untested Monetization**: RevenueCat initialization drops if network fails, removing premium ad-free status permanently for that session. Release builds silently fall back to debug signing keys.

### 5.2 P1 Design & Architecture Gaps
1. **Campaign Framing Mismatch**: The campaign uses world names like "The Lock" (Lvl 26-50) and "Relay Storm" (Lvl 51-75). However, Medium difficulty budgets explicitly return `0` locks and `0` relays until Level 126. Players experience 125 levels of identical mechanics and identical Cyan palettes.
2. **Broken Portals**: Portals are broken on four levels:
   - Cell key coordinate decoding uses modulo-1000 math, causing out-of-bounds ray tracing.
   - `enrichLevel()` accidentally strips `portalPairs` from the generated level payload.
   - `BoardMaskComponent` has no render logic for portals.
   - The relay softlock proof mathematical test does not account for portals.
3. **Milestone Level Starvation**: 40% of hand-authored milestone seeds (like Boss levels) are silently failing evaluator constraints and fallback-shipping as standard procedurally generated boards.
4. **Idle Hint Stealing**: The ghost-hint system (activating after 4 seconds of idle time) accidentally decrements the player's hard-earned "Free Hint" budget without their consent.

---

## 6. Execution Priority for Launch

To reach launch readiness, engineering efforts must shift **away from the procedural generation engine** (which is mature, solved, and structurally sound) and strictly toward **wrapping the game in a robust production shell**:

1. **Instrument the App**: Implement `AnalyticsLocator`. Track Level Start/End, Node Jams, Rewarded Ad Funnels, and Purchases. Fix the Firebase Crashlytics API keys.
2. **Fix Ad/Timer Safety**: Pause `GameTimerController` when ad overlays are active. Implement 45s timeouts on all `await ad.show()` calls. Disable UI interaction during the Cascade Finale.
3. **Re-align Progression**: Ensure World 1-5 have distinct color palettes. Move the first Lock Node and Relay Node introductions down into the first 50 levels of Medium difficulty so players experience mechanics before they abandon the app. Fix the `enrichLevel()` portal deletion.
4. **Fix Milestone Seeds**: Disable mechanic-floor validations on explicitly requested milestone seeds so Authored Boss levels always ship successfully.
