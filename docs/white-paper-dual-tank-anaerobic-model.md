# A Dual-Tank Model for Real-Time Tracking of Phosphocreatine and Glycolytic Energy Reserves in Cycling

**White paper — AnaerobicFuelTanks project**
*Version 0.1 · 2026-07-10*

---

## Abstract

Endurance-cycling analytics have converged on the Critical Power (CP) / W′ framework, in
which all work performed above a sustainable power asymptote is drawn from a single finite
reserve, W′. This lumps two physiologically distinct anaerobic systems — the fast
phosphocreatine (PCr / alactic) system and the slower glycolytic (lactic) system — into one
tank with a single recovery time constant. That simplification is convenient but discards the
information a rider most wants during hard, variable-intensity efforts: *which* reserve is being
spent, and *how fast* each will come back. This paper proposes a **dual-tank model** that splits
W′ into a fast PCr reserve and a slow glycolytic reserve, drives both from the instantaneous
power trace, and applies system-specific depletion and restoration laws drawn from the
bioenergetic and 31P-MRS literature. The model is deliberately reduced to be computable at 1 Hz
on a wrist- or bar-mounted device, and we specify a Garmin Connect IQ implementation that
displays live reserve, consumption, and depletion for both systems. We close with a validation
strategy and an explicit statement of the model's assumptions and limits.

---

## 1. Introduction

A power meter reports mechanical output, not metabolic cost. The bridge between the two is a
model of the body's energy-supply systems. The dominant bridge in cycling — the CP/W′ model —
treats supra-CP work as depletion of a single reservoir and sub-CP work as its exponential
refill (Skiba et al. 2012). It is power-native, validated, and computationally trivial, which is
why it underlies W′bal displays in GoldenCheetah, intervals.icu, and several head units.

Its central simplification is also its central weakness for real-time decision-making: **W′ is
one tank.** Physiologically, anaerobic capacity is at least two tanks with very different
dynamics (Margaria; di Prampero & Ferretti 1999):

- The **phosphocreatine (PCr / alactic)** system — high power, low capacity, **fast** oxidative
  recovery (seconds to a minute), but with recovery that is pH-sensitive and slows across
  repeated bouts.
- The **glycolytic (lactic)** system — larger capacity, lower peak power, and **slow** recovery
  (minutes) that effectively only proceeds at low intensity.

A rider deciding whether to cover the next surge cares which tank is empty. If the PCr tank is
full but glycolytic is depleted, a 5-second jump is fine but a 40-second dig is not — a distinction
the single-tank W′bal cannot express. The goal of this paper is a model that keeps the
power-native, on-device virtues of W′bal while restoring the two-system resolution.

---

## 2. Physiological background

**Phosphocreatine (alactic).** ATP is buffered by the creatine-kinase reaction (PCr + ADP →
ATP + Cr). Intramuscular PCr (~20–25 mmol·kg⁻¹ wet muscle) is the highest-power energy source
and is drawn on instantly at any power transient. Its resynthesis is oxidative and fast:
classic alactic O₂-debt half-time ≈ 30 s (Margaria); 31P-MRS gives recovery time constants
τ_PCr ≈ 20–40 s, strongly **pH-dependent** (acidosis slows it) and **biphasic** under high
glycolytic load (Harris et al. 1976; Yoshida et al. 2013, PMID 23662804). Recovery also **slows
progressively across repeated hard bouts.**

**Glycolytic (lactic).** Anaerobic glycolysis converts glycogen to lactate, supplying large ATP
flux for ~10 s–2 min. Its "fuel level" is best tracked as accumulated muscle/blood lactate — a
proxy for H⁺ and metabolite accumulation. Contribution decays across repeated sprints (≈40% of
ATP in the first of 10×6 s efforts, <10% by the last; Sci Rep 2024, DOI 10.1038/s41598-024-78916-z).
Restoration is slow (lactic O₂-debt half-time ≈ 15 min) and, mechanistically, proceeds fastest at
low intensity, effectively ceasing above the first lactate threshold (LT1).

**The onset that matters.** Both systems contribute from the start of a hard effort, but not
equally at first: PCr is drawn on instantly (it is the highest-power, immediate buffer), while
glycolytic flux takes several seconds to ramp up as glycogen phosphorylase is activated (Parolin et
al. 1999) — so the *early* demand is PCr-weighted, shifting toward a shared draw as glycolysis
engages. This graded onset — and the very different refill rates — is what the dual-tank model must
reproduce (it does so with a parallel, PCr-weighted draw and a glycolytic activation ramp; §4.2), not
a strict "PCr first, then glycolytic" hand-off.

