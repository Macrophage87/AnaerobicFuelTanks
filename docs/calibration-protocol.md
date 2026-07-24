# DualTank calibration protocol — identifying the model parameters from real-world data

A field-first (with one optional lab visit) test protocol for calibrating the full DualTank
parameter set on a single athlete, with quantified uncertainty and an explicit honesty ledger of
what real-world data can and cannot reach.

**Status:** design document. It maps to the model and fitting tool as they exist in
`tools/calibrate/R/model.R` + `app.R`; where it asks for something the tool does not yet do
(recovery-ladder session type, per-parameter confidence intervals, fitting the `#91` excess term)
that is called out as an **extension**. Companion to
[`white-paper-dual-tank-anaerobic-model.md`](white-paper-dual-tank-anaerobic-model.md) (§4 math/conservation,
§6 validation, §7 assumptions), [`literature-review-anaerobic-models.md`](literature-review-anaerobic-models.md),
and the practical [`calibration-session-checklist.md`](calibration-session-checklist.md).

Relevant issues: **#86** (structural over-drain), **#87/#90** (soft W′ / PCr-light `fP` surfacing),
**#88/#91** (the above-CP aerobic-excess fork + its flip).

---

## 0. Governing principle — fit upstream-frozen, in identifiability order

The parameters are **not** co-estimable in one basket. They form a dependency DAG; a soft *upstream*
parameter silently absorbs the error of a *downstream* one if fit out of order — which is exactly the
failure #87 documented (a soft single-session W′ made the glycolytic tank look empty and pushed the
`fP` split toward a bound). The whole protocol is therefore **staged and upstream-frozen**:

```
data hygiene  →  {CP, W′}  →  pPmax  →  { τG | τP | fP-on-ridge }  →  { eAerMax, τ_E }
                 └ joint ┘              └──── joint fit (η fixed) ────┘   └ lab-anchored ┘
```

Two hard rules the DAG encodes:

1. **`{CP, W′}` and `{fP, τP, τG}` are each *joint* fits, not sequences.** `fit_cp()` returns both
   coefficients of one work–time regression; `fit_recovery()` optimises `fP, τP, τG` simultaneously
   with `η` frozen. Pinning `fP` first, then `τG`, then `τP` walks straight into the `(fP, τG)` ridge
   and returns noise.
2. **Nothing about the tanks is meaningful until CP (the branch pivot) and W′ (the capacity scale)
   exist,** and `lt1Frac` must be in hand before `τG`'s recovery gate is anchored.

---

## 1. Parameter identifiability map

The backbone: for every parameter, what it controls, how identifiable it is, and the minimal
manipulation that breaks its confound. Pillars: **P1** power–duration anchor · **P2** recovery
kinetics · **P3** above-CP excess · **Lab** metabolic/biopsy leaf.

