# T2.9a — is the CUD floor safe to relax? **NO-GO, and for a structural reason.**

**Date:** 2026-08-21 · **Instrument:** `p2b_cud_isolation_report_test.dart`
**Tree:** T2.6 + T2.7 + relay fix. **Variants differ by one integer.**

---

## Result

Hard, L1–300, production budget:

| | A: floor as shipped | B: floor −1 | C: floor disabled |
|---|---:|---:|---:|
| candidates / level | 2.47 | **4.08** | **4.38** |
| novel / level | 0.67 | 1.04 | 1.09 |
| **rankable / level** | **0.56** | **0.57** | **0.54** |
| no-choice levels | 88.3% | 88.7% | **90.3%** |
| `in-band` exits | 124 | 127 | 124 |
| `non-novel` exits | 166 | **124** | **122** |
| `novel-out-of-band` exits | 10 | 49 | 54 |
| CUD floor rejects | 22.0% | 3.6% | 0.0% |
| gen p95 | 143 ms | **104 ms** | **101 ms** |

Medium is inert throughout — its CUD floor kills 0.4% of iterations, so there
was nothing there to relax.

**Relaxing the floor raises candidate supply 65–77% and moves the rankable rate
by nothing** (0.56 → 0.57 → 0.54). No-choice levels get slightly *worse*.

## Why it could never have worked

The CUD check sits inside the `!inBand` branch:

```dart
final inBand = evaluatorProfile.passes(metrics) && !visual.softFailed;
if (!inBand) {
  if (metrics.criticalUnlockDepth < cudFloor) continue;   // <- only here
}
```

It only ever rejects candidates that **already failed the band**. `rankable` is
defined as in-band *and* novel. So every candidate the CUD floor kills was
already unrankable, and relaxing it can only add out-of-band candidates — which
are never rankable by construction.

**This is a correction to how T2.5's mortality table should be read.** That
table counts *iteration* deaths. The DoD counts *rankable candidate* deaths.
They are different funnels, and a row can be 22.3% of one and 0% of the other.
The CUD row is exactly that. Any future lever picked off the mortality table
must be checked against which funnel it feeds before it is implemented.

## The side effect is real, and is not the DoD

Relaxing does improve *exit-path quality*: `non-novel` exits fall 166 → 124
because the extra out-of-band candidates give the fallback something novel to
ship (`novel-out-of-band` 10 → 49). Generation also gets faster, 143 → 104 ms,
since fewer iterations are spent on candidates that get thrown away.

Both are genuine. Neither serves the DoD's rankable target, and both are bought
by **shipping more out-of-band boards** — i.e. worse difficulty targeting, on
the tier where the band matters most. Not taken. If `non-novel` exit share
later becomes the binding DoD item on its own, this is a measured option with a
known price.

## Verdict

**Rejected as a supply lever.** The knob (`LevelGenerator.cudFloorRelaxation`)
stays at 0 — the shipped default — and is `@visibleForTesting` so the
experiment is repeatable rather than re-derived.

The next lever must feed the *in-band* funnel. On Hard that is `components`
(49.8% of iterations), and T2.4c's evidence closes the direct route: all-soft
put Medium composition p10 at 0.4625 against a 0.63 gate. The remaining
approach is upstream — bias construction away from candidates that are going to
fail `components` — rather than admitting them after the fact.

---

## Separate finding: **Medium composition p10 has breached its gate**

Not a CUD result — this is the current tree, measured by the real T2.4b
instrument (`composition_calibration_test`), which the isolation sweep above is
*not* a substitute for.

| shipped composition p10 | post-P2 | now | gate |
|---|---:|---:|---:|
| Medium | 0.6514 | **0.6181** | **≥ 0.63** ❌ |
| Hard | 0.6948 | 0.6764 | ≥ 0.65 ✅ |

**Medium is below the floor T2.4b calibrated.** The mechanism is a direct
consequence of P2b working: before T2.6/T2.7, ~95% of levels shipped through
the `non-novel` fallback, which selects the **best-composed** candidate it has
seen. Now Medium ships 177 of 300 via the ranked in-band path, where
composition is one term among tempo, CUD and topology — so the composition
floor is no longer being held up by the fallback's tie-break.

This is the risk the P2b checks-and-balances table named as *"composition
regresses → the T2.4b p10 floor, unchanged"*, and it has fired. It must be
resolved before the bundle is scored, and it is a ranking-weight question, not
a reason to undo T2.6/T2.7.

**Caution for whoever picks this up:** do not read composition p10 off
`LevelGenerator.visualScoresAccepted`. That list is capped by
`_kVisualScoreSampleCap` and never cleared by `resetCounters`, so it holds the
first N accepted boards — an early-level sample that reads identically across
unrelated variants. The isolation instrument above had that column and it was
removed for exactly this reason.