**What the two "tanks" represent — and what they don't.** The "tank" is a deliberate
simplification for intuition and on-device display, not a claim that either system is a literal
reservoir that drains. The two sides are not even the same *kind* of quantity:

- The **PCr tank** does correspond to a real, depletable substrate store — intramuscular
  phosphocreatine — so "PCr empty" is close to literal.
- The **glycolytic "tank"** is better understood as **tolerance to accumulating fatigue-related
  metabolites** than as a fuel gauge. On the ~1–4 min timescale it represents, muscle glycogen is
  nowhere near exhausted; carbohydrate depletion is a separate, hours-long limiter this model does
  not address. What forces power down at the limit of a hard effort is the buildup of inorganic
  phosphate (Pi), H⁺ (acidosis), ADP, and extracellular K⁺ toward the limit of tolerance —
  consistent with exhaustion at CP/W′ coinciding with a reproducible low-PCr / high-metabolite
  state. (Lactate itself is largely a fuel and a marker, not the cause of force loss.)

This is the physiological reason the two recovery laws differ: PCr resynthesizes quickly, whereas
the glycolytic side recovers slowly and only at low intensity because it reflects *clearance and
buffering* of accumulated byproducts, which need aerobic metabolism and time — exactly why the
model tracks the glycolytic state as an accumulation variable (a muscle-lactate proxy; §4.1) and
gates its recovery below LT1. Muscle fatigue is multifactorial and still debated; W′ deliberately
lumps it into one number for usability. In short: **the PCr tank is a fuel that depletes; the
glycolytic "tank" is a byproduct bucket that fills.**

---

## 3. Prior models (and why a reduced dual-tank sits between them)

Three model families exist (full survey in `literature-review-anaerobic-models.md`):

- **Family A — CP / W′-balance** (Skiba 2012/2015; Bartram 2018; Froncioni–Clarke). Power-native
  and on-device-friendly, but **one lumped tank, single recovery τ.** Recovery
  `τ_W′ = 546·e^(−0.01·D_CP) + 316 s` cannot represent fast PCr + slow glycolytic simultaneously.
- **Family B — hydraulic tank models** (Morton 1986; Weigend `three_comp_hyd` 2021). **Two
  explicit anaerobic vessels** (AnF = phosphagen, AnS = glycolytic) plus an aerobic vessel;
  out-predicts W′bal for intermittent recovery (arXiv 2108.04510). But its 8 parameters are
  abstract and fit per-athlete by evolutionary computation — heavy for an embedded target.
- **Family C — bioenergetic supply/demand ODEs** (EJAP 2023, PMID 37369795). Explicit alactic /
  lactic / aerobic metabolic-rate terms, with an efficiency-limited PCr recovery and a
  power-gated lactate-removal law. Mechanistically ideal but has 17 parameters and needs
  grey-box fitting.

**The gap:** Family A is implementable but under-resolved; Families B and C resolve the two
systems but are too heavy to run and calibrate on a head unit. The dual-tank model below keeps the
two-tank resolution of B/C with the on-device simplicity of A.