| Param | Term it moves (`simulate_tanks`) | Identifiability class | Manipulation that breaks the confound | Home |
|---|---|---|---|---|
| **CP** | `supply`, `delta=p−supply`, every recovery gate `(cp−p)/cp` | **Directly identifiable** (slope of `fit_cp`'s `lm(W~t)`) | ≥3 maximal efforts over a wide duration span | P1 |
| **W′** | `cP=fP·W′`, `cG=(1−fP)·W′` → reserve amplitude | **Directly identifiable but co-fit with CP; soft from one session (#87)** | Spread CP efforts across ≥2–3 days/files | P1 |
| **pPmax** | `rateP=pPmax·rP/cP`; emergent `τ_dep=cP/pPmax` | **Directly identifiable** from one maximal sprint (an *upper bound*) | One all-out ≤5 s sprint, fresh | P1 |
| **fP** | the split `cP/cG`; sprint residual; `rG/cG` in `τ_P,eff` | **Weakly identified / on the `(fP,τG)` ridge; degenerate w/ `pPmax` sprint residual** | Short-vs-long recovery contrast (see P2) — else stays assumed ~0.20–0.25 | P2 (weak) |
| **τP** | `τ_P,eff=τP·(1+fatK·(1−rG/cG))`; PCr resynthesis | **Identifiable only from a contrast** (repeated max efforts, varied *short* recovery); degenerate w/ `η`, `fatK` | Valleys of ≥3 short lengths at low, fixed valley power | P2 |
| **τG** | `bG=1−e^(−1/τG)`; W′bal reconstitution | **Identifiable from a recovery-duration contrast**; degenerate w/ `fP`; confounded by recovery *power* | Deplete to a fixed anchor, recover at known low power for varied *durations* | P2 |
| **τAer** | `kUp=1−e^(−1/τAer)`; aerobic onset ramp | **Weak from field power** (first-~25 s transient only) | VO₂ on-kinetics (lab); else keep default 25 | Lab |
| **τOn** | `kOn=1−e^(−1/τOn)`; glycolytic activation | **Not identifiable from field power** (redistributes a split) | Biopsy / phosphorylase kinetics (Parolin 1999); assumed 6 | Lab |
| **fatK** | `τ_P,eff` pH-slowing of PCr recovery | **Contrast-only, degenerate with τP** | Long repeated-sprint set, matched valley duration | P2 (weak) |
| **lt1Frac** | `gate20=(lt1Frac·cp−20)/(lt1Frac·cp)` — glyco recovery-gate anchor | **Measure it** (lactate threshold); do NOT derive from CP | Blood-lactate threshold test | Lab |
| **η** | `rP += gateP·η·(cP−rP)·…` — pure rescale of `τP/η` | **Not identifiable — perfectly degenerate with τP** | none; **held fixed at 1.0** by construction | — |
| **gFat** | `rateG·=(rG/cG)^gFat` (opt-in) | **Not identifiable from field power** (a split quantity) | Muscle biopsy across a repeated-sprint set (§6.10) | Lab |
| **eAerMax** *(#91)* | `supply=(P>CP)?min(P,aer+E):P` — VO₂ slow component | **Contrast-only, W′-confounded; realistically a lab VO₂ measurement** | Sustained/short-recovery supra-CP work + VO₂; default 0 until measured | P3 / Lab |
| **τ_E,on/off** *(#91)* | rise/decay of `E` (hardcoded 90/120) | **Not separately identifiable from field power** | Lab VO₂ slow-component kinetics | Lab |

**HR** is not a model state — use it corroboratively (a freshness/validity check; drift on long
supra-CP efforts flags that `E` is non-zero), never as a fitting input.

### Sensitivity ranking (where to spend the athlete's legs)
`CP ≫ W′ > pPmax > τG > lt1Frac > τP > fP > τAer > fatK > τOn > eAerMax/τ_E (0 by default) > gFat > η (0)`.
CP is the pivot of every sample *and* rescales every recovery gate — spend the most effort there.
`fP` is split-personality: **low** sensitivity on the W′bal/pacing display (the split is invisible in
depletion) but **moderate** on the per-system training-load kJ outputs — which is why it is
"load-bearing yet unidentifiable."

### Identifiability verdict
- **Cleanly gettable from field power alone:** **CP, W′, pPmax**.
- **Field-gettable via a designed contrast, weakly:** **τG**, then **τP** (softer).
- **Effectively assumed / physiology-selected:** **fP** (rides the `(fP,τG)` ridge), **fatK**.
- **Needs lab/biopsy or stays assumed:** **lt1Frac** (lactate), **τAer** (VO₂ on-kinetics),
  **τOn / gFat** (biopsy), **eAerMax / τ_E** (VO₂ slow component).
- **Never identifiable:** **η** (frozen at 1.0). Gold-standard corroboration of the PCr compartment
  is impossible in-modality (³¹P-MRS unavailable during cycling, WP §6.5) — the two-compartment
  hypothesis is testable only by proxy (§6.10 biopsy direction) or by the recovery-law out-of-sample
  win (§6.6), never confirmed directly.

---

## 2. Phase 1 — the power–duration anchor (CP, W′, pPmax)

Everything here feeds the tool's actual fit path: `mmp_curve()` builds one composite mean-maximal-power
curve (max `best_mean_power` **across every uploaded file** at each `DURATIONS` grid point), and
`fit_cp(dur, pw, tmin, tmax)` runs the linear work–time regression `W = W′ + CP·t` over the CP window
(default **2–12 min / 120–720 s**): CP = slope, W′ = intercept.

### Effort menu (each a genuine all-out effort to failure)

| Effort | Target | Grid point | Role in `fit_cp` |
|---|---|---|---|
| Sprint (6–8 s max) | 1 s | 1 | `pPmax = max(50, P₁ₛ − CP)` (outside the CP window) |
| Short TTE | ~2 min | 120 | anchors the **W′ intercept** (short lever to t=0) |
| Mid TTE | ~4–5 min | 240/300 | interior point, stabilises R² |
| Long-mid TTE | ~8 min | 420/600 | fills the log-gap, protects `rng` |
| Long TTE | ~12 min | 720 | anchors the **CP asymptote** (large-t slope) |

**Why both ends are mandatory.** CP (slope) is pinned by the long end (at 12 min, work is dominated by
`CP·t`); W′ (intercept) is pinned by the short end (at 2 min the work-above-CP fraction is large and the
extrapolation to t=0 is short and stable). All-long batteries leave the intercept a wild extrapolation —
that *is* the W′ softness, geometrically. Below ~2 min the work–time line curves (why the window floor
is 120 s and the sprint is used only for pPmax); above ~15–20 min glycogen/thermal drift bends it the
other way. `rng ≥ 5` encodes "both ends": 720/120 = 6 clears it.

**Form:** use **separate maximal TTEs** — the only form `fit_cp` consumes correctly. A single 3-min
all-out test gives n≈2, `rng`≈1.5 ("narrow durations"), no long anchor, and is single-file by
construction (#87); keep it only as a *cross-check* (its end-power should land near the multi-TTE CP).
A ramp test yields no work–time pair — warm-up/MAP reference only.

### Multi-session design — defeating single-session W′ softness (#87)
`mmp_curve` takes the max **per grid point across all files**, so if the window winners come from
**different files**, W′ no longer rests on one ride (the `mmp_src`/`single-session` flag from #90 fires
when they all trace to one file). **Prescription: spread 4 CP-window efforts across 3–4 sessions over
~2 weeks, one maximal TTE per session**, ≥48 h apart, identical warm-up each time. Do sprints on fresh
legs. One maximal TTE per session (a second same-day TTE is suppressed → shows as a below-line point →
"low R2").

### pPmax — the clean sprint
`pPmax = P₁ₛ − CP`, guarded by the `P₁ₛ ≥ 1.6·CP` check. Sprints **first** in the session (before any
W′-depleting effort); 2–3 maximal 6–8 s efforts, ≥5 min full recovery, take the best 1 s; big gear,
rolling start, ~110–130 rpm, standing, consistent gear/posture across retests; flat surface or a
direct-force trainer (a wheel-on flywheel smooths the 1 s peak). A trained rider's P₁ₛ ≈ 3–5× CP.

### Field vs lab, and failure modes
Power meter alone gets the whole phase. Test–retest envelope: **CP CV ≈ 2–4 %** (reliable), **W′ CV
≈ 10 %+** (the softness the multi-session design attacks), pPmax to a few %. Lab (blood lactate → MLSS)
gives an independent CP check once. Read the tool's own flags: `nonphysical`/`impossible`/`implausible`
(bad file/window — blocks device export), `low R2` (a non-maximal effort on the line), `narrow
durations`/`few efforts` (add an end/effort), `pPmax uncertain` (no real sprint). **Control terrain and
heat** — grade-contaminated efforts (cf. the 2026-07-20 ride) and hot-day efforts depress/​distort CP;
prefer a flat loop or indoor trainer, temperate, for all anchoring efforts. Re-test when a new best
effort lands above the current CP line, after a training block, or when CP drifts > ~5 % between
calibrations.

### Acceptance criteria
`n ≥ 3` (target 4), `rng ≥ 5`, `R² ≥ 0.95`; no nonphysical/impossible/implausible; **CP-window winners
from ≥2 (ideally ≥3) distinct files** (single-session flag clear); W′ in a plausible ~10–25 kJ band;
pPmax from a fresh sprint with `P₁ₛ ≥ 1.6·CP`. **2-session MVP** (clears the flag but not its spirit):
S1 fresh = sprint → 2-min → (≥25 min easy) → 5-min; S2 (+48 h) = 12-min. Three sessions is the true
robust floor.

---

## 3. Phase 2 — recovery kinetics (τP, τG, fP; τAer, τOn)

Power alone cannot see the depletion split (WP §4.2); everything here lives in the **recovery** branch,
where the two systems obey different laws: PCr refills gated by oxidative headroom `gateP=(CP−P)/CP`
(fast, t½ ≈ 19 s), glycolytic + deficit refill at the Skiba rate `τ_W′ = 546·e^(−0.01(CP−P))+316`
(slow, t½ ≈ 326 s). The two constants are ~18× apart but overlap in one session — so the game is
**choosing recovery valleys that make one curve move while the other is pinned flat.**

### The valley-duration ladder (valley power ≈ 0.25–0.3·CP, well below LT1)
Verified against the exact gates in `model.R` (CP 255, valley 60 W → `gateP` 0.765, τ_P,eff ≈ 35 s,
τ_G,eff ≈ 558 s):

| Valley (s) | PCr refilled | Glyco refilled | What is moving |
|---|---|---|---|
| 15 | ~35 % | ~3 % | PCr rising limb only |
| 30 | ~58 % | ~5 % | **PCr only** (glyco pinned) |
| 60 | ~82 % | ~10 % | **PCr only** |
| 90–120 | ~92–97 % | ~14–19 % | PCr saturating |
| 300 | ~99 % | ~42 % | **Glyco only** (PCr flat) |
| 600 | ~99 % | ~66 % | Glyco toward the Ferguson 6-min point |

**10→60 s isolates τP; 120→300 s isolates τG; the short-vs-long contrast isolates fP.** The ladder must
be swept at **fixed valley power** — otherwise the gate confounds duration with intensity.

### Sessions

| Session | Work bout | Valley ladder | Reps | Pins | Extra |
|---|---|---|---|---|---|
| **A — PCr ladder** | 10–15 s max, re-test | {30,45,60,90 s} @ ~60 W | 8–12 | **τP** | NIRS |
| **B — gate sweep** | 15 s max | 60 s @ {40,100,150,190 W} | 4–8 | **τP** gate shape | NIRS |
| **C — short / glyco-pinned** | 30 s @ ~130 % CP | 30 s @ ~60 W | 12–15 → failure | **fP** (short limb) | [La] |
| **D — long / refill** | 3–4 min @ ~115–120 % CP | {120,240,360 s} @ 60 W | 5 | **τG** + fP (long limb) | [La] |
| **E — onset/offset** *(lab)* | steps to ~320 W | rest vs 0.7·CP baseline; ±30 s | — | **τAer, τOn** | VO₂ + NIRS |

**fP — the #87 trap and the escape.** At a *single* recovery power the reconstitution curve constrains
a **ridge** in `(fP, τG)`, not either alone — one work:recovery ratio is one point on that ridge and
`fit_recovery` slides along it. The escape is the **C↔D contrast**: on short valleys only PCr (size
`fP·W′`) regenerates, so sustainable work is governed by the *fast* capacity; on long valleys both
refill, so performance tracks *full* W′. The contrast separates the fast-pool size from the total — it
pins fP off the ridge. **Session B is why valley *power* is a control variable, not just duration:**
because `gateP=(CP−P)/CP`, a hot valley refills PCr less, so a hot-valley session masquerades as a large
τP; B excites the gate directly and lets the fit separate "recovered slowly" (true τP) from "barely got
a chance" (gate).

**Confounds.** Lock CP/W′/pPmax *first* (else recovery params absorb power-duration error). Command
valley power on a trainer or an enforced valley-watt target — never "soft-pedal by feel" (the
2026-07-20 valleys sat at 134 W flat-equivalent → `gateP` 0.475, so a 60 s valley refilled PCr ~65 %,
not ~82 %). Counterbalance rung order or split rungs across days (the `fatK` term slows late-bout PCr
recovery), start fresh, 24–48 h between the glycolytic sessions C/D.

**External anchors that rescue the weak cluster.** NIRS muscle re-oxygenation gives τP almost directly
(validated against ³¹P-MRS PCr resynthesis: τ ≈ 31.5 s, r ≈ 0.88–0.95, Ryan 2013); blood-lactate
clearance is a minutes-scale proxy for τG. With NIRS pinning τP and [La] pinning τG, the power fit only
has to find fP — the best-case escape from #87.

### Stays weakly identified (flag it)
`fP` (rides the ridge; field-only fP keeps a wide CI), `τOn`/`τAer` (first-seconds kinetics, invisible
at 1 Hz — literature-held unless Session E VO₂/NIRS is run), `τ_off` glyco deactivation (assumed = τOn;
load-bearing for 30 s valleys but unobservable), `gateP` functional form (B constrains the rate at
sampled powers, not the shape between them — ±21–31 pts at LT1, WP §7), `η` (degenerate, fixed),
`fatK` (order-effects only, confounded with τP).

---

## 4. Phase 3 — the above-CP aerobic excess (eAerMax, τ_E,on/off) — #91/#88

In the `#91` scaffold, `supply = min(P, aer + E)`, where `E` rises toward `eAerMax` (τ_E,on ≈ 90 s)
while `P > CP` and decays (τ_E,off ≈ 120 s) while `P ≤ CP`. `E` is the model's **VO₂ slow component**.
Today `eAerMax = 0` (byte-identical to hard-CP) and the τ's are hardcoded literature guesses — nothing
is fitted to a rider. This phase turns the term into measured quantities and makes §6.10 (aerobic
metabolism *rising* across repeated sprints) an out-of-sample target rather than a consistency check.

### The falsifiable field signature
Hard-CP (`eAerMax = 0`) makes a hard prediction: every second above CP drains W′ at exactly `(P − CP)`,
so on a designed 30/15 session the tanks hit zero at a computable **hard-CP empty point**. `E > 0`
lowers the drain to `(P − CP − E)` once E has ramped in, so the rider keeps producing power **past**
that point.

> **Field test:** design a 30/15-style session whose supra-CP target + rep count put the *hard-CP* model
> at `reserve = 0` at a known rep N. If the athlete completes rep N and continues at target, hard-CP is
> falsified and the surplus is direct evidence of `E`. This is precisely the 2026-07-20 ride — re-run it
> under hard-CP to locate its predicted empty point and measure the work produced beyond it.

The integrated `E_work ≈ (produced supra-CP work) − (hard-CP W′ budget)` is computable from **power
alone**; what power alone cannot do is split it into `eAerMax × time`.

### The micro-interval battery (VO₂ cart where available)
- **A — on-kinetics ramp (τ_E,on, and detection):** 30 s @ ~110–115 % CP / 15 s @ ~50 % CP, to
  exhaustion, single long set. τ_E,on shows up as the *curvature* of the reserve trajectory — early reps
  drain near `(P−CP)`, later reps at `(P−CP−eAerMax)` once E saturates. Repeat at a 2nd intensity to
  check intensity-robustness.
- **B — off-kinetics / persistence (τ_E,off):** 3 sets of ~4 min of 30/15 work separated by sub-CP
  valleys of **varied** length {45, 90, 240 s} (randomised). A fast set-2 start after a short valley but
  slow after a long one ⇒ E decayed; equal starts ⇒ persistence. This turns the WP-flagged assumption
  `τ_off = τ_on` into a measurement.
- **C — steady-state ceiling (eAerMax):** constant hold just above CP (~102–106 % CP) to exhaustion,
  >3–4 min so E fully develops; the sustainable excess above CP plateaus at `eAerMax`. Run 2–3 holds at
  slightly different powers to find the saturation.

Add a short-effort MMP refresh (2–3 min and 8–12 min maximal) in the same block to pin the
slow-component-poor W′ for the contrast. ≈5–6 sessions over ~2 weeks.

### eAerMax prior (physiological)
The VO₂ slow-component amplitude is ~0.3–0.5 L·min⁻¹ near the severe boundary (Pessoa Filho 2012;
Burnley 2011), rising toward VO₂max in the fully-developed severe domain. At ~22–24 % gross efficiency
(~80 W mechanical per L·min⁻¹) that is **~20–60 W ≈ 5–15 % of CP** — a defensible prior band. Any field
estimate far outside it signals W′-underestimate or recovery mis-fit leaking into the number.

### Field-vs-lab ladder and the honesty statement
| Measure | What it gives for E | Rung |
|---|---|---|
| Breath-by-breath VO₂ (cart) | slow component *directly*: eAerMax (amplitude×eff), τ_E,on (rise), τ_E,off (recovery) | **Gold** |
| Blood lactate | corroborates severe-domain physiology; does not quantify E | Support |
| NIRS | secondary deoxygenation drift flags E onset; hard to convert to watts | Support |
| Power + HR (field) | *detects* E (falsifies hard-CP), bounds aggregate `E_work`, shows the ramp shape | Field |

From power alone the three parameters are **not separately identifiable**: eAerMax↔τ_E,on trade off
(same integrated `E_work`), E↔W′-magnitude trade off (a bigger W′ explains "went past empty" too — the
discriminator is that E's benefit grows with cumulative time-above-CP and is absent on a short maximal
effort), and τ_E,off is barely identifiable from the inter-set contrast (confounded with τP/τG refill).
**Field power+HR can DETECT E and bound its aggregate — enough to justify moving `eAerMax` off a hard 0
into the 20–60 W band — but partitioning eAerMax / τ_E,on / τ_E,off needs the metabolic cart**, where
the slow component is a direct observable rather than a power-bookkeeping residual.

### §6.10 tie-in without circularity
The review flagged that tuning τ_E/eAerMax to the literature and then citing §6.10 as confirmation is
circular. Defeat it with a **hold-out / different-protocol-class** design: (1) calibrate eAerMax/τ_E on
the athlete's own Session A/B/C **VO₂** data, without reference to the biopsy magnitudes; (2) validate
out-of-sample by running the *calibrated* model on a **different protocol class** — a Gaitanos-style
10×6 s all-out battery — and checking it reproduces the rising-aerobic / falling-glycolytic direction;
(3) **ablate E** (`eAerMax=0`) and confirm the §6.10 direction disappears, then restore it and confirm
it returns — the causal check that E, not the fullness-taper artifact, produced the result.

**Bottom line:** field power+HR can *detect* the excess and justify a nonzero default; the **primary
calibration of eAerMax/τ_E requires one lab visit with a metabolic cart.** Flag any pure-field estimate
as low-confidence in the same channel the tool already uses for `fP`/`τ_off`.

---

## 5. Fitting, uncertainty, validation, instrumentation

### 5.1 Staged fit workflow (= the DAG)
`hygiene → {CP,W′} → pPmax → {τG | τP | fP-on-ridge} → {eAerMax,τ_E}`. Each stage conditions on all
above being **frozen**. Maps onto `fit_cp` → `fit_recovery`/`fit_all_rides` (which already takes `cp`
as a fixed argument and freezes `η`). **Stage 1 must clear the `cpWhy` gate before it is frozen** — a
provisional W′ taints every downstream parameter (`stage1-soft`). Inside the recovery stage, fit **τG
from a long-recovery Ferguson-anchored session** and **τP from a short-recovery ladder** with the other
held at its stage value, then a final joint polish with `fit_all_rides` + `agg()`. **Stage 4 (excess) is
last and is a fitter extension** — `fit_recovery` does not touch `eAerMax`/`τ_E`; fitting them before the
split is pinned lets them absorb its misfit (an over-drain is equally "fixed" by a bigger PCr tank or by
aerobic excess).

### 5.2 Regularisation / priors (so weak params don't rail to a bound)
The fitter already has box bounds (`fP∈[0.10,0.60]`, etc.) and a ridge prior in the `submax` branch.
Extend the ridge prior to the general fit, **weighted by informativeness**: `λ·Σ((θ−θ_prior)/σ_prior)²`
with `λ` scaling *down* as a session genuinely constrains a parameter (many bouts, short recovery, low
`refill`) and *up* when it does not — shrinkage toward literature when data is thin, converging to the
pure fit when data is rich. Bound `eAerMax ∈ [0, ~0.3·CP]`, `τ_E,on ∈ [30,180]`, shrunk hard toward 0 so
the flip must be *earned*. **Report each parameter as `data-identified` / `held-at-prior` /
`held-at-bound`** — a bound-hit (e.g. `fP=0.10`) is the strongest warning (data wanted to leave the
physiological range and was clamped), and should be distinguished from a mere wide spread.

### 5.3 Uncertainty — from binary flags to per-parameter CIs
Keep the existing flags (`few-efforts`/`narrow-range`/`low-R²`/`single-session`/`short-recovery`/`cv`)
as the first triage gate, then add real intervals: **(1) session bootstrap** — resample qualifying
sessions with replacement, recompute the `agg` estimate, report 2.5/97.5 percentiles (degenerates to
"soft" with one session — the honest signal); **(2) leave-one-session-out** stability + influential-
session detection (doubles as cross-validation); **(3) profile likelihood** for the single-session case
(trace the `optim` objective — a flat profile = unidentifiable → fall back to the prior; it visualises
the `(fP,τG)` ridge directly). The athlete sees `value ± band` with a **settled / soft / not-tested**
label (multiplicative ×/÷ bands for the τ's, additive ± for CP/W′/fP).

### 5.4 Out-of-sample validation (the decisive test — WP §6.6/§6.8)
Fit quality is *not* validation (the model near-supersets single-tank in depletion). **Hold out one
intermittent-to-failure session whose valleys straddle LT1**, predict (don't fit) its exhaustion + reserve
trace with frozen parameters, and require it to **beat a re-fit single-tank W′bal** (its own τ_W′ fit to
the same sessions) by more than the LOSO spread. Pass = exhaustion timing within ±10 % (or ±20 s), terminal
reserve within ±10 % of W′ of zero (reuse `ride_diag$margin`), trajectory RMSE below the test–retest noise
floor. Rotate the hold-out (k-fold over sessions). A win validates the **recovery law**, not the
two-compartment hypothesis (that is §6.10). Test–retest targets: CP ≤ ±3 %, W′ ≤ ±8 % (>±10 % ⇒
`stage1-soft`), pPmax ≤ ±5 %, τP within ×/÷1.5, τG ≤ ±25 %, eAerMax sign-stable.

### 5.5 The #88 flip-acceptance harness (what this protocol produces)
- **Gate A — no-regression:** regenerate both fixture generators, rerun `test_parity.py`, require
  |Δreserve| ≤ 0.1 J on non-intermittent traces (do not loosen — τP +1 % ≈ 4.8 J).
- **Gate B — the 30/15 fix:** the over-drain is removed **and** the fix comes from `eAerMax>0`, verified
  by ablation (E→0 returns the over-drain; E-on with the *frozen* split resolves it).
- **Gate C — §6.10 direction:** the calibrated E reproduces the rising-aerobic / falling-glycolytic
  direction out-of-sample on a different protocol class, with the E-ablation causal check, and without
  wrecking §6.9 separation.
- **Decision:** flip `eAerMax` to a nonzero default iff A+B+C pass and the full re-anchor (§4.4 tables,
  §6.8, §6.9, §6.10) shows no regression; else ship a documented negative result.

### 5.6 Instrumentation & data hygiene
- **1 Hz native power** — set the head unit to *Every Second*, not Smart Recording (which deflates MMP →
  biases CP/W′); `cadence_of()` must be in `[0.9,1.1]` (app warns otherwise).
- **Dropouts:** a gap *inside* a maximal effort invalidates that effort (zero-fill → false low); reject
  it. A pause *between* efforts is fine.
- **Developer-field FIT files** are readable via the base-R `read_power_raw()` fallback (native power
  field 7 + timestamp 253); confirm the fallback fired.
- **Power meter:** prefer dual-sided; zero-offset before every session; same meter across the whole
  battery (cross-meter offsets alias into W′ drift).
- **HR / VO₂ / [La] / NIRS:** HR is a freshness check only; VO₂/[La]/NIRS are the only channels that
  directly observe the aerobic-excess and glycolytic systems (the PCr gold standard, ³¹P-MRS, is
  unavailable in cycling — so fP/τP are never field-*or*-lab identifiable to gold standard; WP §6.5).

### 5.7 Calibration quality scorecard (the tier is the *minimum* across parameters)
| Tier | CP/W′ | Split (fP,τP,τG) | Excess | Meaning |
|---|---|---|---|---|
| **SETTLED** | `r2≥0.95`, `n≥3`, `rng≥5`, W′ from ≥2 sessions, retest ≤±8 % | ≥3 qualifying sessions, CIs inside prior band, no bound-hit, **passes out-of-sample vs re-fit single-tank** | tested via Gates A–C; direction reproducible | drives device settings + coaching |
| **PROVISIONAL** | clears the gate but single-session W′ or retest ±8–15 % | soft/prior-dominated; τP not tested | off / not tested | CP/W′ usable; split is an anchored default, say so |
| **REJECT** | any nonphysical/impossible/implausible or low-R²/few/narrow | `held-at-bound` (fP railed), no-converge, submax-only | conflated with soft split | do not export; recollect the named session |

The scorecard is a **to-do list keyed to the missing identifying session**, not a grade.

---

## 6. Integrated calendar (one athlete, ~5–6 weeks)

| Phase | When | Sessions | Yields |
|---|---|---|---|
| **0 · Lab anchor** *(optional, decisive)* | wk 0 | 1 visit: VO₂ cart + [La] (+NIRS) | LT1→`lt1Frac`, MLSS/CP cross-check, VO₂ slow component, NIRS→τP, [La]→τG |
| **1 · Power–duration** | wk 1–2 | 3–4 sessions, one maximal TTE each (2/5/8/12 min) + fresh sprint | **CP, W′, pPmax** |
| **2 · Recovery kinetics** | wk 3–4 | A (PCr ladder), B (gate sweep), C (short/glyco-pinned), D (long/refill) | **τP, τG, fP** (weak) |
| **3 · Aerobic excess** | wk 5 | on-kinetics 30/15, off-kinetics varied recovery, steady-state ceiling (VO₂ cart) + re-analyse 2026-07-20 | **eAerMax, τ_E,on/off** |
| **4 · Held-out validation** | wk 6 | 1 intermittent-to-failure, straddling LT1 (never fitted) | pass/fail vs re-fit single-tank; flip-gate evidence |

---

## 7. Honesty ledger (the through-line)

- **Trust from field power alone:** CP, W′, pPmax.
- **Field-weak (designed contrasts only):** τG, then τP.
- **Effectively assumed / physiology-selected:** fP (rides the `(fP,τG)` ridge — data picks a ridge,
  not a point; keep ~0.20–0.25), fatK.
- **Lab-only for a primary calibration:** eAerMax/τ_E (metabolic cart), τAer/τOn (VO₂ on-kinetics),
  lt1Frac (lactate test).
- **Never identifiable:** η (frozen at 1.0, degenerate with τP).
- **External anchors that rescue the weak cluster:** NIRS → τP, [La] → τG, VO₂ slow component → eAerMax.

A calibration is trustworthy only when Stage 1 is SETTLED from ≥2 fresh sessions (no downstream
parameter absorbing W′ error — the #87 guard), every split parameter is `data-identified` with a CI
inside its prior band and no bound-hit, it **passes out-of-sample intermittent prediction and beats a
re-fit single-tank W′bal**, and any nonzero `eAerMax` cleared the #88 flip harness. Anything less is
reported **provisional with the specific blocking flag named** — so the athlete knows which session to
go collect, rather than trusting a soft number.

---

## References (in-repo + added)
- White paper §4 (math/conservation), §6.5 (gold-standard limits), §6.6 (out-of-sample intermittent),
  §6.8 (informativeness ≠ accuracy), §6.9 (training-load separation), §6.10 (repeated-sprint biopsy
  test), §7 (assumptions/limitations). Literature review: Skiba W′bal, Ferguson 2010, Parolin 1999,
  Harris 1976, Bogdanis 1996/1998.
- CP/W′ testing standards: Jones & Vanhatalo 2017; Poole 2016; Karsten 2015; Triska 2017;
  Muniz-Pumares 2019. NIRS↔³¹P-MRS PCr cross-validation: Ryan 2013; Hart 2014; Layec 2017.
  Repeated-sprint E:R manipulation: Dennis 2022. VO₂ slow component: Pessoa Filho 2012; Burnley 2011;
  Bogdanis 1996.

*Design document — a calibration/test plan, not a change to the model. Parameters, flags, and fit
functions reference `tools/calibrate/R/model.R` and `app.R` as of the #90/#91 merges.*
