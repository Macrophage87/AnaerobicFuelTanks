# AnaerobicFuelTanks

Modeling the two anaerobic energy systems in cycling — **phosphocreatine (PCr / alactic)** and
**glycolytic (lactic)** — as two separate "fuel tanks" that deplete and refill from your power
data, and surfacing them live on a Garmin head unit.

This repo goes research → model → app:

1. **Research** — a literature review of the mathematical models of anaerobic metabolism.
2. **Model** — a white paper proposing a reduced **dual-tank** model driven entirely by power.
3. **App** — a buildable Garmin **Connect IQ** data field that runs the model at 1 Hz and records it.

---

## The idea

The standard cycling model (Critical Power / W′-balance) lumps *all* anaerobic capacity into one
reserve with a single recovery constant. Physiologically there are two systems with very different
dynamics:

| Tank | System | Power | Capacity | Recovery |
|---|---|---|---|---|
| **PCr** (purple) | phosphocreatine / alactic | highest | small | fast (~seconds), pH-sensitive |
| **GLY** (green) | glycolytic / lactic | lower | large | slow (~minutes), only at low intensity |

The dual-tank model splits W′ into a fast PCr tank and a slow glycolytic tank, drains them
**PCr-first** from the power trace, and refills them with **system-specific, intensity-gated**
laws — so you can see *which* reserve is spent and *how fast* each will come back.

---

## Repository layout

```
AnaerobicFuelTanks/
├─ docs/                                   research & design
│  ├─ literature-review-anaerobic-models.md    survey of the modeling literature (+ .pdf)
│  ├─ white-paper-dual-tank-anaerobic-model.md the proposed dual-tank model (+ .pdf)
│  └─ connectiq-app-spec-and-prompt.md         app spec + ready-to-use build prompt (+ .pdf)
├─ connectiq/                              the Garmin Connect IQ app
│  ├─ source/            Monkey C: model + rendering + FIT recording
│  ├─ resources/         strings, settings, launcher icon
│  ├─ store/             hero/cover/device icons + in-app screenshots + generators
│  ├─ manifest.xml, monkey.jungle, build.sh
│  └─ README.md          app-specific docs (build, settings, layouts)
└─ tools/
   └─ calibrate/         R Shiny app: FIT files -> estimate the field's parameters
```

## Calibration tool

`tools/calibrate/` is an R Shiny app that reads your `.FIT` files and estimates the parameters the
data field needs (`CP`, `W′`, `pPmax`, and — where the data allows — `fP`, `tauP`, `tauG`, `eta`),
flagging anything weakly constrained. It exports a dated YAML reading and a PDF report, and tracks
your values over time. See [`tools/calibrate/README.md`](tools/calibrate/README.md).

---

## The Connect IQ app

A custom **data field** (`connectiq/`) that reads `Activity.Info.currentPower` once per second and:

- runs the dual-tank model (aerobic ramp, fatigue-slowed PCr recovery, pause/resume rest recovery);
- draws two tanks — **dull** when idle, **bright** when draining, **red flash** when spent;
- **records to the FIT file**: per-second `PCr_pct` / `GLY_pct` reserve streams (+ live consumption),
  and per-ride `PCr_depleted_kJ` / `GLY_depleted_kJ` session totals, which sync to Garmin Connect →
  intervals.icu / Strava;
- **adapts its layout** to the data-field cell:
  - very wide → two horizontal bars side by side,
  - wide/short → two horizontal bars stacked,
  - large single field → vertical tanks + a depletion & fatigue summary,
  - square/tall (1×2 cell) → two vertical bars side by side;
- reads on **light and dark** themes (foreground picked by background luminance).

### Build

```bash
cd connectiq
./build.sh            # requires the Connect IQ SDK + a developer key; default device edge840
```

See [`connectiq/README.md`](connectiq/README.md) for the developer-key steps, settings
(`CP`, `Wprime`, `fP`, τ's, `fatK`, `tauAer`), simulator testing, and per-layout screenshots.

---

## Documents

| Document | What it is |
|---|---|
| [Literature review](docs/literature-review-anaerobic-models.md) | Survey of anaerobic-metabolism models (CP/W′bal, Margaria–Morton hydraulic, bioenergetic ODEs) with an annotated, DOI/PMID-linked bibliography |
| [White paper](docs/white-paper-dual-tank-anaerobic-model.md) | The reduced dual-tank model: state, depletion & restoration laws, on-device implementation, validation strategy, limitations |
| [Connect IQ spec](docs/connectiq-app-spec-and-prompt.md) | Field/UI/FIT specification and a copy-paste build prompt |

PDF renderings of each sit alongside the Markdown in `docs/`.

---

## Status & caveats

- **Estimates, not measurements.** Tank levels are a pacing model, not muscle chemistry — calibrate
  (`fP`, per-athlete τ's) and validate before trusting absolute numbers (white paper §6–7).
- **Not compiled in CI.** The Monkey C is written to pass strict type checking and is statically
  validated, but the real compile happens locally via the Connect IQ SDK (`connectiq/build.sh`).
- **Research sourcing.** Literature was retrieved via PubMed / PubMed Central; some typeset equations
  were image-embedded, so a few closed forms are the standard published forms cross-checked against
  the surrounding text — verify exact coefficients against the publisher PDFs before hard-coding.
