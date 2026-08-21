# P2b — the selection funnel, as measured 2026-08-21

Raw output of `p2_selection_funnel_report_test.dart` on the post-P2-bundle tree
(commit `e309e0d`). This is the evidence base for `docs/P2B_PLAN.md`.

```
--- THE FUNNEL (Hard L1-300, prod budget, n=300) ---
candidates reaching the ledger, per level : 1:94 2:82 3:60 4:30 5:17 6:11 7:5 8:1
RANKABLE candidates (in-band + novel)     : 0:288 1:11 3:1
exit path taken                           : {in-band: 12, non-novel: 286, exhausted: 90, novel-out-of-band: 2}
totals: candidates=752  novel=20  rankable=14  evaluatorRejections=2371
per level: candidates=2.51  novel=0.07  rankable=0.05
LEVELS WHERE RANKING HAD NO CHOICE (<=1 rankable): 299/300 = 99.7%
  ^ every diversity mechanism in the generator — ledger novelty, the
    silhouette streak penalty and diversity boost, T2.4c composition
    ranking, the tempo/CUD/topology comparator — chooses among these.

--- FINGERPRINT BIT ENTROPY (Hard, n=500) ---
  bit  0 sil0    p(1)=0.480  h=0.999
  bit  1 sil1    p(1)=0.546  h=0.994
  bit  2 sil2    p(1)=0.726  h=0.847
  bit  3 wave0   p(1)=0.108  h=0.494
  bit  4 wave1   p(1)=1.000  h=0.000   DEAD
  bit  5 bf0     p(1)=0.998  h=0.021
  bit  6 bf1     p(1)=1.000  h=0.000   DEAD
  bit  7 motif0  p(1)=0.002  h=0.021
  bit  8 motif1  p(1)=0.030  h=0.194
  bit  9 motif2  p(1)=0.028  h=0.184
  bit 10 dirN    p(1)=0.314  h=0.898
  bit 11 dirE    p(1)=0.274  h=0.847
  bit 12 dirS    p(1)=0.248  h=0.808
  bit 13 dirW    p(1)=0.292  h=0.871
  bit 14 dens0   p(1)=0.728  h=0.844
  bit 15 dens1   p(1)=0.812  h=0.697
  bit 16 dens2   p(1)=0.440  h=0.990
  bit 17 dens3   p(1)=0.816  h=0.689
  bit 18 dens4   p(1)=0.834  h=0.648
  bit 19 dens5   p(1)=0.670  h=0.915
  bit 20 dens6   p(1)=0.450  h=0.993
  bit 21 dens7   p(1)=0.658  h=0.927
  bit 22 dens8   p(1)=0.278  h=0.853
  bit 23 fam0    p(1)=0.256  h=0.821
  bit 24 fam1    p(1)=0.050  h=0.286
  bit 25 fam2    p(1)=0.000  h=0.000   DEAD
  DEAD bits: 3/26   effective entropy: 15.84 of 26 bits
  by field: dens=7.56b  sil=2.84b  fam=1.11b  dirN=0.90b  dirW=0.87b  dirE=0.85b  dirS=0.81b  wave=0.49b  motif=0.40b  bf=0.02b

--- CONCRETE OUTLINES PER SILHOUETTE ID ---
  (cells@grid signatures — what the player actually sees, against the
   4-family label the "lattice share" DoD item is measured on)
  asymmetric     28 distinct outlines   [organic]
  organicBlob    27 distinct outlines   [organic]
  diamond        24 distinct outlines   [geometricLattice]
  ring           16 distinct outlines   [geometricLattice]
  cross          13 distinct outlines   [geometricLattice]
  corridor       11 distinct outlines   [corridor]
  archipelago     8 distinct outlines   [archipelago]
  rectangle       4 distinct outlines   [geometricLattice]
  TOTAL distinct outlines: 131

--- NOVELTY GATE vs ACHIEVABLE DISTANCE ---
rolling nearest-neighbour Hamming over a 20-wide window:
  min=0  p25=2  median=3.00  p75=5  p90=5.00  max=9
ledger thresholds: base=5, same-visual-family=8
  share under base 5 : 74.5%
  share under 8      : 99.0%
  ^ a candidate must clear the threshold against EVERY one of the 20
    entries in the window, so these shares are a lower bound on how
    often novelty is unreachable.
```