To be precise about what "lighter" means here, because it is easy to oversell: the model's core
parameter count (`CP, W′, f_p, P_p_max, τ_p, τ_g, LT1, η, τ_on`, ~9, plus two optional realism
terms) is essentially the **same** as the hydraulic model's eight — it is **not** a smaller model.
The difference is *where the parameters come from*. Only `CP` and `W′` are fitted per athlete (from
a standard CP test); the rest are **hard-coded to literature defaults** rather than fit by
evolutionary computation. That buys on-device simplicity and a trivial calibration, at a real cost:
the load-bearing defaults (`f_p`, `P_p_max`, `LT1`, and the recovery τ's) are exactly the quantities
a CP test does **not** determine, so the model's two-system resolution rests on assumptions, not
measurements. That is a legitimate identifiability-for-convenience trade — but it is a trade, and the
sections below are explicit about which numbers are earned and which are assumed.

---

## 4. The dual-tank model

### 4.1 State and parameters

Two energy reserves (Joules), each with a fixed capacity:

- `R_p` — **PCr reserve**, capacity `C_p`
- `R_g` — **glycolytic reserve**, capacity `C_g`
- Total anaerobic capacity `W′ = C_p + C_g`

Rider-supplied parameters (all obtainable from a maximal power–duration / CP test):

| Symbol | Meaning | Typical default |
|---|---|---|
| `CP` | critical power (W) | from 3-/12-min CP test (≈ FTP + a few %) |
| `W′` | total work above CP (J) | from same test (~15–25 kJ) |
| `f_p` | fraction of W′ assigned to the PCr tank | **0.25** (weakly identified — see §7) |
| `P_p_max` | PCr peak (immediate) power above CP (W) | ≈ P₁ₛ − CP (best 1 s power − CP) |
| `g_pmax` | glycolytic peak power, as a fraction of `P_p_max` | 0.5·`P_p_max` (PCr is the higher-power system) |
| `τ_p` | PCr recovery time constant (s) | 22 (fast, pH-modulated) |
| `τ_g` | glycolytic recovery time constant (s) | 360 (slow) |
| `LT1` | first lactate threshold power (W); recovery of the glycolytic tank proceeds below it | **measured** (a threshold test), *not* a fixed %CP |
| `η` | PCr recovery-rate efficiency (see note) | 0.80 |

Derived: `C_p = f_p·W′`, `C_g = (1 − f_p)·W′`. Initial state `R_p = C_p`, `R_g = C_g` (full).

Three of these deserve flags up front, because the defaults are doing real work:

- **`f_p` is weakly identified, not measured.** It is *not* determined by a CP test. It is nudged by
  the reconstitution curve (§6.3) and by physiological alactic-fraction estimates, both of which put
  it **below** the 0.35 we used previously — hence the revised 0.25 default. It should be personalized.
- **`P_p_max ≈ P₁ₛ − CP`** (not a 5 s figure): at the very first second glycolysis is barely active
  (`g ≈ 1 − e^(−1/6) ≈ 15%`), so the instantaneous ceiling is close to, but slightly above, CP +
  `P_p_max` — i.e. `P₁ₛ − CP` mildly over-attributes to PCr and should be read as an upper bound.
- **`η` is a recovery-*rate* efficiency, not hysteresis.** In the recovery law below it is
  mathematically equivalent to scaling `τ_p` to `τ_p/η` (the asymptote is still full recovery, so
  there is no path dependence). It is retained only as an interpretable knob mapping to the
  aerobic-efficiency term of the EJAP 2023 model, and is degenerate with `τ_p` when fitted — the two
  cannot be identified separately. A *true* efficiency loss (incomplete recovery under fatigue) would
  require an asymptote **below** `C_p`; that is a possible extension, not what `η` does here.

### 4.2 The 1 Hz update

Let `P` be instantaneous power (W) and `Δt = 1 s`. Define the demand relative to aerobic supply
as `Δ = P − CP`.

**Case 1 — depletion (`Δ > 0`, above CP).** Demand `need = Δ·Δt` (J) is met by **both systems in
parallel**. This matters: glycolytic ATP supply is not instantaneous. Glycogen phosphorylase (the
rate-limiting glycolytic enzyme) transforms to its active form over the first several seconds of
maximal effort — Parolin *et al.* (1999) measured it rising from 12% at rest to 47% by 6 s — while
phosphocreatine is the immediate buffer, near-fully drawn within the first ~10 s (Bogdanis *et al.*
1996); both contribute from the onset, not in sequence (González‑Alonso *et al.* 2000). We model this
with a **glycolytic activation** term `g ∈ [0,1]` that ramps first-order with a time constant
`τ_on ≈ 6 s` while above CP and relaxes back during recovery:

```
g ← g + (1 − g)·(1 − exp(−Δt/τ_on))      # activation ("glycolytic inertia"); decays below CP
g_pmax = 0.5·P_p_max                      # glycolytic peak rate < PCr peak rate

# Rate-proportional split: demand shared in proportion to each system's available rate.
total_rate = P_p_max + g_pmax·g
share_p = need · P_p_max / total_rate      # at g=0 PCr covers all; at g=1 a ~2:1 PCr:glycolytic split
share_g = need − share_p

take_p = min(share_p, R_p, P_p_max·Δt)     # both systems are rate-capped AND capacity-limited
take_g = min(share_g, R_g, g_pmax·Δt)
unmet  = need − take_p − take_g
# any shortfall (a tank empty or rate-capped) spills to the partner, then to deficit:
take_g += min(unmet, R_g − take_g, g_pmax·Δt − take_g);   unmet −= …
take_p += min(unmet, R_p − take_p, P_p_max·Δt − take_p);  unmet −= …
R_p −= take_p;  R_g −= take_g

if unmet > 0:  exhaustion = true          # both tanks empty/capped → rider at/over the limit
```

At effort onset `g ≈ 0`, so PCr supplies essentially everything (the fast transient); as `g → 1`
over a few seconds the two tanks drain together — but *not* equally: because PCr is the higher-power
system (`g_pmax = 0.5·P_p_max`), the steady-state split is roughly **2:1 in PCr's favour**, and the
glycolytic tank is rate-limited to `g_pmax` so it cannot absorb an arbitrarily large one-second
demand. Once the small PCr tank empties, glycolysis carries the rest up to its own cap.

**On identifiability (and consistency with §7).** The parallel draw is the physiologically faithful
choice for the *live display*, and `τ_on` is a literature-set constant (Parolin 1999), not a fitted
one. But we are careful not to over-claim: the depletion split is **not** identifiable from power at
all — total draw above CP is all the pedals see, and any (`f_p`, `g_pmax`) that sums to the same
total is observationally equivalent. In *principle* the bi-exponential **recovery** of W′ constrains
the split (a fast PCr component + a slow glycolytic component); in *practice* that fit is
ill-conditioned (§6.3 shows the fast component is invisible at standard reconstitution sampling), so
`f_p` ends up **assumed and weakly constrained**, not recovered. This is the §7 position, and it is
the one to trust — the reserves are a plausible decomposition, not measured latent state.

**Case 2 — restoration (`Δ ≤ 0`, at/below CP).** Recovery "headroom" is `CP − P`. Each tank
refills exponentially toward full; glycolytic refill is gated by intensity.

```
# PCr: fast, oxidative (η rescales the effective rate to τ_p/η — see §4.1 note)
R_p += η · (C_p − R_p) · (1 − exp(−Δt/τ_p))

# Glycolytic: slow, only meaningfully below LT1 (a MEASURED power, not a %CP)
if P < LT1:
    gate = (LT1 − P) / LT1                        # 0 at LT1, → 1 toward zero power
    R_g += gate · (C_g − R_g) · (1 − exp(−Δt/τ_g))
```

`LT1` is the rider's **first lactate threshold in watts**, from a threshold test — *not* a fixed
fraction of CP. LT1 and CP vary independently (LT1 is roughly 65–85% of CP depending on training
status), and this gate decides whether the glycolytic tank refills at all during tempo/endurance
riding, so getting it wrong there is consequential. Where only CP is known, `LT1 ≈ 0.80·CP` is a
fallback, but it is the weakest default in the model and should be replaced by a real measurement.

**Optional realism (recommended, off by default):**
- *pH-slowed / fatiguing PCr recovery:* scale `τ_p` upward as the glycolytic tank is emptier,
  e.g. `τ_p_eff = τ_p · (1 + k·(1 − R_g/C_g))`, capturing the observed slowing across repeated bouts.
- *Aerobic ramp:* replace the hard `CP` boundary with a first-order aerobic supply
  `A(t)` that rises toward `min(P, CP)` with `τ_aer ≈ 25 s`, and use `need = (P − A)·Δt`. This
  reproduces the onset "oxygen deficit" that transiently loads the anaerobic tanks even below CP.

### 4.3 Reported quantities

- **PCr reserve** `= R_p / C_p` (0–100%) — how much "punch" is left.
- **Glycolytic reserve** `= R_g / C_g` (0–100%) — how much "sustained dig" is left.
- **Consumption rate** (per system, W) — `take_p/Δt`, `take_g/Δt`, the live draw on each tank.
- **Combined W′bal** `= (R_p + R_g)/W′` — backward-compatible with existing single-tank displays.
- **Depletion / exhaustion flag** — both reserves at/near zero.

### 4.4 Why this behaves correctly

- A short, very hard surge draws mostly from `R_p` (glycolysis has not yet ramped in),
  and `R_p` visibly refills within ~30–60 s of easy pedaling — matching PCr physiology.
- A sustained supra-CP effort empties `R_p` quickly, then leans on `R_g`, which only comes back over
  minutes and only when the rider drops below LT1 — matching glycolytic physiology.
- **On "generalizing W′bal" — a careful claim.** In *depletion* the model is a faithful
  generalization: as long as no tank is empty or rate-capped, `take_p + take_g = need`, so the summed
  draw above CP matches standard W′bal exactly. In *recovery* it is deliberately **different**:
  bi-exponential, with an LT1 gate and the `η`/`τ_p` rate — it does **not** reduce to Skiba's single
  `τ_W′ = 546·e^(−0.01·D_CP) + 316`. Nor does `f_p → 0` recover standard W′bal: it collapses to a
  *single glycolytic tank* with `τ_g` and an LT1 gate, which is still not the incumbent's recovery
  law. So this is a generalization in **structure and depletion behaviour**, not a strict superset
  that contains W′bal as one parameter setting. The divergence is intentional — the whole point is
  that single-tank recovery is the thing we are trying to improve on.

---

## 5. Real-time on-device implementation (Garmin Connect IQ)

The model's per-second cost is a handful of multiplies and one `exp()` per tank — trivial for a
head unit. A companion document, `connectiq-app-spec-and-prompt.md`, gives the full technical
specification and a ready-to-use build prompt. Summary of the target design:

- **App type:** a custom full-screen **Data Field** (`Toybox.WatchUi.DataField`), which the head
  unit calls once per second — a natural fit for the `Δt = 1 s` update.
- **Input:** `Activity.Info.currentPower` inside `compute(info)`.
- **Configuration:** `CP`, `W′`, `f_p`, and the recovery constants exposed via Connect IQ app
  settings (`Application.Properties`), so a rider enters them from Garmin Connect.
- **Display:** two vertical bar gauges (PCr and glycolytic reserve) with numeric % and color
  bands (green → amber → red), plus optional live consumption in W.
- **Recording:** write both reserves and consumption to the FIT file via `FitContributor` fields
  so they sync to Garmin Connect / intervals.icu / Strava for post-ride analysis.
- **Footprint:** two `Float` state variables, no arrays, well within Connect IQ memory budgets.

---

## 6. Validation strategy

The model is a hypothesis; it must be checked against data before its numbers are trusted. The
honest difficulty is that the model's *headline feature* — a separate PCr reserve tracked in real
cycling — is the hardest thing to validate, so we separate tests that only check the plumbing from
the one test that would actually earn the second tank.

1. **Face validity / unit tests** — synthetic power traces (single sprint, repeated sprints,
   supra-CP hold, sub-CP recovery) should produce the qualitative behaviours in §4.4.
2. **Backward compatibility — *depletion only*.** Summing the tanks reproduces a reference W′bal
   implementation (Froncioni–Clarke) on the same trace **in depletion** (`take_p + take_g = need`).
   It will **not** match in recovery, by construction (§4.4), so this test must be scoped to
   above-CP segments — a test that expected agreement everywhere is one the model is designed to fail.
3. **Reconstitution targets — with two caveats.** After a full W′ depletion, combined recovery can
   be compared to the published curve (≈37% / 65% / 86% at 2 / 6 / 15 min; Chorley & Lamb 2020). But:
   (a) **this curve is blind to the fast tank.** A `τ_p ≈ 22 s` process is `1 − e^(−120/22) ≈ 99.6%`
   complete by the first (2 min) sample, so passing this test validates the *glycolytic* recovery and
   the *size* of the PCr offset — **not** the PCr recovery kinetics, i.e. not the feature that
   distinguishes this model from W′bal. To constrain `τ_p` you need recovery samples at ~10/20/30/45/60
   s (test 5). (b) **our defaults do not hit it, and that is informative.** At the old `f_p = 0.35` the
   model recovers ~53% by 2 min against the 37% target — a 16-point overshoot — because putting 35% of
   W′ in a tank that is ~fully back by 2 min forces combined 2-min recovery above 35%. Matching the
   curve pulls `f_p` **down** (~0.13 at passive rest, ~0.25 at a realistic soft-pedal recovery power);
   this is the main reason the default was revised to 0.25. Note also that a single slow exponential
   cannot fit all three points exactly (the empirical curve is itself multi-exponential), so this is a
   *soft constraint on `f_p`*, not a pass/fail on the decomposition.
4. **Fast-recovery kinetics (the missing piece).** The load-bearing test for `τ_p` is a repeated-bout
   protocol with **early** recovery sampling — e.g. all-out efforts separated by 10/20/30/45/60 s — and
   the between-bout power recovery correlated with modelled PCr recovery (as Bogdanis 1996 did for
   PCr). Standard reconstitution data cannot supply this; it must be measured deliberately.
5. **System-specific truth (lab) — and its hard limit.** Blood-lactate kinetics can corroborate the
   glycolytic tank, but the PCr tank's gold standard, **31P-MRS, is essentially unavailable in real
   cycling**: the measurement requires the muscle to be inside a magnet, so it exists only for
   small-muscle knee-extension or immediate post-exercise, not whole-body cycling. The model's headline
   novelty therefore **cannot be checked against the gold standard in the modality it targets** — a
   limitation to state plainly, not paper over.
6. **The test that earns the second tank — out-of-sample intermittent tolerance.** Because the model
   is a near-superset of single-tank in depletion, it can *always* fit at least as well, so "it fits
   better" is guaranteed and is **not** evidence the compartments are real. The decisive test is a
   **head-to-head against single-tank W′bal on an out-of-sample, intermittent-effort tolerance
   prediction** — the same protocol class on which the hydraulic model beat W′bal (arXiv 2108.04510):
   predict time-to-exhaustion / whether a prescribed interval set is completable, where the dual-tank
   and single-tank models make *different* predictions, and show the dual-tank wins. Until that test is
   passed, the second tank is a plausible, physiologically-motivated decomposition — not a validated one.
7. **Field calibration** — fit `f_p`, `P_p_max`, and the `τ`'s per athlete to maximal-effort tests
   (a sprint-then-hold or repeated-bout protocol) rather than trusting defaults.

---

## 7. Assumptions and limitations

- **The PCr/glycolytic split `f_p` is assumed and weakly constrained, not measured.** Power alone
  cannot identify the depletion split (§4.2); recovery can in principle, but the fast component is
  invisible at standard sampling (§6.3), so `f_p` is effectively an assumption. Independent lines
  (reconstitution offset ~0.13–0.25; physiological alactic-fraction estimates ~0.20–0.30; some
  multi-ride calibrations higher) put it in a broad ~0.15–0.35 band. We default to 0.25 and treat it
  as a per-athlete calibration target — the model's outputs are sensitive to it.
- **The reserves are a decomposition, not latent state.** The two bars are a physiologically-motivated
  split of one measured quantity (W′bal), not two independently measured reserves. When the PCr tank is
  full — which, given `τ_p ≈ 22 s`, is most of the time except the ~30–60 s after a hard effort — the
  glycolytic bar is an affine transform of the existing single W′bal (`W′bal = f_p + (1−f_p)·R_g/C_g`),
  so it carries no new information there. The PCr bar adds decision-relevant content **only** in those
  post-surge transients. Those transients *are* where race decisions concentrate (can I cover this
  attack right after the last one?), which is the case for the display — but the honest framing is a
  heuristic decomposition whose split is assumed, not "the two numbers a rider races on" as if both
  were measured.
- **`η` is degenerate with `τ_p`** (§4.1): as written it rescales the recovery rate, not a true
  efficiency, and the two cannot be fitted separately. Reported `η`/`τ_p` pairs are non-unique.
- **`LT1` should be measured, not derived from CP.** The `0.80·CP` fallback will be wrong for many
  riders (LT1 ranges ~65–85% of CP), and it gates whether the glycolytic tank recovers during tempo,
  so a bad value materially changes recovery estimates.
- **The headline feature is hard to validate in-modality.** 31P-MRS cannot be run during real cycling
  (§6.5), and depletion "fit-better" is guaranteed by construction, so the second tank is only earned
  by an out-of-sample intermittent-tolerance head-to-head vs single-tank (§6.6) — not yet performed here.
- **Fixed time constants** ignore the documented pH-dependence and bout-to-bout slowing of PCr
  recovery unless the optional fatigue term is enabled.
- **Hard CP boundary** omits the aerobic slow component and onset kinetics unless the optional
  aerobic-ramp term is enabled; expect over-attribution to anaerobic tanks in long low-intensity
  recovery (the same failure mode reported for the EJAP 2023 model).
- **Power is whole-body and mechanical**, not muscle-specific; the model cannot see local fatigue,
  cadence, or fiber-type effects.
- **Not medical or diagnostic.** This is a training/pacing aid; tank levels are estimates, not
  measurements of muscle chemistry.
- **Parameters drift** with fitness, fatigue, heat, and altitude; periodic re-testing is required.

---

## 8. Conclusion

The single-tank W′ model earned its place by being power-native and light enough to run anywhere,
but it answers "how much anaerobic work is left?" without answering "in which system?" The
dual-tank model proposed here offers a physiologically-motivated split at negligible computational
cost: divide W′ into a fast, rate-limited, fast-recovering PCr tank and a slow, large,
slowly-recovering glycolytic tank; drain them **in parallel** from the power trace (PCr-weighted,
with glycolysis ramping in); and refill them with system-specific, intensity-gated laws. It
generalizes W′bal in depletion and diverges from it — deliberately — in recovery, it runs at 1 Hz on
a Garmin head unit, and it surfaces a two-system decomposition — *punch left* and *dig left* — that
is most informative in the transients where pacing decisions concentrate.

Two honest caveats set the agenda. The split `f_p` is **assumed, not measured**, and the display's
extra resolution over single-tank W′bal is real but concentrated in post-surge windows. And the
decomposition is not yet **validated**: the tests that only check the plumbing (backward
compatibility, reconstitution offset) it can pass, but the one that would earn the second tank — an
out-of-sample intermittent-tolerance win over single-tank W′bal — remains to be run, and the PCr
gold standard (31P-MRS) is unavailable in real cycling. The accompanying Connect IQ specification
turns the model into a live data field; the open questions are calibration (`f_p`, `LT1`, per-athlete
τ) and that decisive head-to-head field validation.

---

## References

See `docs/literature-review-anaerobic-models.md` for the full annotated bibliography with DOIs
and PMIDs. Primary sources for this paper:

- Skiba PL et al. 2012, *Med Sci Sports Exerc* — W′bal integral model. PMID 22382171, DOI 10.1249/MSS.0b013e31824cfdc0.
- Skiba PL et al. 2015 — differential W′bal. DOI 10.1249/MSS.0000000000000226.
- Bartram J et al. 2018, *IJSPP* — elite τ_W′ recalibration. DOI 10.1123/ijspp.2017-0356.
- Chorley A, Lamb K 2020, *Sports (Basel)* — CP/W′ reconstitution review. DOI 10.3390/sports8090123 (PMC7552657).
- Morton RH 1986, *J Math Biol* — three-component hydraulic model. DOI 10.1007/BF01236892.
- Weigend F, Behncke, Skiba 2021 — hydraulic model & `three_comp_hyd`. arXiv 2104.07903 / 2108.04510.
- Dynamic bioenergetic model, intermittent cycling, *Eur J Appl Physiol* 2023. PMID 37369795, DOI 10.1007/s00421-023-05256-7 (PMC10638188).
- di Prampero PE, Ferretti G 1999, *Respir Physiol* — anaerobic energetics reappraisal. PMID 10647856, DOI 10.1016/S0034-5687(99)00083-3.
- Harris RC et al. 1976 — biphasic PCr resynthesis. *Pflügers Arch*.
- Yoshida et al. 2013, *Scand J Med Sci Sports* — τ_PCr by muscle. PMID 23662804, DOI 10.1111/sms.12081.
- Parolin ML et al. 1999, *Am J Physiol Endocrinol Metab* — glycogen phosphorylase / PDH activation kinetics during maximal intermittent exercise (glycolytic activation over the first ~6 s). PMID 10567017, DOI 10.1152/ajpendo.1999.277.5.E890.
- Bogdanis GC et al. 1996, *J Appl Physiol* — PCr and aerobic contribution during repeated sprints (PCr near-fully used in first 10 s). PMID 8964751, DOI 10.1152/jappl.1996.80.3.876.
- González‑Alonso J et al. 2000, *J Physiol* — heat production at exercise onset; PCr + glycogenolysis initially provide most energy. PMID 10766936, DOI 10.1111/j.1469-7793.2000.00603.x.
- Bangsbo J et al. 1990, *J Physiol* — anaerobic energy production and O₂ deficit during exhaustive exercise. PMID 2352192, DOI 10.1113/jphysiol.1990.sp018000.

*Sourcing note:* equations for the incumbent models were cross-checked against PubMed Central
full text (PMC7552657, PMC10638188); typeset equations there were image-embedded, so published
closed forms were reconstructed from the surviving prose and standard literature. Verify exact
coefficients against publisher PDFs before hard-coding.
