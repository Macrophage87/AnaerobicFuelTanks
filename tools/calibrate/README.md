# Dual-Tank Parameter Estimator (R Shiny)

A steampunk-styled calibration tool: upload **several** `.FIT` files and get one parameter set for
the AnaerobicFuelTanks Connect IQ data field, picking the best value for each parameter across all
of them — with uncertainty flags, dated YAML export, trends over time, and a PDF report.

```r
install.packages(c("shiny", "bslib", "ggplot2", "DT", "yaml"))
remotes::install_github("grimbough/FITfileR")     # FIT parsing

shiny::runApp("tools/calibrate")                   # from the repo root
```

Purple = **PCr** metabolism, green = **glycolytic** — carried through the whole UI (brass-on-walnut
`bslib` theme) and the plots.

## What it estimates

| Parameter | Source | Identifiable from best efforts? |
|---|---|---|
| `CP`, `Wprime`, `pPmax` | best across all files (combined mean-maximal power curve) | **yes** |
| `fP`, `tauP`, `tauG`, `eta` | dual-tank model fit per ride, anchored at maximal moments, aggregated | only with repeated efforts + anchors |
| `lt1Frac`, `fatK`, `tauAer` | defaults | no (need threshold / repeated-bout / onset data) |

A single maximal effort obeys `t_lim = W′/(P−CP)`, so best efforts give only `CP`/`W′`. The split
and recovery rates need repeated efforts **with** "reserve = 0" anchors.

## Estimation paths

- **Power-duration / CP–W′** — combined MMP curve across files; linear work model `W = CP·t + W′`.
- **Recovery fit** — simulate the dual-tank model (same 1 Hz update as the data field) over each ride
  and fit `fP, tauP, tauG, eta` by anchoring reserve ≈ 0 at maximal/cracked moments while keeping
  reserve ≥ 0 for the completed ride. Fits every ride; combines by **median** or **best-fit**.
- **Anchor editor** — click a ride's reserve trace to add/remove anchors (click near one to delete);
  auto-suggest / clear per ride.
- **Interval sets** — mark repeated-bout files. They constrain recovery **only when the between-bout
  refill is low** (short rest); sets with **>70% refill** are flagged as non-informative for
  `tauP`/`tauG`. The editor shows bouts / mean recovery / refill % per ride.

## Uncertainty flags

Every parameter is flagged when weakly constrained:
- `CP`/`W′` — low R², few efforts, or a narrow duration range.
- `pPmax` — no clear maximal sprint (best 5 s not well above CP).
- `fP`/`tau…` — no ride constrained recovery (all rests too long / too few bouts), or a wide spread
  across rides. Per-ride flags (`few-bouts`, `rest-too-long`, `no-converge`, `poor-fit`) highlight
  rows in the fit table.

## Races and hard group rides

They work — rich in repeated near-maximal surges. The one requirement is **anchors**: mark where you
were at the limit. The best natural anchor is **getting dropped** (a real reserve-0 event).

## Export, history & trends

- **Export dated YAML reading** — appends the current estimate (with a datestamp and the list of
  flagged params) to any supplied history, producing a multi-reading YAML.
- **History YAML** — supply a previous export to unlock the **Trends** tab: each tracked value plotted
  over time (small multiples) plus a table.
- **Export PDF report** — a page explaining where each parameter stands (value, source, and whether
  it's well-constrained or uncertain and why), followed by the MMP, CP-fit, and trend plots.

## Notes

- FIT files must contain a `power` record field.
- Fonts load from Google (`Cinzel`, `EB Garamond`) at startup — needs a network connection the first
  time; swap `font_google(...)` for local fonts to run fully offline.
- The recovery fit uses `optim` (L-BFGS-B); the feasibility/anchor weighting is a tunable constant —
  inspect per-ride objectives and reserve traces before trusting values.
- This is a **sketch**: it runs, but validate the fits on your own data before racing on the numbers.
