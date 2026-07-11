# Dual-Tank Parameter Estimator (R Shiny)

Upload **several** `.FIT` files and get one parameter set for the AnaerobicFuelTanks Connect IQ
data field, picking the best value for each parameter across all of them.

```r
install.packages(c("shiny", "ggplot2", "DT"))
remotes::install_github("grimbough/FITfileR")     # FIT parsing

shiny::runApp("tools/calibrate")                   # from the repo root
```

## Two estimation paths

### 1. Best efforts → `CP`, `W′`, `pPmax`  (identifiable, best-of-all files)

- Parse every file to a 1 Hz power series and build a combined **mean-maximal power (MMP)** curve
  — the best rolling-average power per duration **across all files**.
- Fit the linear work model `W = CP·t + W′` over a chosen window (default 2–12 min).
- `pPmax` = best 5 s power (across files) − CP.

These take the **best value across all uploaded rides** automatically (the MMP curve is the
per-duration max), so more files → a better power-duration envelope.

### 2. Recovery fit → `fP`, `tauP`, `tauG`, `eta`  (across all rides)

A single maximal effort obeys `t_lim = W′/(P−CP)`, so it can't reveal the tank split or recovery
rates. Those only show up across **repeated efforts with recovery**, and only when a ride has
moments where the rider was genuinely **maximal / cracked** (reserve ≈ 0).

The app simulates the dual-tank model (the same 1 Hz update as the data field) over each ride and
fits `fP, tauP, tauG, eta` by:

- **anchoring** reserve ≈ 0 at maximal/cracked moments — set with a **click-to-anchor editor**
  on each ride's reserve trace (click to add, click near one to remove), or auto-suggested at the
  ride's lowest-reserve points, and
- keeping reserve ≥ 0 for the whole (completed) ride — an infeasibility penalty.

It fits **every uploaded ride**, shows a per-ride table, and combines them by **median** (robust)
or **best-fit** (lowest objective). Use rides whose hard efforts had **different recovery
lead-ins** (a fresh sprint vs a sprint after repeated surges) to separate fast PCr recovery from
slow glycolytic recovery.

## Can you estimate from a race or hard group ride?

**Yes.** Races and hard group rides are full of repeated near-maximal surges with varied recovery —
ideal for the recovery fit. The one requirement is **anchors**: mark (or let the app auto-suggest)
the moments you were at the limit. The best natural anchor is **getting dropped** — the instant you
can't hold the wheel is a real "reserve = 0" event. A completed ride with *no* anchors only tells
you the parameters are *feasible* (reserve never went negative), which bounds them but doesn't
identify them.

| Parameter | Source |
|---|---|
| `CP`, `Wprime`, `pPmax` | Best across all files (combined MMP) |
| `fP`, `tauP`, `tauG`, `eta` | Fit per ride at maximal anchors, combined (median / best-fit) |
| `lt1Frac`, `fatK`, `tauAer` | Defaulted (need a threshold / repeated-bout protocol) |

## Notes / extensions

- The **Anchor editor** tab lets you click each ride's reserve trace to place/remove anchors;
  rides with no manual anchors fall back to auto-suggested lowest-reserve points.
- `lt1Frac` needs a lactate/threshold test; `fatK`/`tauAer` need repeated-bout data to identify.
- The fit uses `optim` (L-BFGS-B, bounded). Weighting between the feasibility and anchor terms is a
  tunable constant — inspect the per-ride objective and reserve traces before trusting values.
- FIT files must contain a `power` record field (a power meter was paired).
- This is a **sketch**: it runs, but validate the fits on your own data before racing on the numbers.
