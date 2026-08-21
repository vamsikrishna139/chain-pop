# Unbound — End-to-End UI/UX Journey

A Figma-ready specification of every screen, overlay, component and state in the
app, in the order a player meets them. Written against the shipping code on
`new_improvements`, so it doubles as a design source of truth and an audit of
what actually exists.

Suggested Figma file structure — each `##` section below is one **page**, each
`###` is a **frame**, and Section 9 is the shared **component + token library**.

---

## 0. File map

| Figma page | Frames | Code |
| --- | --- | --- |
| 01 · Foundations | Tokens, type ramp, icon set, states matrix | `lib/theme/app_colors.dart`, `lib/models/difficulty.dart` |
| 02 · Launch | Splash | `splash_screen.dart` |
| 03 · Home | Main menu, settings sheet, reset dialog | `main_menu_screen.dart`, `widgets/home_settings_sheet.dart` |
| 04 · Level select | Tabs, drill-down, level grid | `level_select_screen.dart` |
| 05 · Play | HUD, board, toolbar, pause | `game_screen.dart`, `game/widgets/*` |
| 06 · Resolution | Quick win, win panel, time-up, out-of-lives | `win_panel.dart`, `quick_win_banner.dart`, `game_dialogs.dart` |
| 07 · Daily | Incident calendar, unlock dialog | `daily_challenge_calendar_screen.dart` |
| 08 · Achievements | Summary, tracks, rows | `achievements_screen.dart` |
| 09 · Monetization & privacy | Ad slots, premium, consent | `services/ads/*`, `widgets/privacy_*` |
| 10 · Flows | Journey map, first-session, returning-session | — |

---

## 1. Design foundations

### 1.1 Color tokens

All literals live in one place (`AppColors`), named by **role**, not hue.

| Token | Value | Use |
| --- | --- | --- |
| `background` | `#0F0F13` | App canvas, splash, board backdrop |
| `surface` | `#14141C` | Win panel, achievement cards |
| `surfaceDialog` | `#1A1A22` | Alert dialogs |
| `starGold` | `#FFC371` | Stars, progress fill |
| `timerCaution` | `#FFC371` | Timer 30–10 s |
| `timerWarning` | `#FF5F6D` | Timer < 10 s |

**Difficulty accents** — the accent is a *variable*, not a constant. Every
screen re-seeds its Material 3 `ColorScheme` from the currently selected mode,
so the whole app changes temperature as the player moves between tracks.

| Mode | Label | Accent | Icon |
| --- | --- | --- | --- |
| Easy | `EASY` | `#00F2FE` cyan | `bolt_outlined` |
| Medium | `MEDIUM` | `#FFC371` amber | `local_fire_department_outlined` |
| Hard | `HARD` | `#FF5F6D` coral | `whatshot` |

Derived: `dimColor` = accent @ 30 %, `boardTint` = accent @ 4 %.

**Node palette** — 6 slots, plus a parallel Okabe–Ito colorblind-safe palette
swapped in by the *High Contrast* setting. Design both variants for any frame
containing nodes.

```
Standard   #60EFFF  #00FF87  #FF5F6D  #FFC371  #A18CD1  #4FACFE
Accessible #56B4E9  #009E73  #D55E00  #E69F00  #CC79A7  #0072B2
```

### 1.2 Type ramp

Material 3 dark, with heavy weights reserved for identity and numbers.

| Role | Size / weight | Example |
| --- | --- | --- |
| Wordmark | 34 / w900, tracking 5.5→7.5 animated | `UNBOUND` |
| Screen title | `titleLarge` / w800 | "Levels" |
| Hero number | `displayMedium` / w900, tracking −1 | Frontier level |
| Section eyebrow | 10–11 / w800, tracking 1.1–2 | `LEVEL 42 · HARD` |
| Body / caption | `bodySmall` @ `onSurfaceVariant` | "Pick a stage · Stars save per level" |
| Micro-label | 9–11 / w600–w800 | HUD progress, chips |

### 1.3 Shape & elevation

| Element | Radius |
| --- | --- |
| Hero CTA | 20 |
| Cards (progression, daily) | 22–24 |
| Win panel, dialogs | 24–28 |
| Chips, toolbar buttons, tabs | 12–16 |
| Pills, banners | 20–28 |

Elevation is expressed as **accent glow**, not gray shadow:
`BoxShadow(color: accent @ 8–30 %, blur 12–40, spread −2…4)`. Frosted layers use
a 12 px backdrop blur over black @ 38 %.

### 1.4 Motion

| Moment | Spec |
| --- | --- |
| Segmented control select | 300 ms `easeOutCubic` |
| Page transitions | 350 ms `easeInOut`; splash → home cross-fade 500 ms |
| Win stars | 450 ms `elasticOut`, staggered 200 ms + 150 ms × index |
| Quick-win banner in | 320 ms `easeOutBack`, slide from −0.6 y |
| Confetti | 2900 ms, 88 particles, gravity 1.05 × min(screen) |
| Ambient drift | slow loop, **user-disableable** |

