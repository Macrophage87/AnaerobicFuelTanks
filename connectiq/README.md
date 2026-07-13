# Dual-Tank Anaerobic Reserve — Connect IQ data field

A Garmin Connect IQ **data field** that tracks the reserve, consumption, and depletion of two
anaerobic energy systems live from cycling power:

- **PCr (phosphocreatine / alactic)** — purple bar, "how much punch is left"
- **GLY (glycolytic / lactic)** — green bar, "how much sustained dig is left"

Each tank fills with the reserve fraction and is labelled with the **raw reserve in kJ** (divide by
the tank's capacity for %); it is **dull** when idle/recovering, **bright** when that system is
actively being drained, and turns **solid red and flashes** when the tank empties. The bars have
rounded, tank-like ends.
It implements the reduced dual-tank model in
[`../docs/white-paper-dual-tank-anaerobic-model.md`](../docs/white-paper-dual-tank-anaerobic-model.md);
the full field/UI/FIT spec is in
[`../docs/connectiq-app-spec-and-prompt.md`](../docs/connectiq-app-spec-and-prompt.md).

## What it records to the FIT file

- **Per second (record stream):** `PCr_pct`, `GLY_pct` (reserve %), plus `PCr_cons`, `GLY_cons` (live W).
- **Per ride (session summary):** `PCr_depleted_kJ`, `GLY_depleted_kJ` — total energy drawn from each
  system over the ride. These sync to Garmin Connect and flow on to intervals.icu / Strava.

## Project layout

```
connectiq/
├─ manifest.xml                     app id, product list, min API level
├─ monkey.jungle                    build config
├─ source/
│  ├─ DualTankApp.mc                AppBase entry point
│  └─ DualTankView.mc               the data field: model + rendering + FIT
└─ resources/
   ├─ drawables/ (launcher icon)
   ├─ strings/strings.xml
   └─ settings/ (properties.xml defaults + settings.xml UI)
```

## Settings (edit in Garmin Connect → the field's settings)

| Key | Meaning | Default |
|---|---|---|
| `CP` | critical power (W) | 250 |
| `Wprime` | total work above CP (J) | 20000 |
| `fP` | PCr share of W′ (0–1) — weakly identified | 0.25 |
| `pPmax` | PCr peak power above CP (W), immediate rate cap (~1 s peak − CP) | 300 |
| `tauP` | PCr recovery time constant (s) | 22 |
| `tauG` | glycolytic recovery time constant (s) | 360 |
| `lt1Frac` | LT1 as a fraction of CP — **set from a measured LT1**, not left at default | 0.80 |
| `eta` | PCr recovery-rate efficiency (rescales τ_p; degenerate with tauP) | 0.80 |
| `fatK` | fatigue slowing of PCr recovery (0 disables) | 0.75 |
| `tauAer` | aerobic ramp time constant, s (0 = hard CP edge) | 25 |
| `tauOn` | glycolytic activation time constant, s (how fast glycolysis ramps in) | 6 |

> `fP` is assumed and weakly identified (not measured) — personalize it (and the τ's, and `lt1Frac`
> from a real LT1 test) per athlete. Above CP the two systems drain **in parallel**, PCr-weighted
> (glycolytic peak rate is fixed at half the PCr peak, an internal modeling assumption).

### Realism terms (now built in, tunable)

- **Aerobic ramp (`tauAer`)** — below CP the aerobic system covers demand, so PCr does **not**
  deplete while you ride below CP; above CP a sticky, floored aerobic tracker ramps toward CP, so
  the onset of a hard effort draws the tanks down and tapers as aerobic catches up. Set
  `tauAer = 0` for a hard CP edge.
- **Fatigue-slowed PCr recovery (`fatK`)** — `τ_p,eff = τ_p · (1 + fatK·(1 − rG/cG))`, so PCr
  resynthesis slows as the glycolytic tank empties (the observed bout-to-bout slowing). Set
  `fatK = 0` to disable.

### Layout

The field **adapts to the data-field cell**, with **vertical tanks as the standard look**; it only
falls back to horizontal bars for a strip too short for a legible vertical bar:
- **large single field** (`w ≥ 200 & h ≥ 240`) → vertical tanks on top + a **summary panel**
  (per-system depleted kJ and a fatigue level);
- **any field tall enough** (`h ≥ 74`) → two vertical tanks **side by side** — the default, covering
  full-screen, half-screen, 1×2, and 2×2 cells;
- **short & wide strip** (`w ≥ 2h`) → two horizontal bars **side by side** (PCr | GLY);
- **short strip** → two horizontal bars **stacked**.

Text/outline color also adapts to the background luminance (light & dark themes).

### Pause / resume

Depletion is **frozen while the timer is paused or stopped** (nothing accumulates). On resume the
tanks are **recovered in closed form for the entire elapsed pause** (rest recovery), so a long stop
refills them correctly even if the device stops calling `compute()` while paused. A full activity
reset re-fills the tanks and zeroes the session kJ totals.

## Build & run

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and a device developer key.

```bash
# from this connectiq/ directory

# 1. one-time: generate a developer key if you don't have one
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt

# 2. build (wrapper handles paths); default device edge840
./build.sh              # or: ./build.sh edge1040

# --- or the raw commands the wrapper runs ---
monkeyc -d edge840 -f monkey.jungle -o bin/DualTank.prg -y developer_key.der   # build a PRG
connectiq && monkeydo bin/DualTank.prg edge840                                  # run in simulator
monkeyc -e -f monkey.jungle -o bin/DualTank.iq -y developer_key.der             # package .iq (all products)
```

> Tip: build with `-l 3` (strict type check) for the most thorough compiler pass:
> `monkeyc -l 3 -d edge840 -f monkey.jungle -o bin/DualTank.prg -y developer_key.der`.
> The source was written to pass strict type checking (property reads are `instanceof`-narrowed,
> nullable `Activity.Info` fields are copied to locals before use).

Sideload: copy the built `.prg` to the device's `GARMIN/APPS/` folder over USB, or distribute the
`.iq` via the Connect IQ store. In VS Code, the **Monkey C** extension's *Build Current Project*
and *Run App* commands do the same via `monkey.jungle`.

### Testing the model in the simulator

Use the simulator's **Data Fields → activity simulation** to feed a power trace (or FIT playback),
then watch the two bars. Expected behaviour is documented as test traces at the top of
`source/DualTankView.mc` (single sprint → PCr drains bright and refills in ~30–60 s; sustained
supra-CP → GLY bleeds and only refills below LT1).

## Notes / limitations

- Tank levels are **model estimates for pacing**, not measurements of muscle chemistry — calibrate
  and validate before trusting absolute numbers (white paper §6–7).
- The session kJ totals are **gross energy drawn** from each system, so on a long ride they can
  exceed a tank's capacity (a tank can be spent and refilled many times) — that is intended.
- Both realism terms (fatigue-slowed PCr recovery, aerobic ramp) are wired up and on by default;
  set `fatK = 0` and `tauAer = 0` to recover the clean baseline model.
