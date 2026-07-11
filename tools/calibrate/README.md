# Dual-Tank Parameter Estimator (R Shiny)

Upload several `.FIT` files, build a **mean-maximal power (MMP)** curve across all of them,
and get a reasonable estimate of the parameters that feed the AnaerobicFuelTanks Connect IQ
data field.

```r
install.packages(c("shiny", "zoo", "ggplot2", "DT"))
remotes::install_github("grimbough/FITfileR")     # FIT parsing

shiny::runApp("tools/calibrate")                   # from the repo root
```

## What it does

1. **Parse** each FIT file to a 1 Hz power series (`FITfileR::readFitFile` → `records()`).
2. **MMP curve** — for a set of durations (1 s … 60 min) take the best rolling-average power
   across *all* uploaded files (cumulative-sum sliding window).
3. **CP / W′** — fit the linear work model `W = CP·t + W′` (`W = P·t`) over a chosen effort
   window (default 2–12 min). `CP` = slope, `W′` = intercept, with R².
4. **pPmax** — 5 s peak power minus CP (a practical max-anaerobic-power proxy).
5. **Export** — a parameter block formatted for the Connect IQ field settings, plus the MMP CSV.

## What is estimated vs defaulted (important)

From **single maximal efforts** the time to exhaustion is `t_lim = W′/(P − CP)` — it depends
only on total anaerobic capacity `W′` and `CP`. The **PCr/glycolytic split (`fP`)** and the
**recovery constants (`tauP`, `tauG`, `eta`, `lt1Frac`, `fatK`, `tauAer`)** do **not** change a
single all-out effort, so best efforts **cannot identify them**.

| Parameter | Source |
|---|---|
| `CP`, `Wprime` | **Fit** from best efforts (reliable) |
| `pPmax` | 5 s peak power − CP (proxy) |
| `fP`, `tauP`, `tauG`, `eta`, `lt1Frac`, `fatK`, `tauAer` | **Defaulted** — need an intermittent protocol to fit |

## Fitting the rest (future tab)

To calibrate `fP` and the recovery τ's you need **repeated / intermittent** maximal work with
known recoveries — e.g. repeated 15–30 s sprints at fixed rest, or on/off intervals to
exhaustion. The recovery pattern (how much power comes back after each rest) constrains the
per-tank capacities and recovery rates. Sketch of the added step:

1. Detect repeated maximal efforts + their recoveries in the FIT stream.
2. Simulate the dual-tank model (the same 1 Hz update as the data field) over the actual power
   trace for candidate `{fP, tauP, tauG, eta}`.
3. Minimise the error between predicted and observed power available on each successive effort
   (or predicted vs observed exhaustion points) — `optim()` / `nls`.

## Notes

- FIT files must contain a `power` record field (a power meter was paired).
- The CP linear model is robust but sensitive to the fit window — use genuine maximal efforts
  of 2–12 min and inspect the R² and the work–time plot.
- This is a **sketch**: single-file estimation, defaults for the non-identifiable parameters,
  and a clearly-marked path to the intermittent-protocol fit.
