# Calibration-session checklist — max-effort day

*Hand this to your coach (human or AI) when planning a max-intervals / sprint session. It lists what to
**include** in the session so the resulting `.FIT` file actually calibrates the rider's dual-tank anaerobic
model. It is **not** a prescription for the whole workout — fold these targets into the session you're
already planning, and sequence them for freshness and safety.*

---

## Why this session matters for the model

The rider uses the **AnaerobicFuelTanks** model, which tracks two anaerobic reserves from power — a **fast
reserve** ("PCr", small, quick recovery) and a **slow reserve** ("glycolytic", large, slow recovery). Only
`CP` and `W′` are fitted per athlete; the rest are literature defaults, and a few can **only be confirmed by
specific maximal efforts**. The rider's recent sprints were all **submaximal (~90%)**, so the sprint ceiling
(`pPmax`) has never actually been tested — a genuine max-effort day is what's been missing.

## Current parameters (for reference)

| Parameter | Current value | Status |
|---|---|---|
| Critical Power (`CP`) | 255 W | from intervals.icu |
| W-prime (`Wprime`) | 21472 J | from intervals.icu |
| PCr max power (`pPmax`) | ~691 W | **untested** — this session can confirm it |
| Glycolytic recovery tau (`tauG`) | 470 s | default; a to-failure set constrains it |
| LT1 fraction (`lt1Frac`) | 0.80 | measured |
| everything else (`fP`, `tauP`, `eta`, `fatK`, `gFat`, `tauAer`, `tauOn`) | defaults | not constrainable from a normal ride |

(Fuller model context, if the coach wants it, is in `llm-calibration-context.md`.)

---

## What to include — and what each confirms

### Priority 1 — one **true all-out sprint** → confirms `pPmax`
- **≤10 s, rolling start** (not from a standstill), fully rested, **genuinely maximal** (this is the whole
  point — a 90% effort does not test it).
- Reads: `pPmax ≈ best 1 s power − CP`.
- Why it's #1: it is the only effort that pushes power above `CP + pPmax`, which is what makes the PCr rate
  ceiling bind. Until that happens, `pPmax` is a guess and nothing in the ride constrains it.
- Do it **early, while fresh** (before the deep interval work), and give it a full recovery.

### Priority 2 — **maximal 3–5 min efforts** → checks `CP` / `W′`
- A couple of all-out 3–5 min efforts (the max-interval work itself, if taken to true maximum) add real
  maximal anchors to the power-duration curve.
- Reads: lets the fit **check** the current `CP 255 / W′ 21472` against this ride, rather than trusting the
  intervals.icu values blind.

### Priority 3 — **intervals to failure with consistent short recoveries** → constrains `W′` / recovery (`tauG`)
- Repeated hard efforts taken to (or near) failure, with **short, consistent recovery valleys** between
  them, drive the reserves toward empty.
- Reads: constrains how fast the slow reserve comes back (`tauG`) and pressure-tests `W′`. Long
  full-recovery rest between reps leaves recovery ambiguous, so keep the rests short and equal.

### One session can cover all three
Include one true ≤10 s sprint **and** take the intervals to failure with short rests: that exercises the
ceiling (`pPmax`), the capacity (`W′`), and the recovery (`tauG`) in a single file.

---

## What this session **cannot** calibrate (leave at defaults)
`fP`, `tauP`, `eta` (deprecated), `fatK`, `gFat`, `tauAer`, `tauOn`. These need specialised protocols
(early-recovery-sampled repeat sprints, biopsy data, onset-kinetics) or aren't identifiable from power at
all — don't design the session around them.

## Before the ride — data capture
- **Rebuild/reinstall the data field** first (`connectiq/build.sh`) so the ride embeds the config
  parameters in the FIT session message.
- The FIT will then carry: `PCr_J` / `GLY_J` (reserve energy, J), `PCr_cons` / `GLY_cons` (live W),
  `PCr_depleted_kJ` / `GLY_depleted_kJ` (session totals), **and** the config parameters the ride ran with.

## After the ride
Send the `.FIT`. With a genuine max effort in it, `pPmax` can be read directly (best 1 s − CP), `CP / W′`
sanity-checked against the maximal efforts, and `tauG` constrained if the intervals went to failure.

---

## Caveats for the coach
- **Warm up thoroughly** before max neuromuscular sprints, and sequence the fresh sprint **before** the
  glycolytic interval work — a true sprint and a to-failure VO2 set are both demanding; balance the load.
- **"90% by feel" ≠ 90% of peak watts** — the RPE→power curve is nonlinear and rider-specific, so only a
  genuinely all-out effort confirms the ceiling.
- One session gives **point estimates**; values firm up as more max-effort files accumulate.
