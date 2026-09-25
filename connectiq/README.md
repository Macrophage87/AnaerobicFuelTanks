# Dual-Tank Anaerobic Reserve — Connect IQ data field

A Garmin Connect IQ **data field** that tracks the reserve, consumption, and depletion of two
anaerobic energy systems live from cycling power:

- **PCr (phosphocreatine / alactic)** — purple bar, "how much punch is left"
- **GLY (glycolytic / lactic)** — green bar, "how much sustained dig is left"

Each tank fills with the reserve fraction and is labelled on-screen with the reserve **%**; it is
**dull** when idle/recovering, **bright** when that system is actively being drained, and turns
**solid red and flashes** when the tank empties. The bars have rounded, tank-like ends. (The raw
reserve in joules is what goes to the FIT file — see below.)
It implements the reduced dual-tank model in
[`../docs/white-paper-dual-tank-anaerobic-model.md`](../docs/white-paper-dual-tank-anaerobic-model.md);
the full field/UI/FIT spec is in
[`../docs/connectiq-app-spec-and-prompt.md`](../docs/connectiq-app-spec-and-prompt.md).

## What it records to the FIT file

Two developer fields, and only while the **Record reserves to FIT** setting is on (it is **on by
default**) **and CP and W′ are both set** (#76). Both are read once at load, when the fields are
created, so a change to either applies at the next load: a load with CP or W′ unset records no
developer fields for that load even if they are set mid-ride, and clearing them mid-ride keeps
the fields that load already created.

- **Per second (record stream):** `PCr_J`, `GLY_J` — reserve energy remaining, **joules**, FLOAT,
  ids 0 and 1. 8 B of Connect IQ's 32-byte-per-message developer-field budget for data fields.

  **These streams lag the recorded power by one record (#100).** The reserve at record *t*
  reflects the power recorded at record *t−1*. This is platform-inherent:
  - `compute()` reads the power, steps the model and writes both fields in one call, so
    write-ordering in the app was ruled out at source on #100.
  - What the file shows is consistent with each record carrying the value latched by the
    previous `compute()`.

  On the 2026-09-20 ride (`../docs/fielddata/ride-2026-09-20-edge1050.md`), a single-threshold
  fit of the draw reconstructed from these two streams misclassifies 13/11858 seconds when
  power is shifted one record, against 488/11879 unshifted (`RIDEFACT threshold`). The
  2026-07-26 ride shows the same offset (#100).

  The pause boundaries are consistent with it, though they cannot tell it apart from the resume
  record being written before the first post-resume `compute()` (`../docs/agents/FACTS.md` §3.3).
  The first record after a resume repeats the pre-pause reserves, and the rest-recovery refill
  lands one record later (`RIDEFACT boundary_latch`, `boundary_change_at_next`: 23/23 boundaries).

  Both rides decoded so far (2026-07-26, #100; 2026-09-20) carry the offset; treat every file as
  carrying it. Align before comparing these streams
  with power: [`../docs/calibration-protocol.md`](../docs/calibration-protocol.md) §5.6.
- **Per ride (session summary):** _nothing._ SESSION contributions are 0 B.

Issue #102 cut this from seven fields to two (RECORD 16 B → 8 B, SESSION 8 B → 0 B). Whether the
32 B per-message-type budget is per app or contended across co-installed data fields is open
(`../docs/agents/FACTS.md` §5.3); the cut helps under either reading.

**Retired, and the ids are never reused:** `PCr_cons` / `GLY_cons` (live
W, ids 2/3), `PCr_depleted_kJ` / `GLY_depleted_kJ` (session totals, ids 4/5) and `Deficit_kJ`
(id 18). The per-second draws and the depleted totals are reconstructible from the two reserve
streams — `max(0, −ΔR)/Δt` for a draw in watts, `Σ max(0, −ΔR)` for the joules — **exact only
between out-of-band reserve moves**
(a pause and its rest recovery, a mid-ride restore, a live settings change), which move a reserve
with no draw and leave no marker in the file. The banked deficit is not reconstructible from the
reserves at all; it needs a replay from power plus the config.

- **Config parameters (session summary):** _not recorded, and not returning._ Recording the 12
  config parameters pushed the session developer-fields over the 32-byte limit and crashed the
  field at load on every device (issue #96); #102 chose not to bring them back in any form, which
  supersedes #99. A calibration ride's settings have to be kept out of band — see
  [`../docs/calibration-session-checklist.md`](../docs/calibration-session-checklist.md).

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
| `tauP` | PCr recovery time constant (s) | 27 |
| `tauG` | glycolytic recovery time constant (s) | 470 |
| `lt1Frac` | LT1 as a fraction of CP — **set from a measured LT1**, not left at default | 0.80 |
| `eta` | PCr recovery efficiency — fraction of recovery energy stored as usable PCr (0–1); **effectively deprecated/neutral**: at the default 1.00 it applies no rescaling and is degenerate with tauP | 1.00 |
| `fatK` | fatigue slowing of PCr recovery (0 disables) | 0.75 |
| `gFat` | glycolytic fatigue (optional) — lowers glycolytic flux as its reserve empties (repeated-sprint realism); 0 disables | 0.00 |
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

# --- or the raw commands the wrapper runs (bin/ is git-ignored, so create it first) ---
mkdir -p bin
monkeyc -d edge840 -f monkey.jungle -o bin/DualTank-edge840.prg -y developer_key.der   # build a PRG
connectiq && monkeydo bin/DualTank-edge840.prg edge840   # run in simulator
monkeyc -e -f monkey.jungle -o bin/DualTank.iq -y developer_key.der   # package .iq (all products, unsuffixed)
```

> Tip: build with `-l 3` (strict type check) for the most thorough compiler pass:
> `monkeyc -l 3 -d edge840 -f monkey.jungle -o bin/DualTank-edge840.prg -y developer_key.der`.
> **Whether it still passes `-l 3` is unmeasured.** The source was *written* with strict checking
> in mind (property reads are `instanceof`-narrowed, nullable `Activity.Info` fields are copied to
> locals before use), but nothing in this repository has ever run `-l 3`: CI compiles at `-l 1`,
> `build.sh` passes no `-l` at all, and `.github/workflows/ci.yml:24-25` states the opposite —
> "this codebase is untyped, so strict `-l 3` would drown in errors". Treat the tip as something
> to try, not a guarantee; the run that settles it is tracked in #109.

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
