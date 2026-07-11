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

The dual-tank model splits W′ into a fast PCr tank and a slow glycolytic tank, drains them
**PCr-first** from the power trace, and refills them with **system-specific, intensity-gated**
laws — so you can see *which* reserve is spent and *how fast* each will come back.

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

There are two ways to get the ten numbers the data field needs.

### Method 1 — Work with an LLM (recommended, and best for ongoing tuning)

Share your ride/workout `.FIT` files (or their power-duration numbers) with an LLM like Claude,
along with the context block below. It can estimate the parameters, tell you which ones your data
actually constrains, and — as you feed it more workouts over time — **refine them** (raise `W′`
after a breakthrough effort, pin down recovery once you do a glycolytic-depleting session, etc.).
This is the most flexible option because the reasoning adapts to whatever data you have.

<details>
<summary><b>Context to paste to the LLM (with your FIT files)</b></summary>

> I use the AnaerobicFuelTanks Connect IQ data field — it models two anaerobic "tanks" from power,
> **PCr** (fast, small) and **glycolytic** (slow, large). Help me set/refine these 10 settings from
> my data. Flag anything my data can't constrain instead of guessing.
>
> **Parameters — key = meaning [default, typical range, unit]:**
> - `CP` = critical power [255, from test, W]
> - `Wprime` = anaerobic work capacity above CP [20000, 10k–30k, J]
> - `pPmax` = max PCr power above CP [300, W]
> - `fP` = PCr share of Wprime [0.35, 0.30–0.45]
> - `tauP` = PCr recovery time constant [22, 15–35, s]
> - `tauG` = glycolytic recovery time constant [360, 240–600, s]
> - `lt1Frac` = fraction of CP below which glycolytic refills [0.80, 0.70–0.85]
> - `eta` = PCr recovery efficiency [0.80, 0.60–1.0]
> - `fatK` = fatigue slowing of PCr recovery [0.75, 0–1.5]
> - `tauAer` = aerobic onset time constant [25, 15–40, s]
>
> **How to estimate each:**
> - `CP`, `Wprime`: from maximal efforts spanning ~2–12 min (linear model `W = CP·t + Wprime`), or
>   from intervals.icu's CP/W′. A single maximal effort can set *only* these two.
> - `pPmax`: best ~5 s sprint power minus CP (or a modelled Pmax − CP).
> - `fP`, `tauP`, `eta`: need **repeated** near-maximal efforts with recovery between; anchor the
>   moments I was maximal/cracked (final sprint, the attack I couldn't follow, getting dropped).
> - `tauG`, `fatK`: **only** identifiable from a workout that actually **depleted glycolytic** —
>   repeated hard 1–3 min efforts on short rest (or short sprints on very short rest). If no session
>   emptied glycolytic, keep the defaults.
> - `lt1Frac`: from a lactate/threshold test or intervals.icu LT1 (≈ LT1 ÷ CP).
> - `tauAer`: aerobic onset; leave near default unless you have onset kinetics.
>
> **Model rules to respect when reasoning about my rides:**
> - Below CP the aerobic system covers demand → **no PCr draw below CP**. Above CP: PCr supplies
>   first (capped at `pPmax`), glycolytic covers any overflow.
> - Glycolytic drains while PCr is still full **only** when power exceeds ~`CP + pPmax`; otherwise
>   PCr carries the load until it empties, then glycolytic takes over.
> - A single all-out effort obeys `t_lim = Wprime/(P − CP)` → gives only `CP` and `Wprime`.
>
> **Iterating over time:** each time I share new workouts, tell me which parameters the new data
> constrains, revise those, leave the rest. If I completed an effort the current params say is
> impossible (reserve would go negative), raise `Wprime` or speed recovery; if I was maximal but the
> model shows lots left, lower them.
>
> **Output:** the 10 settings ready to paste into the field, marking which are well-constrained vs
> still default/uncertain.

</details>

### Method 2 — The Shiny calibration app

`tools/calibrate/` is an R Shiny app that reads your `.FIT` files and estimates the same parameters
(`CP`, `W′`, `pPmax`, and — where the data allows — `fP`, `tauP`, `tauG`, `eta`), flagging anything
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