---

## 2. Launch — Splash

`SplashScreen` · ~3.9 s total, then cross-fades to Home.

**Composition (128×128 logo, centered column):**

1. **Spark** — a glowing dot appears (0–15 % of a 1500 ms timeline).
2. **Boundary** — a square draws itself in white @ 28 %, with a deliberate
   14 px gap at the top-right corner (12–55 %).
3. **Escaping arrow** — an accent stroke draws from inside the square out
   through the gap, arrowhead resolving in the last 28 % (48–92 %).
4. **Wordmark** `UNBOUND` fades up with letter-spacing expanding 1 → 6, then
   settles into a 2400 ms breathing loop between 5.5 and 7.5.
5. **Slogan** — "Find the path. Free the board." @ white 55 %.

Background: 18 deterministic dust particles drifting upward with a sine sway.

> **Design note.** The logo *is* the core mechanic — a piece escaping a bounded
> board. Keep the corner gap; it's the whole idea.

---

## 3. Home — Main menu

`MainMenuScreen` · scrolling sliver list, 20 px side padding.
Background: radial gradient from `surface`→accent @ 18 % centered at (0, −0.7).

### 3.1 Frame anatomy (top → bottom)

| Block | Content | Behavior |
| --- | --- | --- |
| **App bar row** | `Unbound` wordmark in accent, w900 · trophy icon · settings icon | Trophy → Achievements; gear → settings bottom sheet |
| **Difficulty segmented** | Three equal cards: icon + label | Tap re-themes the *entire* screen; persists selection; UI-tap SFX at 1.1× rate |
| **Progression card** | Mode icon + "{MODE} track" · huge frontier number + "Current stage" · inset panel: "Levels 41 – 60", `★ 34 / 60`, progress bar (gold→accent lerp) · two stat chips: Lifetime ★, Avg / stage | Reads `highestUnlocked`; 20-level "stretch window" aligned to map pages |
| **Daily challenge card** | Calendar icon tile · "Daily challenge" · date · 3 stars for today · chevron | → Incident calendar |
| **Tutorial button** | *Filled tertiary* when incomplete, *outlined ghost* when complete | The single most important state change on this screen |
| **Play CTA** | Filled accent, radius 20, 24 px accent glow, `play_arrow` + "Play" | → Level select at current mode |
| **Reset** | 12 px muted text: "Hold to reset all progress" | Long-press only → destructive confirm dialog |

### 3.2 States to draw

- Fresh install (frontier = 1, 0 stars, tutorial CTA prominent, empty daily stars)
- Mid-game (frontier ~60, partial stretch bar, 2/3 daily stars)
- Deep player (frontier 1,000+ — comma-formatted, compact `★ 2.8k` stats)
- Each of the three accents

### 3.3 Settings sheet (home)

Bottom sheet, drag handle, "Settings" title, accent section eyebrows:

