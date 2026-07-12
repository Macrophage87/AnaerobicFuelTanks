# LLM calibration context — AnaerobicFuelTanks

Paste this whole file to an LLM (Claude, etc.) along with your ride/workout `.FIT` files (or their
power-duration numbers) to set or refine the data field's parameters. It is a standalone brief: it
describes the model the field actually runs, the twelve settings, how each is estimated, and the rules to
respect when reasoning about your rides. Keep it up to date with the field — it mirrors the current model
(see the [white paper](white-paper-dual-tank-anaerobic-model.md)).

---

## What the field is

The AnaerobicFuelTanks Connect IQ data field models cycling anaerobic capacity as **two reserves** driven
from power at 1 Hz:

- a **fast reserve** ("PCr" — purple): high-power, small, fast recovery;
- a **slow reserve** ("glycolytic" — green): lower-power, large, slow recovery, mostly at low intensity.

**Read the labels as motivation, not measurement.** The two reserves are compartments of **W′** (the work
capacity above Critical Power), named for their dominant metabolic system. They have the right *internal*
fast/slow ratio, but W′ itself recovers roughly **4× faster** than the muscle PCr/lactate the tanks are
named after — so a full "PCr bar" means the fast **W′** reserve is back, **not** that muscle
phosphocreatine has fully resynthesised. Use the bars for pacing ("punch left" / "dig left") and for
per-system training load, not as a biopsy readout.

---

## The twelve settings (key = meaning [default, typical range, unit])

Only `CP` and `Wprime` are truly fitted per athlete; the rest are literature-set defaults you refine only
when your data constrains them.

| Key | Meaning | Default | Typical range | Notes |
|---|---|---|---|---|
| `CP` | critical power | 250 | from test | W |
| `Wprime` | anaerobic work capacity above CP (W′) | 20000 | 10k–30k | J |
| `pPmax` | fast-reserve peak power above CP, at a full tank | 300 | — | W; ≈ best 1 s power − CP |
| `fP` | fast-reserve share of W′ | 0.25 | 0.20–0.25 | **assumed**, weakly identifiable |
| `tauP` | fast-reserve recovery time constant | 27 | 20–40 | s; a **W′-recovery** constant, not muscle PCr |
| `tauG` | slow-reserve recovery time constant | 470 | 300–600 | s |
| `lt1Frac` | LT1 as a fraction of CP; sets the recovery-rate band | 0.80 | 0.65–0.85 | prefer a measured LT1 |
| `eta` | **deprecated** — identity; leave at 1.0 | 1.00 | — | kept only for compatibility |
| `fatK` | slows fast-reserve recovery as the slow reserve empties | 0.75 | 0–1.5 | pH/repeated-bout slowing |
| `gFat` | **optional** glycolytic flux-fatigue exponent; **off by default** | 0.00 | 0–1.5 | leave 0 unless doing repeated-sprint analysis |
| `tauAer` | aerobic onset time constant | 25 | 15–40 | s |
| `tauOn` | glycolytic activation time constant | 6 | ~6 | s; Parolin 1999, not power-identifiable |

`Cp = fP·Wprime`, `Cg = (1 − fP)·Wprime`. A fast-reserve *depletion* kinetic `tau_dep = Cp/pPmax` also
falls out of these and is equally assumed.

---

## How to estimate each

- **`CP`, `Wprime`** — from maximal efforts spanning ~2–12 min (linear model `W = CP·t + Wprime`), or from
  intervals.icu's CP/W′. A single maximal effort obeys `t_lim = Wprime/(P − CP)` and can set **only** these
  two.
- **`pPmax`** — best ~1–5 s sprint power minus CP (read as an upper bound: at 1 s glycolysis is already
  ~15% active).
- **`fP`** — **assumed ~0.25 (band 0.20–0.25); not a routine fit target.** Power cannot identify the
  depletion split; only repeated all-out efforts with *early* recovery sampling constrain it, and even then
  weakly. Keep the default unless you have that kind of data.
