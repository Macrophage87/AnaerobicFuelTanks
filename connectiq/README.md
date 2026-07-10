# Dual-Tank Anaerobic Reserve — Connect IQ data field

A Garmin Connect IQ **data field** that tracks the reserve, consumption, and depletion of two
anaerobic energy systems live from cycling power:

- **PCr (phosphocreatine / alactic)** — purple bar, "how much punch is left"
- **GLY (glycolytic / lactic)** — green bar, "how much sustained dig is left"

Each bar fills left→right with the reserve %, is **dull** when idle/recovering, **bright** when
that system is actively being drained, and turns **solid red and flashes** when the tank empties.
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
| `fP` | PCr share of W′ (0–1) | 0.35 |
| `pPmax` | max PCr power above CP (W) | 300 |
| `tauP` | PCr recovery time constant (s) | 22 |
| `tauG` | glycolytic recovery time constant (s) | 360 |
| `lt1Frac` | fraction of CP below which glycolytic refills | 0.80 |
| `eta` | PCr recovery efficiency (0–1) | 0.80 |

> `fP` is a modeling choice, not a measured value — personalize it (and the τ's) per athlete.

## Build & run

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and a device developer key.

```bash
# from this connectiq/ directory

# 1. one-time: generate a developer key if you don't have one
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt

# 2. build a runnable PRG for the simulator / a device
monkeyc -d edge840 -f monkey.jungle -o bin/DualTank.prg -y developer_key.der

# 3. run in the simulator
connectiq            # launch the simulator
monkeydo bin/DualTank.prg edge840

# 4. package a store/sideload .iq (all products)
monkeyc -e -f monkey.jungle -o bin/DualTank.iq -y developer_key.der
```

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
- Optional realism (fatigue-slowed PCr recovery, aerobic ramp) from the white paper is **not** wired
  up here; this is the clean baseline model.
