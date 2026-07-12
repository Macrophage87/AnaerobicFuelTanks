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

> The glycolytic side is the more complex of the two — it isn't really a fuel gauge but a stand-in
> for how much fatigue-metabolite buildup you can still tolerate ([note below](#a-note-on-the-tanks)).

The dual-tank model splits W′ into a fast PCr tank and a slow glycolytic tank, drains them **in
parallel** from the power trace — PCr is the immediate buffer and glycolysis ramps in over the first
few seconds (its real activation delay), so both are spent together on a hard effort — and refills
them with **system-specific, intensity-gated** laws, so you can see *which* reserve is spent and
*how fast* each will come back.

### A note on the "tanks"

"Tank" is a **simplified mental model for an at-a-glance read, not a literal reservoir** — and the
two sides aren't even the same kind of thing:

- **PCr** really is a small store that depletes (intramuscular phosphocreatine) — "empty" is close
  to literal.
- **Glycolytic** is better read as **how much fatigue-metabolite buildup you can still tolerate**
  (inorganic phosphate, H⁺, ADP, K⁺) — *not* running low on carbohydrate. You have plenty of
  glycogen on this timescale, and lactate is a fuel/marker, not the cause of fatigue.

That's why the glycolytic side recovers **slowly and only at low intensity** (it reflects *clearing*
byproducts, which needs aerobic time) while PCr snaps back fast. One-liner: **PCr is a fuel that
depletes; glycolytic is a byproduct bucket that fills.** Muscle fatigue is multifactorial; the model
deliberately lumps it into one number for usability. (More in the
[white paper](docs/white-paper-dual-tank-anaerobic-model.md).)

---

## Repository layout

```
AnaerobicFuelTanks/
├─ docs/                                   research & design
│  ├─ literature-review-anaerobic-models.md    survey of the modeling literature (+ .pdf)
│  ├─ white-paper-dual-tank-anaerobic-model.md the proposed dual-tank model (+ .pdf)
│  ├─ dual-tank-anaerobic-model-journal.tex    standalone journal-format manuscript (LaTeX)
│  ├─ llm-calibration-context.md               paste-to-an-LLM brief for setting parameters
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

## Setting your parameters

There are two ways to set the field's twelve parameters (ten that materially affect it — `eta` is a
deprecated identity and `gFat` is an optional off-by-default term).

### Method 1 — Work with an LLM (recommended, and best for ongoing tuning)

Share your ride/workout `.FIT` files (or their power-duration numbers) with an LLM like Claude,
along with the context block below. It can estimate the parameters, tell you which ones your data
actually constrains, and — as you feed it more workouts over time — **refine them** (raise `W′`
after a breakthrough effort, pin down recovery once you do a glycolytic-depleting session, etc.).
This is the most flexible option because the reasoning adapts to whatever data you have.

The full, self-contained brief lives in
[`docs/llm-calibration-context.md`](docs/llm-calibration-context.md) — **paste that whole file** to the
LLM with your data. It mirrors the current model (parameters, estimation guidance, and the depletion /
recovery rules), so keep sharing that file rather than the summary below.

<details>
<summary><b>Context to paste to the LLM (with your FIT files)</b></summary>

> I use the AnaerobicFuelTanks Connect IQ data field — it models two anaerobic reserves from power, a
> **fast reserve** ("PCr", small) and a **slow reserve** ("glycolytic", large). Both are compartments of
> **W′**, named for their dominant system — a full "PCr bar" means the fast *W′* reserve is back, not that
> muscle phosphocreatine has resynthesised (W′ recovers ~4× faster than the metabolites). Help me set/refine
> the twelve settings from my data; flag anything my data can't constrain instead of guessing.
>
> **Parameters — key = meaning [default, typical range, unit]:**
> - `CP` = critical power [250, from test, W]
> - `Wprime` = anaerobic work capacity above CP (W′) [20000, 10k–30k, J]
> - `fP` = fast-reserve share of W′ [0.25, 0.20–0.25] — **assumed**, weakly identifiable
> - `pPmax` = fast-reserve peak power above CP, full tank [300, ≈ best 1 s power − CP, W]
> - `tauP` = fast-reserve recovery constant [27, 20–40, s] — a **W′-recovery** constant, not muscle PCr
> - `tauG` = slow-reserve recovery constant [470, 300–600, s]
> - `lt1Frac` = LT1 as a fraction of CP; anchors the recovery-rate band [0.80, 0.65–0.85]
> - `eta` = **deprecated** identity — leave at 1.0
> - `fatK` = slows fast-reserve recovery as the slow reserve empties [0.75, 0–1.5]
> - `gFat` = **optional** glycolytic flux-fatigue exponent, **off by default** [0.0, 0–1.5]
> - `tauAer` = aerobic onset time constant [25, 15–40, s]
> - `tauOn` = glycolytic activation time constant [6, ~6, s] — literature-set, not power-identifiable
>
> **How to estimate each:**
> - `CP`, `Wprime`: from maximal efforts spanning ~2–12 min (`W = CP·t + Wprime`), or intervals.icu CP/W′.
>   A single maximal effort obeys `t_lim = Wprime/(P − CP)` and sets *only* these two.
> - `fP`: **assumed ~0.25; not a routine fit target** — power can't identify the split. Keep the default
>   unless I have repeated all-out efforts with early recovery sampling.
> - `pPmax`: best ~1–5 s sprint power minus CP (upper bound).
> - `tauP`: a W′-recovery constant (~27 s); do **not** recalibrate it toward muscle-PCr biopsy values.
> - `tauG`, `fatK`: **only** identifiable from a workout that actually **depleted the slow reserve** —
>   repeated hard 1–3 min efforts on short rest. If none did, keep the defaults.
> - `lt1Frac`: from a lactate/threshold test or intervals.icu LT1 (≈ LT1 ÷ CP).
> - `eta`: deprecated — leave 1.0. `gFat`: leave 0 for normal use. `tauAer`, `tauOn`: leave near default.
>
> **Model rules to respect when reasoning about my rides:**
> - **Below CP:** no anaerobic draw. The fast reserve refills with `tauP` but **gated by oxidative
>   headroom** `(CP − P)/CP` — ~27 s stopped, but 100–500 s while pedalling. The slow reserve and the
>   deficit recover whenever `P < CP` at an **intensity-dependent rate** (fast at low power, slowing through
>   the tempo band; `lt1Frac` anchors the band) — **not** a hard on/off at LT1.
> - **Above CP:** both systems draw **in parallel**. Glycolysis **ramps in** over ~`tauOn` s, so at onset
>   the fast reserve covers almost everything. The **share** is **capacity-weighted**, so on a steady hard
>   effort both reserves empty together at exhaustion. A separate **rate ceiling** (fast-reserve ceiling
>   tapers with fullness) governs **maximal** efforts. Unmet demand banks as a deficit.
> - If I completed an effort the params call impossible (a reserve goes deeply negative), raise `Wprime` or
>   speed recovery; if I was maximal but the model shows lots left, lower them.
>
> **Iterating over time:** each time I share new workouts, tell me which parameters the new data
> constrains, revise those, leave the rest at default.
>
> **Output:** the twelve settings ready to paste into the field, marking which are well-constrained vs
> still default/uncertain (note `eta` deprecated at 1.0, `gFat` optional at 0).

</details>

### Method 2 — The Shiny calibration app

`tools/calibrate/` is an R Shiny app that reads your `.FIT` files and estimates the same parameters
(`CP`, `W′`, `pPmax`, and — where the data allows — `fP`, `tauP`, `tauG`), flagging anything
weakly constrained. It exports the settings as JSON/YAML and a PDF report and tracks your values
over time. Good for **initial** parameters, or if you'd rather not work with an LLM. See
[`tools/calibrate/README.md`](tools/calibrate/README.md).

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
(`CP`, `Wprime`, `fP`, `pPmax`, the τ's incl. `tauOn`, `lt1Frac`, `fatK`, optional `gFat`, `tauAer`;
`eta` deprecated), simulator testing, and per-layout screenshots.

---

## Documents

| Document | What it is |
|---|---|
| [Literature review](docs/literature-review-anaerobic-models.md) | Survey of anaerobic-metabolism models (CP/W′bal, Margaria–Morton hydraulic, bioenergetic ODEs) with an annotated, DOI/PMID-linked bibliography |
| [White paper](docs/white-paper-dual-tank-anaerobic-model.md) | The reduced dual-tank model: state, depletion & restoration laws, on-device implementation, validation strategy, limitations |
| [Journal manuscript](docs/dual-tank-anaerobic-model-journal.tex) | Standalone, journal-formatted LaTeX rebuild of the white paper (Vancouver citations, cross-linked); compile with `pdflatex` (×3) |
| [LLM calibration context](docs/llm-calibration-context.md) | Paste-to-an-LLM brief for setting/refining the field's parameters from your FIT files |
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