- **Game** — Sound, Haptics, High Contrast, Aim Guide ("Show a node's exit path
  while you press"), Ambient Motion ("Enable slow background drift animations")
- **Purchases** — Remove ads / Unbound Premium, Restore purchases; snackbars for
  success, failure, and "No previous purchases found."
- **Privacy & ads** — consent controls, privacy rights sheet

### 3.4 Reset dialog

`restart_alt` icon in `error` · "Reset all progress?" · body naming exactly what
is lost and that it can't be undone · Cancel (text) + Reset (filled `error`).

---

## 4. Level select

`LevelSelectScreen` · vertical gradient: accent @ 8 % → surface → raised surface.

### 4.1 Header + tabs

- Back arrow, "Levels", subtitle "Pick a stage · Stars save per level"
- Segmented `TabBar` inside a rounded 16 container: icon + label per mode,
  indicator = accent @ 22 % fill with accent @ 45 % border. Switching tabs
  re-themes the screen and plays a pitched-up tap.

### 4.2 Drill-down navigation

The core scaling idea: the campaign runs to four digits, so navigation is a
**breadcrumb of range pills** that subdivides on tap.

```
1–700   701–710   711–720 …        ← top level (100s summary + 10s tail)
   ↓ tap
1–500   501–700                     ← >500 span splits by 500
   ↓
501–600  601–700                    ← >100 splits by 100
   ↓
601–620  621–640 …                  ← >20 splits by 20
   ↓
601  602  603 …                     ← leaf: individual levels
```

Pills auto-scroll the active range into view; the page controller opens on the
page containing the player's frontier.

### 4.3 Level card states

20 cards per page. Draw all six:

| State | Treatment |
| --- | --- |
| **Locked** | Muted fill, `lock_outline`, no tap target, semantics "Level N, locked" |
| **Next** | Locked but adjacent — semantics "next challenge" |
| **Unlocked, unplayed** | Surface container, number in `onSurface`, empty star row |
| **Completed** | Accent-tinted fill + mini star row (1–3, gold) |
| **Frontier** | The current goal — emphasized border/glow; semantics "current goal" |
| **Boss / milestone** | Flag badge overlay; on Hard, card fill picks up the **world accent** for that level range instead of the mode accent |

A "Jump to frontier" tonal button (`flag_rounded`) sits below the grid.

---

## 5. Play — the game screen

`GameScreen` · a single `Stack`: full-bleed Flame `GameWidget`, with every HUD
element and overlay layered above it in the same stack (so overlays can be
positioned against measured HUD geometry).

### 5.1 Layer order

```
┌ WinPanel / dialogs            ← top, modal
├ GamePauseOverlay              ← 12px blur + black 38%
├ GameBottomToolbar             ← bottom safe area
├ SessionGoalChip / tutorial banner
├ GameHeaderHud                 ← top safe area
├ QuickWinBanner ▸ WinCelebrationOverlay (confetti)
└ GameWidget (board)            ← bottom
```

### 5.2 Header HUD

Two rows, 16 px side padding.

**Row 1:** back chevron · centered `Integrity: 87%` (green ≥70, amber ≥50, red
below; `FittedBox` so it survives 320 px widths) · settings (`tune_rounded`) ·
lives display (3 max).

**Row 2:** left column = difficulty label *or* a mode label (e.g. daily
incident) in accent w800 tracking 1.1, with an optional 9 px mission subtitle;
center column = progress readout (`Cores: 2/5` when the level uses cores,
otherwise `14 / 30 nodes`) above a phase progress bar; right = **timer chip,
which is also the pause button**.

### 5.3 Session goal chip

A pill under the header: flag icon · "Win 3 levels" · `1/3`. Turns green
(`#00FF87`) with a check and reads `DONE` on completion. Non-interactive;
introduced for ~4 s at session start.

### 5.4 Bottom toolbar

Five 48 px circular buttons, horizontally scrollable if cramped:

| Button | Icon | Notes |
| --- | --- | --- |
| Hint | `lightbulb_outline` | Carries a 23 px **"Ad"** badge on Hard campaign and Daily, where extra hints go through a rewarded flow |
| Align lines | `grid_on` | Toggle, has a selected state |
| Zoom in | `zoom_in` | **Tutorial only** — pinch works everywhere |
| Reset view | `zoom_out_map` | |
| Undo / Restart | dual-purpose | Tap = undo (disabled when no history); **press and hold = restart** |

Every control ships an explicit `Semantics` label; the visual child is
`ExcludeSemantics`'d so screen readers get one clean node per button.

### 5.5 Pause overlay

Triggered by tapping the timer chip. 12 px backdrop blur, black @ 38 %, pointer
absorbed so the board can't be touched. Back-to-menu chevron top-left, timer
chip top-right in *emphasize-resume* styling, `PAUSED` at 28 / w900 / tracking 4,
"Tap the timer to resume" in accent, restart action, and a banner ad slot pinned
at the bottom. Announced as a route with `namesRoute` + `scopesRoute`.

### 5.6 Coaching

A ghost hint pulses the legal move after **4 s** of inactivity — dropped to
**2 s** on tutorial steps 0–1, so a brand-new player never stalls on the first
tap.

---

## 6. Resolution states

The key design decision: **not every win gets a ceremony.**

### 6.1 Quick win (clears under 20 s)

`QuickWinBanner` — a pill at 55 % height: stars, level label, optional
directive, session streak. Slides in over 320 ms, holds 1500 ms, auto-advances.
Non-interactive. No confetti, no panel, no interstitial. This exists purely to
protect flow state during fast runs.

### 6.2 Full win panel

For slower clears and milestone moments: confetti overlay + a `surface` card,
radius 28, accent border and 40 px glow.

```
LEVEL 42 · HARD                    ← eyebrow, accent, tracking 2
Complete!                          ← 26 / w900
[ DIRECTIVE: FLAWLESS · mission ]  ← optional chip
★ ★ ☆                              ← 50 px, elastic stagger, gold glow
TIME 1:24        FOULS 0           ← stat chips
🎯 Win 3 levels          2/3       ← session goal row
Menu    Retry    Next (auto 5s)    ← auto-advance ring on Next
```

Daily puzzles hide Next and the auto-advance copy entirely.

### 6.3 Time's up

Dialog on `surfaceDialog`, 24 radius, accent border: `timer_off` icon 48 px,
`TIME'S UP!` at 22 / w900 / tracking 2, "The clock ran out. Try again?", then
MENU (ghost) + RETRY (filled accent, black text). When a rewarded ad is
available, a full-width outlined **"WATCH AD TO CONTINUE"** appears — disabled
and reading `AD LOADING…` until the ad is ready.

### 6.4 Lives

3 lives per level, spent on fouls. Refilled on retry. Surfaced only in the HUD
lives display and the win panel's FOULS chip.

---

## 7. Daily — Network Incidents

`DailyChallengeCalendarScreen` · title "Network Incidents · {Month Year}".

Intro copy sets the rules honestly: *each day is a critical incident; today is
free; earlier days replay after a short ad unlock.*

7-column month grid (M T W T F S S), cells at 0.92 aspect. Cell states:

| State | Treatment |
| --- | --- |
| Future | Empty / inert |
| Today | Accent ring, free to play |
| Played | Star row (0–3) |
| In free window | Playable, no badge |
| Needs unlock | Small `lock_outline` + video badge |
| Ad-unlocked | Playable, badge cleared |

Every cell carries a composed accessibility label. Tapping a locked past day
opens the **Time Travel** dialog (`schedule` icon, `TIME TRAVEL` title, cancel +
watch-ad).

---

## 8. Achievements

`AchievementsScreen` · plain app bar on `background`.

- **Summary card** — big `earned / total` count, points earned against the
  frozen 2000-point catalog total, completion bar.
- **Track headers** — per-category with an `earned / total` counter.
- **Rows** — icon, name, description, points, locked/unlocked state, and step
  progress where the achievement is incremental.

Local-first: it reads the on-device tracker, so the full catalog is browsable
and verifiable whether or not Play Games is signed in.

---

## 9. Component library

Build these as Figma components with variants matching the code's props.

| Component | Variants |
| --- | --- |
| `DifficultySegment` | mode × selected/unselected |
| `ProgressionCard` | mode × (early / mid / deep) |
| `LevelCard` | locked · next · unplayed · completed(1–3★) · frontier · boss |
| `NavPill` | range · leaf · active · inactive |
| `GameToolbarButton` | default · selected · disabled · ad-badged |
| `TimerPauseChip` | counting · caution · warning · paused/emphasize-resume |
| `LivesDisplay` | 3 / 2 / 1 / 0 |
| `SessionGoalChip` | in-progress · complete |
| `WinPanel` | campaign · daily · with/without directive |
| `StatChip` | win-panel · home |
| `MiniStars` | 0–3 |
| `AdSlot` | banner · rewarded prompt · premium (hidden) |

Each takes `accent` as a Figma color variable so a single mode switch retints
the whole page.

---

## 10. Journey map

```
Splash ──► Home ──┬──► Level select ──► Game ──┬──► Quick win ──► next level
                  │                            ├──► Win panel ──┬─ Next
                  │                            │                ├─ Retry
                  │                            │                └─ Menu
                  │                            ├──► Time's up ──┬─ Retry
                  │                            │                └─ Rewarded continue
                  │                            └──► Pause ──────┬─ Resume
                  │                                             └─ Menu
                  ├──► Tutorial ──► Game (fixed levels, extra coaching)
                  ├──► Daily calendar ──► Game (incident) ──► Win (no Next)
                  ├──► Achievements
                  └──► Settings sheet ──► Purchases / Privacy
```

### First session

Splash (3.9 s) → Home with tutorial as a *filled* CTA → tutorial levels with
2 s coaching hints and an explicit zoom button → tutorial completes, the CTA
demotes to an outlined ghost → Play → level select opens on level 1 → first
real clear, almost certainly a quick-win banner → session goal chip appears.

### Returning session

Splash → Home shows the frontier number and stretch bar immediately → daily card
shows today's star state → Play resumes at the frontier page → wins alternate
between quick banners and full panels, with interstitials gated behind a
frustration check so they never land on a fast streak.

---

## 11. Accessibility checklist

- **High Contrast** setting swaps the node palette for Okabe–Ito — draw both.
- **Ambient Motion** off must be a complete stop, not a slowdown.
- Every icon-only control has a `Semantics` label; decorative children are
  excluded so each button is one node.
- Composed labels carry state, not just identity ("Level 42, current goal,
  2 stars").
- Pause is announced as a route.
- Narrow-width (320 px) survival is handled with `FittedBox` in the HUD — test
  the frame at 320, 375 and 430 px.
- Minimum touch target 48 px throughout the toolbar.

---

## 12. Known gaps for design attention

- **Failure feels thin.** Fouls cost lives, but there is no dedicated
  out-of-lives moment with the weight of the win panel.
- **No settings screen**, only sheets — fine today, will strain as options grow.
- **No onboarding for cores/integrity.** Those HUD readouts appear without ever
  being introduced.
- **Achievements are browse-only.** Nothing surfaces an unlock in the moment it
  happens; there is no in-game toast.
- **Daily has no leaderboard surface**, though the card layout leaves room.