- **`tauP`** — a **W′-recovery** constant, set from the W′-reconstitution curve (~27 s), *not* from muscle
  PCr. Do not "recalibrate to Bogdanis": W′ and muscle PCr do not share a time constant.
- **`tauG`, `fatK`** — identifiable **only** from a workout that actually **depleted the slow reserve** —
  repeated hard 1–3 min efforts on short rest (or short sprints on very short rest). If no session emptied
  the slow reserve, keep the defaults.
- **`lt1Frac`** — from a lactate/threshold test or intervals.icu LT1 (≈ LT1 ÷ CP). The weakest default in
  the model; worth measuring.
- **`eta`** — deprecated. Leave at 1.0.
- **`gFat`** — off (0) by default. It only matters for repeated-sprint ATP-partitioning analysis, where it
  shifts the glycolytic share toward the biopsy direction (it does not fully reproduce it). Leave 0 for
  normal use.
- **`tauAer`, `tauOn`** — literature defaults; leave near default unless you have onset-kinetics data.

---

## Model rules to respect when reasoning about rides

**Below CP (recovery / `P ≤ CP`).**
- The aerobic system covers demand → **no anaerobic draw below CP**.
- The **fast reserve** refills toward full with `tauP`, but **gated by oxidative headroom**
  `gate_p = (CP − P)/CP`: full rate stopped, near-arrested near CP. So its *effective* recovery constant is
  ~27 s only at a standstill and **100–500 s while actually pedalling** — the bar stays live through
  interval recovery valleys.
- The **slow reserve and the deficit** recover whenever `P < CP` at an **intensity-dependent rate** (fast
  at low power, slowing smoothly through the tempo band; `lt1Frac` sets the anchor band). This is **not** a
  hard on/off switch at LT1.

**Above CP (depletion / `P > CP`).**
- Both systems draw **in parallel**, not "PCr first, then glycolytic."
- Glycolysis has an **activation ramp** (`tauOn` ≈ 6 s): at effort onset the fast reserve (immediate
  buffer) covers almost everything, and glycolysis engages over the first several seconds.
- The **share** of supra-CP demand is **capacity-weighted** (`w_p = Cp`, `w_g = Cg·g`), so on a steady hard
  effort both reserves drain together and reach their nadir at exhaustion — both bars track W′bal there.
- A separate **rate ceiling** (peak flux) caps each reserve: the fast-reserve ceiling **tapers with
  fullness** (`pPmax·Rp/Cp`), the glycolytic ceiling is `0.5·pPmax·g`. The ceiling governs **maximal**
  efforts (where fast-reserve dominance emerges); it does not distort submaximal sharing.
- Demand the caps cannot place is banked as a **deficit** so combined W′bal stays energy-conserving.

**Consequences for calibration reasoning.**
- If I completed an effort the current params say is impossible (a reserve would go deeply negative), raise
  `Wprime` or speed recovery; if I was clearly maximal but the model shows lots left, lower `Wprime` or the
  recovery constants.
- The two bars are close to an affine rescaling of single-tank W′bal during steady effort — their extra
  information lives in the **transients** (the activation ramp at onset, and the fast-reserve recovery after
  hard efforts). Don't over-read small live differences on steady rides.
- **Per-system live consumption (W)** is a *modelled share*, not a measurement, whenever the rate ceiling is
  slack. The trustworthy training signal is the **cumulative per-system load** over a session
  (`PCr_depleted_kJ` / `GLY_depleted_kJ`), which distinguishes an alactic session from a glycolytic one —
  though that separation is driven by the glycolytic flux ceiling and is blind to *submaximal* alactic work,
  so treat it as descriptive, not a validated ATP partition.

---

## Iterating over time

Each time I share new workouts, tell me which parameters the new data constrains, revise **those**, and
leave the rest at default. Flag anything my data cannot constrain instead of guessing.

## Output

Return the twelve settings ready to paste into the field, marking which are well-constrained versus still
default/uncertain, and noting `eta` is deprecated (leave 1.0) and `gFat` is optional (leave 0 for normal
use).
