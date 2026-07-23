# A Dual-Tank Model for Real-Time Tracking of Phosphocreatine and Glycolytic Energy Reserves in Cycling

**White paper — AnaerobicFuelTanks project**
*Version 0.7 · 2026-07-12 (recovery-law fix: the linear LT1 gate is replaced by Skiba's intensity-dependent recovery shape, so the model now completes a standard 4×4; the tanks are reframed as compartments of W′, not of muscle metabolites — §4.1a; §6.9's mechanism is corrected to the glycolytic flux ceiling; and a new §6.10 runs the model against biopsy data and reports where it fails)*

> **Scope and status (read this once).** This is a **physiologically-motivated decomposition of one
> measured quantity — single-tank W′bal — whose split fraction `f_p` is assumed, not measured** (power
> cannot identify the depletion split; §4.2). The two bars are **compartments of W′**, named for their
> dominant metabolic system; the metabolic identification is *motivation, not a measured claim* — W′
> recovers ~4× faster than the muscle metabolites it is named after (§4.1a), so the "PCr bar" is a
> fast-reserve-of-W′ readout, not a muscle-PCr gauge. The characterisation is narrow: **during steady
> supra-CP effort both bars are affine in W′bal** (`R_p/C_p ≈ R_g/C_g ≈ W′bal + const`; §4.2, §4.4). But
> the earlier claim that the PCr bar is affine "most of the time" is **withdrawn**: under the
> oxidative-headroom recovery gate the effective PCr recovery constant is 100–500 s while a rider is
> actually pedalling (not 27 s), so the PCr bar is *live* for a substantial fraction of interval-ride time
> (§6.8 measures 20–79%). The "affine most of the time" caveat applies to stopped or easy recovery, not to
> riding. **Non-redundant content lives in the transients:** the glycolytic *activation ramp* at onset
> (`τ_on` measured, `τ_off` not) and the *PCr recovery transient* after hard efforts. **There is still no
> experiment showing the two-bar decomposition is *more correct* than single-tank W′bal** — that requires
> the recovery-law head-to-head (§6.6). The v0.6 claim that the compartments are "unfalsifiable
> in-modality — permanently" is also **withdrawn** (§6.10): muscle biopsy during cycle ergometry *is*
> in-modality compartment-level data, it is already in the bibliography, and when the model is run against
> it (repeated-sprint ATP partitioning) it **fails in level and direction** — the first genuinely
> falsifiable result in the project. What survives: v0.5–0.6's **usefulness** arguments. (i) On real
> interval rides the PCr bar is informative ~45% of the time (§6.8). (ii) For **training**, the cumulative
> per-system load separates an alactic from a glycolytic session — but the separation is driven by the
> **glycolytic flux ceiling scaled by the ramp** (not the ramp alone, as v0.6 claimed; §6.9), the metric
> is blind to *submaximal* alactic work, and it must beat a zero-parameter "fraction of work in efforts
> <15 s" stopwatch baseline, not just W′bal. `f_p`, `τ_off`, `g_rate`, the emergent `τ_dep`, and both
> recovery gates (`gate_p` and the LT1-band shape) are assumed. The rest of the paper builds on these; it
> does not re-litigate them.

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
bioenergetic and 31P-MRS literature. We are explicit up front about what this is: a
**physiologically-motivated decomposition of one measured quantity (W′bal) whose split is assumed,
not measured**, and whose extra resolution over single-tank W′bal is real but concentrated in the
transients after hard efforts. It generalizes W′bal in depletion and diverges from it — by design —
in recovery. The model is deliberately reduced to be computable at 1 Hz on a wrist- or bar-mounted
device, and we specify a Garmin Connect IQ implementation that displays live reserve, consumption,
and depletion for both systems. We close with a validation strategy — including the one out-of-sample
test that would actually earn the second tank — and an explicit statement of the model's assumptions
and limits.

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

**There are two distinct use cases, and they are informed by different outputs.** The first —
*pacing/racing* — uses the live bars in the moment ("can I cover this attack?"); its value is
concentrated in the post-effort transients (§7), and is real but narrow. The second — **training
prescription and load monitoring** — uses the *cumulative per-system load* over a session, and it is
where the decomposition is most clearly worth more than W′bal (§6.9). The two anaerobic systems carry
very different **physiological and recovery costs**: PCr-based (alactic) surges — short, high-power, with
adequate recovery — resynthesise in seconds-to-a-minute and can be repeated at high volume with little
systemic fatigue or metabolite accumulation; glycolytic surges accumulate H⁺/Pi and clear over many
minutes (lactate t½ ≈ 1366 s; Ferguson 2010), and cost far more recovery. An athlete who wants to
*target* the PCr system — alactic power, repeat-sprint ability — needs to keep efforts short and
recoveries full enough that glycolysis stays disengaged, and to know, per session, how much of the
anaerobic work was alactic vs glycolytic. W′bal collapses that to one number; the two-tank model does
not (§6.9).

Two honest qualifications, stated here rather than buried in §7. First, the split is a **modeling
assumption**, not a measurement — power alone cannot identify how W′ divides between the two systems
(§4.2). Second, the extra resolution is **concentrated in transients**: whenever the fast reserve is
full the glycolytic reserve is just an affine rescaling of single W′bal. But note the fast reserve is
*not* full "most of the time" while riding: under the oxidative-headroom recovery gate (§4.2) its
effective recovery constant is 100–500 s at typical soft-pedal powers, not the 27 s of a stopped rider,
so the bar stays live through the recovery valleys of an interval session (§6.8: 20–79% of ride time).
The model earns its keep as a *heuristic decomposition of W′*, not as two independently measured
reserves — and, per §4.1a, the tanks are compartments of W′, not of muscle metabolites.

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
proxy for H⁺ and metabolite accumulation. Critically, **glycolytic flux itself *falls* across repeated
maximal sprints**: acidosis inhibits phosphorylase and phosphofructokinase, so the glycolytic ATP
contribution decays from ≈40% of total ATP in the first of 10×6 s efforts to <10% by the last (Gaitanos
1993; the biopsy time-courses reviewed in *Sci Rep* 2024, DOI 10.1038/s41598-024-78916-z), while the
**aerobic** contribution rises to absorb the shortfall (~29%→43% between sprints; Bogdanis 1996).
Restoration of the glycolytic reserve is slow (lactic O₂-debt half-time ≈ 15 min) and, mechanistically,
proceeds fastest at low intensity, effectively ceasing above the first lactate threshold (LT1). *The
model as shipped has no term for glycolytic flux falling with fatigue — a documented failure it now runs
against explicitly (§6.10), with an optional term to partially address it.*

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
free-parameter count (`CP, W′, f_p, P_p_max, g_rate, τ_p, τ_g, τ_on, LT1`, with `τ_off = τ_on` by
default — **nine free numeric parameters**, plus *three* optional realism terms and *two* functional-form
gates — `gate_p` (PCr oxidative-headroom) and the intensity-dependent glycolytic recovery shape — each an
assumption in its own right, now flagged in §7) is essentially the hydraulic model's eight — **the same
size, not a smaller model.**
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

The model has **nine free numeric parameters** (plus `τ_off = τ_on`, three optional realism terms, and two
functional-form gates — see §3). Only `CP` and `W′` come from a CP test; the rest are literature-fixed
defaults (see §3 — this is a real count, not a small one):

| Symbol | Meaning | Typical default |
|---|---|---|
| `CP` | critical power (W) | from 3-/12-min CP test (≈ FTP + a few %) |
| `W′` | total work above CP (J) | from same test (~15–25 kJ) |
| `f_p` | fraction of W′ assigned to the PCr tank | **0.25** — *assumed* (physiology, not data; §7) |
| `P_p_max` | PCr peak power above CP (W), at a **full** tank | ≈ P₁ₛ − CP (best 1 s power − CP) |
| `g_rate` | glycolytic peak flux as a fraction of PCr peak flux (a ratio) | **0.5 — load-bearing** (di Prampero & Ferretti 1999); band ~0.3–0.7, drives §6.9's headline (sep 48→33 pts across the band); flag, not a settled constant |
| `τ_p` | **fast-reserve** recovery time constant (s) — a W′-recovery constant, *not* muscle-PCr resynthesis | **27** — set by the W′-reconstitution curve (§4.1a), *exonerated* there; do **not** read the bar as biopsy PCr (W′ recovers ~4× faster; §4.1a). Gated by oxidative headroom (§4.2) |
| `τ_g` | **slow-reserve** recovery time constant (s) | **470** — reconstitution fit (Ferguson 2010 at 20 W ⇒ gate ≈ 0.90; joint optimum with `f_p`; §4.1a) |
| `τ_on` | glycolytic activation time constant (s) | 6 (Parolin 1999) |
| `τ_off` | glycolytic **de**-activation time constant (s) | = `τ_on` — *assumed*, and now shown **not** load-bearing (a 20× change moves §6.9 by 1–2 pts; §6.9, §7) |
| `LT1` | first lactate threshold power (W) — sets the *band* of the glycolytic recovery shape | **measured** (a threshold test), *not* a fixed %CP |
| `gate_p` | PCr oxidative-headroom recovery gate `(CP−P)/CP` — a *functional form*, no free constant | **assumed** (v0.5); shape is a choice (linear/√/sigmoid swing the headline recovery number ~21–31 pts; §7) |
| `g_fat` | *optional* glycolytic flux-fatigue exponent, `rate_g·(R_g/C_g)^{g_fat}` | **0 (off)** by default — moves repeated-sprint partition toward the biopsy direction but does not reproduce it (§6.10) |

Derived: `C_p = f_p·W′`, `C_g = (1 − f_p)·W′`. Initial state `R_p = C_p`, `R_g = C_g` (full).

**A note on naming (new in v0.7).** We call the two reserves the **fast reserve** (`R_p`, "PCr") and the
**slow reserve** (`R_g`, "glycolytic"). The metabolic labels are **motivation, not a measured claim**:
§4.1a shows the reserves are compartments of *W′*, with the right internal fast/slow ratio (~18×) but an
absolute timescale ~4× faster than the muscle metabolites they are named after — because W′ itself
recovers ~4× faster than PCr or lactate. Every "the bar equals muscle PCr" reading in earlier drafts is
therefore withdrawn; the bar is a fast-recovering component of W′bal. This rename is the honest resolution
of the identifiability problem the review series has circled (Reviewer 2, third report): the model is
right about W′'s internal dynamics and agnostic about the metabolites.

**Free-parameter count.** Nine free numeric parameters (`CP, W′, f_p, P_p_max, g_rate, τ_p, τ_g, τ_on,
LT1`); `τ_off = τ_on` by default. Two functional-form gates (`gate_p`, the glycolytic recovery shape) and
three optional realism terms (pH-slowed PCr recovery, aerobic ramp, glycolytic flux fatigue) sit on top.
Only `CP` and `W′` are fitted per athlete; the rest are literature-set. That is essentially the hydraulic
model's eight — **the same size, but literature-set rather than fitted** (the real trade; §3). A fast-
reserve *depletion* kinetic, `τ_dep = C_p/P_p_max`, also falls out of the above (§4.4) and is equally
assumed — see §7.

**`η` was removed (was 0.80).** The former "recovery efficiency" only rescaled the effective PCr
recovery constant to `τ_p/η` — no sub-`C_p` asymptote, so not a true efficiency, and degenerate with
`τ_p` when fitted. It silently made the effective constant ≈ 27.6 s while the table advertised 22 s.
**`τ_p = 27 s` is now justified on its own terms:** it sits inside the 31P-MRS `τ_PCr` range of 20–40 s
(Yoshida 2013; Harris 1976) — *not* as "22 inflated by η" (that would just re-import the double-count).
The `eta` settings key remains, defaulting to 1.0 (identity) with a **deprecation note**, so a future
maintainer cannot silently reintroduce the rescale. (The pulmonary-VO₂ recovery half-time of 74 s in
Ferguson 2010 is *slower* than muscle `τ_PCr`, because it includes circulatory processes — see the
component-mismatch discussion in §4.1a.)

The `g_pmax = 0.5·P_p_max` ratio is not arbitrary: peak glycolytic ATP flux is roughly half peak
PCr/creatine-kinase flux in human muscle (di Prampero & Ferretti 1999; the biopsy time-courses of
Parolin 1999 / Bogdanis 1996), so PCr is the higher-power system by about 2:1. **But `g_rate` is now a
load-bearing parameter, not an aside:** the ablation in §6.9 shows it (via the glycolytic flux ceiling)
is what generates the training-load separation, and sweeping it 0.3→0.7 moves that headline separation
from ~48 to ~33 pts. It is flagged alongside `f_p` and given a band (~0.3–0.7), and it should be
sanity-checked against sprint biopsy data (§6.10), which it has never been fit to.

Several of these deserve flags up front, because the defaults are doing real work:

- **`f_p` is assumed on physiological grounds, but now *corroborated* by the recovery data (§4.1a).**
  We set **0.25** from physiological alactic-fraction estimates (the PCr system supplies ~20–30% of
  anaerobic ATP capacity; di Prampero & Ferretti 1999, Bangsbo 1990), and — once the reconstitution
  reference protocol's recovery power is known (20 W, near-passive) — the reconstitution curve
  independently implies `f_p ≈ 0.20–0.25`, converging with the physiology. Treat it as a per-athlete
  calibration target; the supported band is ~0.20–0.25 (a joint reconstitution fit centres on 0.20).
- **`P_p_max ≈ P₁ₛ − CP` is the rate at a FULL tank.** PCr flux is not constant: the rate *ceiling*
  tapers with tank fullness (creatine-kinase equilibrium — flux falls as PCr depletes), so the
  available PCr rate is `P_p_max·(R_p/C_p)`, equal to `P_p_max` only when the tank is full (§4.2). Read
  `P₁ₛ − CP` as an upper bound: at 1 s glycolysis is already ~15% active, so it mildly over-attributes
  to PCr. Note this taper is on the *ceiling* only — it does **not** set the submaximal share (§4.2).

#### 4.1a Reconstitution: the source, the calibration, and a contradiction the source raises

The 37% / 65% / 86% W′-recovery at 2 / 6 / 15 min (half-time 234 s) is **Ferguson et al. 2010**
(*J Appl Physiol*, DOI 10.1152/japplphysiol.91425.2008), reviewed by Chorley & Lamb 2020, who state it
was measured "when recovering at a **nominal 20 W**." Three things follow.

- **`τ_g` is calibrated to ~470 s, not confounded (but not exactly "passive").** The confound of review
  3 — the LT1 gate makes the effective constant `τ_g/gate`, so the fit depends on recovery power — is
  resolved by the 20 W figure. But 20 W is not quite `gate = 1`: with `LT1 ≈ 0.8·CP ≈ 200 W`,
  `gate = (200−20)/200 = 0.90`, so a model reproducing Ferguson needs `τ_g ≈ 470 s` (± a few % on the
  cohort's unreported LT1), **not 520**. The default is corrected to **470**.
- **`f_p` is *consistent with* the curve, not independently corroborated by it.** With recovery power
  fixed, the curve still constrains a **ridge in `(f_p, τ_g)`**, not `f_p` alone: `(f_p 0.25, τ_g 520)`
  and the true joint optimum **`(f_p 0.20, τ_g 470)` (SSE ≈ 10.7 pts²)** both fit 37/65/86 to within
  ~3–5 pts. So the honest statement is *one* physiological estimate of `f_p` (di Prampero & Ferretti
  1999, alactic O₂-debt t½ ≈ 30 s; Bangsbo 1990, ~20% alactic) **plus a reconstitution curve consistent
  with it** — the physiology is what selects `f_p ≈ 0.25` on the ridge. We keep `f_p = 0.25` as the
  physiological midpoint but note the recovery data alone would prefer ~0.20. *(An earlier draft called
  this "two independent lines converge"; that overstated the independence — corrected here.)*
- **Ferguson's own components look ~4× off from the model's — but the offset is *forced by the data*, and
  once you see why, it exonerates the τ's and convicts the *naming*.** This is the most important thing in
  the paper, and v0.7 reads it correctly (Reviewer 2, third report, was right and v0.6 was wrong). Ferguson
  reports the two recovery channels underlying W′ reconstitution: VO₂ t½ = 74 s (a proxy for oxidative/PCr
  resynthesis) and blood-lactate t½ = 1366 s. Put those beside the model's component half-times:

  | Component | Model | Ferguson channel | ratio |
  |---|---|---|---|
  | fast | `τ_p = 27 s` → t½ **18.7 s** | VO₂ **74 s** | 4.0× |
  | slow | `τ_g = 470 s` → t½ **326 s** | lactate **1366 s** | 4.2× |
  | **ratio (slow/fast)** | **17.4×** | **18.5×** | within 6% |

  Two facts. **(1) The *shape* is right; only the *scale* is off, by the same factor in both channels.** The
  model reproduces the 18-fold fast/slow separation almost exactly — that is not what fitting-two-
  exponentials-to-a-sum looks like (that lands one component anywhere and lets the other absorb the
  residual). **(2) The offset is unavoidable, because W′ recovers ~4× faster than its own metabolites.**
  Build the two-compartment model out of Ferguson's *measured* channel constants (107 s, 1971 s) and it
  cannot reproduce Ferguson's *own* recovery curve:

  | | 2 min | 6 min | 15 min |
  |---|---|---|---|
  | **Observed** (Ferguson 2010) | 37% | 65% | 86% |
  | Model (`τ_p 27`, `τ_g 470`) | 40% | 63% | 87% |
  | **Built from Ferguson's channels** (107 s, 1971 s) | **20%** | **35%** | **50%** |

  A model calibrated to the *metabolites* predicts half the recovery that is actually observed. So the τ's
  are **not** a fitting error — they are the constants that reproduce W′ recovery, which is the quantity the
  model tracks and displays, and W′ recovery is simply ~4× faster than the PCr/lactate it correlates with.
  This is Ferguson's own conclusion — W′ reconstitution is "**not a unique function of phosphocreatine
  concentration or arterial [lactate]… unlikely to simply reflect a finite energy store**" — now with a
  number attached. **What fails is the metabolic *naming*, not the time constants.** The tanks are
  compartments of W′ (right internal ratio, ~4×-fast absolute scale); the "PCr"/"glycolytic" labels are
  motivation. Note the symmetry v0.6 missed: *blood* lactate t½ is no more a measure of *muscle* H⁺/Pi
  clearance than VO₂ off-kinetics is a measure of PCr resynthesis — so **neither Ferguson channel measures
  a tank, and Ferguson therefore cannot adjudicate the decomposition either way**, which is exactly
  Ferguson's point and ours. The rename in §4.1 (fast/slow reserve) is the resolution.

- **§6.9's training-load claim does not inherit this problem, and here is why (Reviewer 2's collision, and
  its resolution).** A careful reader will worry that §4.1a undercuts §6.9: if the "PCr tank" is not PCr,
  does "76% fast-reserve" still license "cheap to recover from" (§1)? The answer is that §4.1a is entirely
  about the **recovery law** (`τ_p`, `τ_g`), while §6.9's signal is entirely about the **depletion law** —
  which is anchored in *measured* metabolic kinetics: `τ_on` from Parolin's phosphorylase activation (a
  direct biopsy measurement) and `g_rate` from di Prampero's flux ratio. Those are not fitted to W′.
  Concretely, re-running §6.9 with `τ_p` set to **107 s** (Ferguson's own VO₂ channel — the value that
  supposedly indicts the model) moves the alactic/glycolytic separation by <1 pt (77.1%→75%). The
  separation never collapses across any assumption it rests on (§6.9). So the depletion-side partition can
  be metabolically meaningful even though the recovery-law naming is not — the training-load argument is
  best stated in terms of *measured activation kinetics*, not tanks.

### 4.2 The 1 Hz update

Let `P` be instantaneous power (W) and `Δt = 1 s`. Define the demand relative to aerobic supply
as `Δ = P − CP`.

**Case 1 — depletion (`Δ > 0`, above CP).** Demand `need = Δ·Δt` (J) is met by **both systems in
parallel**. This matters: glycolytic ATP supply is not instantaneous. Glycogen phosphorylase (the
rate-limiting glycolytic enzyme) transforms to its active form over the first several seconds of
maximal effort — Parolin *et al.* (1999) measured it rising from 12% at rest to 47% by 6 s — while
phosphocreatine is the immediate buffer (a fresh 30 s sprint drains muscle PCr to ~17%, Bogdanis *et al.*
1996; fresh 10 s and 20 s maximal sprints leave substantially more, Bogdanis *et al.* **1998**); both
contribute from the onset, not in sequence (González‑Alonso *et al.* 2000). *(The model's own ~20–30%
residual after a 10 s sprint is a separate quantity — a fast-reserve-of-W′ level, §4.4 — not muscle PCr;
v0.6 mis-cited Bogdanis 1996's fatigued sprint-2 datum for a fresh 10 s sprint. Corrected, and Bogdanis
1998, which reports fresh 10/20 s conditions, is added.)* We model this
with a **glycolytic activation** term `g ∈ [0,1]` that ramps first-order with a time constant
`τ_on ≈ 6 s` while above CP and relaxes back during recovery:

```
g ← g + (1 − g)·(1 − exp(−Δt/τ_on))       # glycolytic activation ("inertia")

# --- SHARE of submaximal demand: capacity-proportional (NOT rate-proportional) ---
w_p = C_p                                  # at g=0 → PCr covers all; at g=1 → PCr covers f_p
w_g = C_g · g
share_p = need · w_p / (w_p + w_g)         # (guard: if w_p+w_g ≈ 0, share_p = need)
share_g = need − share_p

# --- RATE CEILING: peak flux, PCr tapered with fullness. Governs MAXIMAL efforts only. ---
rate_p = P_p_max · (R_p / C_p)             # (guard: C_p > 0)
rate_g = g_rate · P_p_max · g

take_p = min(share_p, R_p, rate_p·Δt)      # each tank capacity- AND rate-limited
take_g = min(share_g, R_g, rate_g·Δt)
unmet  = need − take_p − take_g
# shortfall (a tank empty or rate-capped) spills to the partner, then to a deficit:
take_g += min(unmet, R_g − take_g, rate_g·Δt − take_g);   unmet −= …
take_p += min(unmet, R_p − take_p, rate_p·Δt − take_p);   unmet −= …
R_p −= take_p;  R_g −= take_g
D  += unmet                                # DEFICIT (debt): supra-CP work the caps couldn't place

if unmet > 0:  rate_limited = true         # producing power beyond the tanks' flux — usually a stale P₁ₛ
```

**Why the share and the ceiling are different objects.** The rate ceiling — `P_p_max`, `g_pmax` — encodes "PCr is the higher-power system." That is true
at **maximal** effort, where both systems are flux-limited, and it is where PCr dominance belongs. It
is the **wrong** object for apportioning **submaximal** supra-CP demand, where neither system is near
its flux limit and the sharing is set by metabolic control, not peak-flux ratios. Earlier revisions
used one rate-weighted rule for both jobs, which forced the PCr trajectory to be a fixed, convex,
intensity-*invariant* function of W′-spent (PCr at ~9% by the midpoint of *any* hard effort). Weighting
the **share by capacity** and keeping the taper on the **ceiling** fixes it with no cost in the sprint
case (there the caps and spill dominate and the share rule never binds — verified bit-identical):

- **Submaximal:** both tanks drain ≈ proportionally to capacity, so `R_p/C_p ≈ R_g/C_g ≈ W′bal` and
  both reach their nadir *together* at exhaustion — matching the reproducible-metabolic-milieu picture
  in §2. Honestly, this means during a steady supra-CP effort the two bars track W′bal and each other;
  they diverge only in the activation ramp and in recovery. That is not a defect — it is the model
  behaving the way the Scope box and §7 already say it does (extra resolution lives in transients).
- **Maximal:** the tapered ceiling makes `R_p` decay ~geometrically to its nadir at exhaustion (a
  ~10 s all-out sprint leaves the fast reserve at ≈ 20–30%; §4.4), and fast-reserve dominance emerges from
  the ceiling, not the weight. *(We no longer claim this "matches Bogdanis 17%": since §4.1a establishes
  the fast reserve is not muscle PCr, we cannot invoke the muscle-PCr mapping to validate the residual and
  then disown it elsewhere — the residual is a model output, motivated by, not validated against, the
  biopsy value. Reviewer 3's "you can't have the mapping both ways" is correct and applied here.)*
- **Energy conserved even when a cap binds.** Residual `unmet` is banked in a **deficit `D`** (standard
  W′bal permits a negative balance), so `(R_p + R_g − D)` drops by exactly `Δ`·Δt per second and the §4.4
  conservation result holds. `D` clears only below LT1 (Case 2) — it is supra-cap byproduct load and must respect the same
  intensity gate as the glycolytic tank. Note the deficit preserves the *aggregate* but not the *split*:
  work booked to `D` never drains a tank, so if `D` is large the two bars read slightly full. `D` is an
  accounting term for the rare supra-flux case, usually signalling a **stale `P₁ₛ`**, not fatigue.

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
g ← g · exp(−Δt/τ_off)                            # glycolytic DE-activation (τ_off = τ_on default)

# FAST RESERVE: resynthesis needs aerobic ATP ABOVE the ride's own demand, so it is gated by the
# OXIDATIVE HEADROOM (CP − P): full at rest, near-arrested at CP. gate_p scales the AMOUNT recovered
# (not the exponent) — the pseudocode and both codebases agree on this (closes Reviewer 3 m2).
gate_p = max(0, (CP − P) / CP)
R_p += gate_p · (C_p − R_p) · (1 − exp(−Δt/τ_p))

# SLOW RESERVE and the deficit recover whenever P < CP, at Skiba's intensity-dependent W′bal rate
# τ_W′(D_CP) = 546·e^(−0.01·(CP−P)) + 316, its amplitude re-anchored so the 20 W passive rate reproduces
# Ferguson 2010 (as v0.6's linear gate did at that one point). NEW in v0.7 — replaces the linear
# (LT1−P)/LT1 gate, whose rate went to zero at LT1 (recovery → ∞), which made the model unable to
# complete a standard 4×4 (§4.4). Skiba's form is bounded and was fitted ACROSS recovery powers.
if P < CP:
    f   = gate20 · τ_W′(CP − 20) / τ_W′(CP − P)   # =gate20 at 20 W (Ferguson anchor), <1 above
    b   = f · (1 − exp(−Δt/τ_g))
    R_g += (C_g − R_g) · b
    D   -= D · b
```

**The v0.7 recovery fix — the linear LT1 gate is gone.** v0.6's glycolytic/deficit recovery used a linear
gate `(LT1−P)/LT1` that fell to zero *at* LT1, so the effective recovery constant diverged to infinity as
the recovery power approached LT1. Re-implementing the pseudocode and holding a rider at constant recovery
powers (Reviewer 3, M2) showed the cost: W′bal half-times of 675 s at 150 W and 2601 s at 190 W (vs
Skiba's 351 s and 417 s), and — decisively — **the model could not get a rider through 4 × [4 min @ 330 W
/ 4 min @ 150 W]**, driving W′bal to 100/38/−23/−76% and leaving the rider 76% into deficit from rep 3
onward. Riders complete that session every week. The fix is Reviewer 3's own suggestion: use Skiba's
`τ_W′(D_CP)` — a functional prior *already fitted across recovery powers* — for the shape, and re-anchor
its amplitude so the 20 W passive rate still reproduces Ferguson (the one curve the model is calibrated
to). Result (verified): W′bal half-times are now **201 / 241 / 291 / 367 s** at 20 / 100 / 150 / 190 W —
bounded, monotone, and within ~15% of Skiba everywhere — the Ferguson curve is unchanged (40/63/87), the
§4.4 sprint battery is bit-identical, and the **4×4 now completes: 100/49/7/−24%** (dips negative only
going into the final rep, consistent with a genuinely hard but finishable VO₂max session).

**The oxidative-headroom gate `gate_p` (v0.5) — a good fix, and now flagged as the assumption it is.**
`gate_p = (CP − P)/CP` stops the fast-reserve bar refilling while the rider is under load (before it, the
bar went green holding 99% of CP). It is correct in instinct and fixes a real bug. But (a) its **shape is a
choice**: linear-in-CP is one option; a √ or sigmoid form is equally defensible and swings the headline
60-s recovery number by **21–31 points** at LT1 (linear 46% / √ 65% / sigmoid 34% after a 700 W/20 s
effort) — so it is now in the §7 assumptions list with that sensitivity reported. And (b) it only fixes
*half* the scenario it was built for: the gate scales the *refill*, it adds no sub-CP *drain*. A rider who
sits at 0.95·CP in a bunch for 30 minutes — never above CP — keeps a **100%** fast-reserve bar the whole
time, because `Δ ≤ 0` and the depletion branch never fires. The structurally correct fix is to relax `R_p`
toward an intensity-dependent steady state `R_p*(P)` rather than toward `C_p`; until then this is a stated
blind spot, not a solved case (Reviewer 3, M7b). Verified after a 20 s / 700 W effort (fast reserve → 23%),
60 s recovery restores it to **87% at 0 W, 46% at 0.8·CP, 25% at 0.99·CP** — vs a flat 92% before the gate.

The `g` de-activation is what makes the activation ramp re-fire on each interval of a repeated-bout
set (without it, `g` would ratchet to 1 on the first surge and every later bout would start at a flat
split — the ramp inert for the rest of the ride). **`τ_off = τ_on` is an assumption, and a
load-bearing one:** Parolin (1999) measured phosphorylase *activation*, not *de*-activation, which is a
separate quantity. If de-activation runs on a minutes timescale rather than seconds, the ramp would not
re-fire on 30 s recoveries and the repeated-sprint behaviour changes materially — so `τ_off` is flagged
alongside `f_p`, `τ_g` (§7).

`LT1` still matters, but its role narrowed in v0.7: it sets the **anchor band** of the Skiba recovery
shape (via `gate20`), not a hard on/off wall. Recovery now proceeds for any `P < CP`, fastest at low
intensity and slowing smoothly through the tempo band — which is more physiological than the old abrupt
cutoff and is what fixes the 4×4. `LT1` is the rider's **first lactate threshold in watts**, from a
threshold test; LT1 and CP vary independently (LT1 ≈ 65–85% of CP). Where only CP is known, `LT1 ≈
0.80·CP` is a fallback, still the weakest default in the model and worth replacing with a measurement.

**Optional realism terms (each can be disabled by zeroing its coefficient).** Two of the three ship **on**
by default and are therefore included in every headline number in this paper: the pH-slowed PCr recovery
(`fatK = 0.75`) and the aerobic ramp (`τ_aer = 25 s`). The glycolytic flux-fatigue term (`g_fat`) ships
**off** (`g_fat = 0`). (An earlier draft mis-stated that all three ship off; the shipped defaults and the
numbers below use `fatK` and the aerobic ramp on, `g_fat` off.)
- *pH-slowed / fatiguing PCr recovery* (`fatK`, **on by default**): scale `τ_p` upward as the slow reserve is emptier,
  `τ_p_eff = τ_p · (1 + k·(1 − R_g/C_g))`. Note it **cannot** be pushed to reproduce Bogdanis's muscle-PCr
  recovery (78.7% at 3.8 min) without breaking the Ferguson W′ curve and the 4×4 — the `k ≈ 16` that hits
  Bogdanis drops Ferguson to 30/68/94 and the 4×4 back to −30% — which is §4.1a's point restated: W′ and
  muscle PCr do not share a time constant.
- *Aerobic ramp* (`τ_aer ≈ 25 s`, **on by default**): a first-order aerobic supply `A(t)` rising toward
  `min(P, CP)`, with `need = (P − A)·Δt`, reproducing the onset O₂ deficit. It is also what absorbs the
  shortfall across repeated sprints (§6.10).
- *Glycolytic flux fatigue* (`g_fat`, **new in v0.7**): scale the glycolytic ceiling down as the slow
  reserve empties, `rate_g_eff = rate_g · (R_g/C_g)^{g_fat}`, capturing acidotic inhibition of
  phosphorylase/PFK. Off (0) by default. It moves the repeated-sprint partition from *rising* toward
  *flat/falling* — the biopsy direction — but does not reproduce the 40%→<10% magnitude (§6.10).

### 4.3 Reported quantities

- **PCr reserve** `= R_p / C_p` (0–100%) — how much "punch" is left.
- **Glycolytic reserve** `= R_g / C_g` (0–100%) — how much "sustained dig" is left.
- **Consumption rate** (per system, W) — `take_p/Δt`, `take_g/Δt`, the live draw on each tank.
- **Combined W′bal** `= (R_p + R_g − D)/W′` — the deficit term keeps this **energy-conserving in
  depletion** (it drops by exactly `Δ`·Δt per second) so it matches a single-tank W′bal reference on
  above-CP segments. It intentionally **diverges in recovery** (bi-exponential + LT1 gate; §4.4),
  so it is *depletion-compatible*, not identical everywhere.
- **Two distinct flags** (the split the code has always made, now stated in the paper — closes the
  round-4/round-5 open item):
  - `rate_limited` — the rider is producing power beyond the tanks' *flux* caps (`unmet > 0`, `D`
    growing) while the reserves are **not** empty. Usually signals a stale `P₁ₛ`, not a spent rider; the
    field surfaces a "recalibrate sprint power" hint.
  - `exhausted` — both reserves are at/near zero (`R_p + R_g ≈ 0`). This drives the red state.
  These are different conditions (a fresh rider with a mis-set `P₁ₛ` can be `rate_limited` but not
  `exhausted`); v0.6's §4.3 wrongly unioned them under one label.

### 4.4 Why this behaves correctly

- A short, very hard surge draws mostly from `R_p` (glycolysis has not yet ramped in), and `R_p`
  refills after — *at a rate set by recovery intensity* (§4.2 gate). A maximal ~10 s sprint leaves
  **`R_p ≈ 20–30%`, not empty**, from the tapered ceiling's emergent depletion constant
  `τ_dep = C_p/P_p_max`. **But `τ_dep` is not a fixed 7 s** — §7 notes it swings ~4–13 s across riders,
  so the 10 s residual ranges from ~10% (fast riders) to **~46%** (`τ_dep ≈ 13 s`). This is a
  fast-reserve-of-W′ level, *motivated by* the biopsy picture (Bogdanis 1996: muscle PCr ≈ 17% at 30 s)
  but not *validated against* it (§4.1a: the fast reserve is not muscle PCr); the wide across-rider spread
  is an argument for a *measured* depletion constant (the re-architect fork, §7), not an emergent ratio.
- A sustained supra-CP effort draws from **both** tanks, declining together to their nadir at
  exhaustion. The drawdown is **front-loaded (mildly concave), not linear** — the activation ramp makes
  the early draw PCr-weighted (450 W: 68/42/18/1 at quarter-TTE intervals). During such steady efforts
  **both bars are affine in W′bal** (§4.2), so they carry no information single-tank W′bal lacks *there*;
  their only non-redundant content is the ramp offset (set by `τ_on`/`τ_off`) and the post-effort PCr
  recovery transient. This is stated as a limitation, not a feature.
- **A falsification test (not a validation), and its real cost.** For a constant supra-CP effort,
  `R_p/C_p` is *asymptotically* a function of the fraction `φ` of W′ spent — but only for efforts long
  relative to `τ_on` and below the ceiling regime; the activation ramp adds a genuine second intensity
  dependence (a hard effort reaches a given `φ` faster, with `g` lower, so PCr is *lower* at that `φ`).
  So the test "hold different supra-CP powers to exhaustion and compare PCr-at-%W′-spent" would report
  intensity-*dependence* for a correct model, and a naive read would wrongly "falsify" it. Framed
  correctly it is a **falsification** test (pass ⇒ the bar is a deterministic restatement of W′bal in
  depletion, i.e. redundant; fail ⇒ the architecture is wrong) — lose–lose for the *depletion* claim,
  which is the point. And it is **not** "testable in an afternoon": checking PCr in-cycling needs
  31P-MRS, which §6.5 says is unavailable in this modality. It requires a surrogate (post-exercise
  sampling, or knee-extension 31P-MRS with a cross-modality transfer assumption; §8).
- **Synthetic battery.** Parameters: `CP = 255 W`, `W′ = 20 kJ`, `f_p = 0.25`, `P_p_max = 690 W`
  (`g_rate = 0.5`), `τ_p = 27`, `τ_g = 470`, `τ_on = τ_off = 6`, `LT1 = 204 W`, and the shipped optional
  terms `fatK = 0.75` and `τ_aer = 25 s` on, `g_fat = 0` off.

  | Test | Result |
  |---|---|
  | Sustained 450 W — PCr at 25/50/75/100% of TTE | 68 / 42 / 18 / ~1% (front-loaded, nadir at exhaustion) |
  | Both tanks at exhaustion | PCr ~1% / GLY ~0% (empty together) |
  | 945 W (= P₁ₛ) 10 s sprint — PCr residual | 23% (ceiling-dominated; share rule doesn't bind) |
  | 6×[10 s@700 W / 30 s@150 W] — PCr at each bout end | 49→17→10→8→8→7% (gated recovery: 150 W is high sub-CP, so little refill) |
  | 1200 W hold (caps bind) — combined W′bal conservation | leak = 0 J |
  | Fast-reserve recovery after 700 W/20 s, 60 s @ {0, 128, 204, 242, 252} W | 87 / 68 / 46 / 30 / 25% (headroom gate) |
  | Debt repayment at 0.9·CP | `D` clears slowly (Skiba rate at that power), not frozen |

- **Recovery-power behaviour (v0.7 fix, verified).** W′bal half-time after full depletion, holding a
  constant recovery power — the linear LT1 gate (v0.6) vs the Skiba-shaped gate (v0.7) vs Skiba's own
  `τ_W′`:

  | Recovery power | v0.6 linear gate | **v0.7 Skiba-shaped** | Skiba `τ_W′` |
  |---|---|---|---|
  | 20 W (Ferguson anchor) | 201 s | **201 s** | 255 s |
  | 100 W (39% CP) | 353 s | **241 s** | 299 s |
  | 150 W (59% CP) | 675 s | **291 s** | 351 s |
  | 190 W (75% CP) | 2601 s | **367 s** | 417 s |
  | 204 W (LT1) | ∞ | **409 s** | 446 s |

  The v0.6 column diverges 2–7× from Skiba above 100 W and hits ∞ at LT1; v0.7 tracks Skiba within ~15%
  everywhere and is bounded. Consequently the **4 × [4 min @ 330 W / 4 min @ 150 W]** session, which v0.6
  could not complete (W′bal 100/38/−23/−76%), now reads **100/49/7/−24%** — finishable, as it is in life.

- **On "generalizing W′bal" — a careful claim.** In *depletion* the model is a faithful generalization:
  `(R_p + R_g − D)` falls by exactly `Δ`·Δt per second (cap-binding or not), so the summed draw above CP
  matches standard W′bal. In *recovery* it is deliberately **different** (bi-exponential, LT1-gated), so
  it does not reduce to Skiba's single `τ_W′`. It is a generalization in **structure and depletion
  behaviour**, not a strict superset. (We drop the earlier `f_p → 0` argument: with the fullness taper
  `C_p = f_p·W′ = 0` is a division by zero, guarded in code — the limit is not meaningfully computable
  and does not add anything.)

---

## 5. Real-time on-device implementation (Garmin Connect IQ)

The model's per-second cost is a handful of multiplies and one `exp()` per tank — trivial for a
head unit. A companion document, `connectiq-app-spec-and-prompt.md`, gives the full technical
specification and a ready-to-use build prompt. Summary of the target design:

- **App type:** a custom full-screen **Data Field** (`Toybox.WatchUi.DataField`), which the head
  unit calls once per second — a natural fit for the `Δt = 1 s` update.
- **Input:** `Activity.Info.currentPower` inside `compute(info)`.
- **Configuration:** `CP`, `W′`, `f_p`, **`P_p_max`** (a per-athlete calibration target — §6.7),
  **`LT1`** (a measured threshold, not a %CP default — §4.2), and the recovery constants exposed via
  Connect IQ app settings (`Application.Properties`), so a rider enters them from Garmin Connect.
- **Display:** two vertical bar gauges (PCr and glycolytic reserve) with numeric % and color bands
  (green → amber → red). *Per-system live consumption in W is a "modelled share," not a reading* — when
  the ceiling is slack it is just `(power − CP)` split by a fixed fraction (§7), so it is labelled as
  such or omitted.
- **Recording:** write both reserves and consumption to the FIT file via `FitContributor` fields
  so they sync to Garmin Connect / intervals.icu / Strava for post-ride analysis.
- **Footprint:** a handful of scalar state variables (`R_p`, `R_g`, the activation `g`, the deficit
  `D`), no arrays — well within Connect IQ memory budgets. Per-second cost is still a few multiplies
  and one `exp()` per tank.

---

## 6. Validation strategy

The model is a hypothesis; it must be checked against data before its numbers are trusted. The
honest difficulty is that the model's *headline feature* — a separate PCr reserve tracked in real
cycling — is the hardest thing to validate, so we separate tests that only check the plumbing from
the one test that would actually earn the second tank.

1. **Face validity / unit tests** — synthetic power traces (single sprint, repeated sprints,
   supra-CP hold, sub-CP recovery) should produce the qualitative behaviours in §4.4.
2. **Backward compatibility — *depletion only*.** The combined balance `(R_p + R_g − D)` reproduces a
   reference W′bal implementation (Froncioni–Clarke) on the same trace **in depletion** — it drops by
   exactly `Δ`·Δt per second, and the deficit term `D` preserves that even when a rate cap binds. It
   will **not** match in recovery, by construction (§4.4), so this test must be scoped to above-CP
   segments — a test that expected agreement everywhere is one the model is designed to fail.
3. **Reconstitution targets — what the curve constrains, and what it cannot.** Combined recovery after
   a full W′ depletion is compared to the published curve (37 / 65 / 86% at 2 / 6 / 15 min; Ferguson
   et al. 2010, at 20 W recovery). (a) **The curve is blind to the fast tank** — a `τ_p ≈ 27 s` process
   is `1 − e^(−120/27) ≈ 99%` complete by the first (2 min) sample, so it validates *glycolytic*
   recovery and the *size* of the PCr offset, **not** PCr kinetics (for those you need 10/20/30/45/60 s
   samples; test 4). (b) **The curve fixes `τ_g` and constrains a `(f_p, τ_g)` ridge, not `f_p` alone.**
   With the 20 W recovery power known (gate ≈ 0.90), the fit gives `τ_g ≈ 470` and the joint optimum
   `(f_p 0.20, τ_g 470)`; `f_p` is *selected on that ridge by physiology*, not by the curve (§4.1a). So
   the curve is **consistent with** `f_p ≈ 0.20–0.25`, not an independent measurement of it. *(This
   supersedes a v0.3 statement — since deleted — that computed an implied `f_p ≈ 0.13` at the old
   `τ_g = 360 s`; that value was a fossil of the superseded default.)*
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
6. **The test that earns the second tank — and what it actually tests.** Because the model is a
   near-superset of single-tank in depletion, "it fits better" is guaranteed and is **not** evidence the
   compartments are real. The decisive test is a **head-to-head against single-tank W′bal on an
   out-of-sample intermittent-tolerance prediction** (the protocol class where the hydraulic model beat
   W′bal, arXiv 2108.04510). But be precise about what it probes: since this model's *depletion* is
   single-tank by construction, its **only** lever to beat single-tank is the **recovery law**
   (bi-exponential + LT1 gate). So **test 6 is a test of the recovery law, not of the two-compartment
   hypothesis** — the framing "two tanks → better prediction" overstates what a win would show. This
   also sharpens the protocol: choose interval recovery-valley powers that **straddle LT1**, where the
   dual-tank and single-tank recovery laws diverge most, rather than a generic interval set.
7. **Field calibration — scoped honestly.** Fit **`P_p_max` and the `τ`'s** per athlete to maximal and
   repeated-bout tests. **`f_p` is *not* a routine calibration target:** §4.2 shows the depletion split
   is unidentifiable from power, and only the test-4 class (all-out efforts with early recovery
   sampling) can constrain it — and even then the fit is ill-conditioned. Also: any single-tank W′bal
   comparator in test 6 must have **its own `τ_W′` fit to the same data**, or the dual-tank wins
   trivially by having more recovery freedom and the win means nothing.

### 6.8 First empirical results (v0.5) — usefulness, on real rides

Three reviews converged on the point that the paper validated *plausibility* but never the two cheap,
data-in-hand questions that decide whether the feature is worth building. Both were run on six real
interval/VO₂max sessions — the best case for **informativeness** (the bar is most *live* when the ride
repeatedly loads and unloads W′; a steady endurance ride would score far lower). **This is a claim about
information content, not accuracy**, and the two are not the same regime: on **sub-minute-recovery
intermittent work** (e.g. 30/15 s micro-intervals) the model is *outside its validated domain* — the hard
CP supply cap over-attributes supra-CP work to the anaerobic tanks and over-drains them (§7; issue #86),
so a live/diverging bar there is *informative-but-wrong*. The results below (informativeness, R² ≈ 0.03)
stand; they must not be read as accuracy on the short-recovery subset.

- **How often is the fast-reserve bar informative, and is it a function of W′bal?** Two tests. (a) The bar
  is below 95% (i.e. live) for a per-ride **20 / 31 / 38 / 52 / 61 / 79%** of ride time — median ~45%, range
  20–79% (reported per-ride, not as a bare mean, per Reviewer 2 §8). (b) The stronger test, which a
  reviewer set and the bar passed: is the bar just an affine transform of W′bal? Binning W′bal and measuring
  the spread of `R_p/C_p` within each 1-point bin gives a **mean spread of ~58 pts (max ~93)**, and regressing
  the bar on its best affine W′bal predictor gives **R² ≈ 0.03** — the bar sits >5 pts off that affine line
  **~93%** of the time. So the fast-reserve bar is emphatically **not** a function of W′bal; the ~45% figure
  is, if anything, conservative.
- **Does the depletion machinery change the display, vs the recovery-only null?** Running the full model and
  the null (§7) on the same traces, the fast-reserve bar **diverges** by up to ~25–60 pts, maxima at the
  starts of recovery valleys. **Important caveat, now carried up from §7: divergence is *not* accuracy.** Two
  models differing by 25–60 pts tells us the caps *change* the display, not that the changed display is
  *right* — a random process would diverge too. Whether the extra resolution is *correct* is §6.6 and now
  §6.10 (which suggests some of it is not). §6.8 establishes the bar carries *information*, full stop.

Neither result validates the *compartments* (that is §6.6 and §6.10). They answer a narrower, real
question — *is the two-bar display worth showing, and does the model's complexity change what it shows* —
with data instead of assertion; the answers are yes and yes, for interval training, with correctness still
open.

### 6.9 Training-load partitioning — a use case the reviews evaluated past

Every review assessed the model as a **pacing** aid and correctly found the live bars affine with W′bal
outside transients. But there is a second use case they did not weigh, and it is where the decomposition
is most clearly worth more than W′bal: **training prescription and load monitoring.** The relevant output
here is not the live bar but the **cumulative per-system load over a session** — how many kJ came from the
alactic (PCr) vs the glycolytic system — which the field already records (`PCr_depleted_kJ`,
`GLY_depleted_kJ`). This matters because the two systems carry asymmetric recovery costs (§1): alactic
work is cheap and repeatable; glycolytic work is expensive and self-limiting. A coach building a
PCr-targeted block (alactic power, repeat-sprint ability) wants sessions that stay alactic; one building
lactate tolerance wants the opposite. **W′bal cannot tell these apart — it is one number.**

The model does discriminate session types, but v0.6 credited the wrong mechanism and overstated the
baseline it beats. Both are corrected here. Sessions are now **fully specified** (Reviewer 2 §8): the
alactic archetype is 10 × [6 s @ 900 W / 300 s recovery @ 150 W]; the glycolytic archetype is
5 × [60 s @ 360 W / 120 s recovery @ 150 W]. Per-system load (default parameters, `g_fat` off), now
reporting the **deficit `D` as a third number** (work booked to neither tank; Reviewer 3 M4):

| Session | fast-reserve kJ | slow-reserve kJ | **`D` kJ** | **fast-reserve % of (fast+slow)** |
|---|---|---|---|---|
| 10 × [6 s @ 900 W] — alactic | 29.2 | 8.7 | 1.2 | **77%** |
| 5 × [60 s @ 360 W] — glycolytic | 13.2 | 21.5 | 1.8 | **38%** |

The separation is real (~39 pts). But three v0.6 claims about it were wrong:

**(a) The mechanism is the glycolytic flux ceiling scaled by the ramp — not the ramp alone.** Ablating the
model one part at a time on the alactic session:

| Configuration | alactic fast-reserve % | separation vs glycolytic |
|---|---|---|
| full model | **77%** | ~39 pts |
| no activation ramp (`g ≡ 1`) | 52% | ~15 pts |
| no rate ceilings (share rule only) | 47% | ~9 pts |
| neither | 25% | −12 pts |

Removing the ceilings costs ~30 pts; removing the ramp ~25 pts; neither alone reaches the full 77%. It is
an **interaction**: during a 6 s sprint the glycolytic ceiling (`g_rate·P_p_max·g`) caps glycolysis at a
few tens of watts while demand is ~645 W, and the spill sends the difference to the fast reserve. So the
load-bearing parameter is **`g_rate`** (via the ceiling), not `τ_on`/`τ_off`. v0.6's "the discriminating
content is the activation ramp" and §7's "`τ_off` is the only parameter carrying the depletion novelty"
are both **withdrawn** — a 20× change in `τ_off` moves the split 1–2 pts, whereas `g_rate` 0.3→0.7 moves
the separation 48→33 pts.

**(b) The metric detects supra-flux-ceiling power, so it is blind to *submaximal* alactic work.** Hold the
structure fixed (10 × 6 s, full recovery) and sweep the power: the reading climbs **52% → 62% → 66% → 72%
→ 77%** at 450 / 550 / 600 / 700 / 900 W. A textbook alactic session done at 450 W — short efforts, full
recoveries, exactly what a neuromuscular block prescribes — reads **~52%**, close to the glycolytic
session's 38%. The metric is really answering "did you exceed the glycolytic flux ceiling," not "was this
alactic." A coach needs to know this; it is a genuine scope limit, not a footnote.

**(c) The honest baseline is not W′bal — it is a stopwatch.** "W′bal cannot tell these apart — it is one
number" is false: W′bal is a *time series*, and a coach with the power file and no model can compute the
fraction of supra-CP work done in efforts under 15 s — **100% vs 0%** for these two sessions, perfect
separation, zero parameters (Reviewer 3 M3). So §6.9's real question is not "does the model separate these"
(of course it does) but "**does the per-system load carry information beyond effort duration and
intensity?**" That is an open, testable question (regress fast-reserve % on a duration/intensity baseline
across real rides; if R² > 0.9 the metric is an expensive stopwatch), and the paper should not claim the
win until it is answered.

What *does* survive: (i) the separation is robust to every assumption it rests on — including setting `τ_p`
to Ferguson's 107 s (§4.1a), which moves it <1 pt, so §4.1a does not reach it; (ii) it is a genuinely
different functional of the power trace than W′bal. Honest limits: absolute kJ scale with `f_p`; `D` must
be reported (and the split refused when `D` is a large fraction of total — e.g. a 4×4 books ~45% of its
anaerobic work to `D`, so a per-system split there is meaningless); and this is a training-*design* signal,
not a validated *outcome*.

### 6.10 Repeated-sprint ATP partitioning — an in-modality, compartment-level test the model *fails*

v0.6 declared (§7) that the compartments are "unfalsifiable in-modality — permanently." That is
**withdrawn.** The claim rested on two true premises (the split is unidentifiable from power; 31P-MRS
cannot run during cycling) and one false inference — that 31P-MRS is the *only* compartment-level
measurement. **Muscle biopsy during cycle ergometry is another**, and Gaitanos 1993, Parolin 1999, and
*Sci Rep* 2024 — all already cited — partition ATP supply by system from vastus-lateralis biopsies during
maximal cycle-ergometer sprints. That is compartment-level data, in the target modality, on the target
ergometer, for the exact protocol class the model describes. It needs no new data collection.

So we ran it. The model's own §6.9 alactic protocol (10 × 6 s maximal sprints) is exactly Gaitanos's, and
the biopsy literature reports the glycolytic ATP share **falling from ≈40% in the first sprint to <10% in
the last**, with aerobic metabolism rising to cover the shortfall. The model, as shipped:

| | Sprint 1 | → | Sprint 10 |
|---|---|---|---|
| **Observed** (Gaitanos 1993 / *Sci Rep* 2024), glycolytic share of anaerobic ATP | **~40%** | ↘ | **<10%** |
| Model, shipped (`g_fat` = 0) | 23% | **↗** | 46% |
| Model, optional `g_fat` = 1 + aerobic ramp | 23% | → | ~34% (flat, then falling) |

**Wrong level and wrong direction.** The model starts glycolysis at about half the observed share and has
it *rise* across bouts, because it has the two fatigue mechanisms backwards: the fast-reserve ceiling
(`rate_p = P_p_max·R_p/C_p`) fades as the reserve empties, so more demand spills to glycolysis bout over
bout, while glycolytic flux has *no* fatigue term at all. The optional `g_fat` term (§4.2) plus the aerobic
ramp flatten the trend and pull the late bouts down, but they do **not** reproduce 40%→<10% — the starting
level is set by `g_rate` and the activation ramp, and reaching 40% in sprint 1 would require a higher
`g_rate` that then wrecks the alactic/glycolytic separation of §6.9.

Two conclusions, and both are progress. **First, this is the first genuinely falsifiable result in the
project** — every prior round argued internal consistency, identifiability, and framing; this one has a
number that is wrong in a specific, fixable way, and it arrived because §6.9 finally asked a question with a
checkable answer. **Second, it settles what the tanks are:** as shipped, the depletion split is a
**W′-decomposition heuristic, not a validated bioenergetic ATP partition.** The `PCr_depleted_kJ` /
`GLY_depleted_kJ` fields should be read as a *descriptive statistic* of a power file (how front-loaded and
supra-ceiling the anaerobic work was), not as a biopsy-grade estimate of which metabolic system paid.
Whether the model can be made to reproduce 40%→<10% — by calibrating `g_rate` to the sprint-1 biopsy value
and fitting `g_fat` to the decay — is the single highest-value experiment left, it needs only data already
in the bibliography, and it is the one test in this document that could falsify (or earn) the two-compartment
hypothesis directly rather than by proxy. Until it is run, §6.9 stands as a descriptive metric, not a
bioenergetic one.

---

## 7. Assumptions and limitations

- **The PCr/glycolytic split `f_p` is assumed (physiology), and *consistent with* — not corroborated
  by — the recovery data.** Power cannot identify the depletion split (§4.2). We default to **0.25** from
  physiological alactic-fraction estimates (~0.20–0.30; di Prampero & Ferretti 1999, Bangsbo 1990 ~20%).
  The reconstitution curve constrains a `(f_p, τ_g)` ridge, not `f_p`, and physiology is what selects
  `f_p` on it (§4.1a) — so the two "lines" are not independent, and the recovery data alone would prefer
  ~0.20. Supported band ~0.20–0.25; a per-athlete target; outputs are sensitive to it.
- **The reserves are a decomposition of W′, not latent metabolic state.** The two bars are a
  physiologically-motivated split of one measured quantity (W′bal), not two independently measured
  reserves, and §4.1a shows they are compartments of W′ rather than of muscle metabolites. **Correcting a
  v0.6 under-claim:** the fast-reserve bar is *not* "full most of the time" while riding. Under the
  oxidative-headroom gate the effective recovery constant is `τ_p/gate_p` — **27 s only at a standstill**,
  rising to ~44 s at 100 W, ~66 s at 150 W, ~135 s at LT1, and 100s–500s across the sub-CP band a rider
  actually recovers in. So the bar stays live through interval recovery valleys (§6.8: 20–79% of ride
  time), and the "affine transform of W′bal" caveat applies to *stopped or easy* recovery, not to riding —
  which is more favourable to the display than v0.6 stated. When the fast reserve *is* full (rest), the
  glycolytic bar is an affine transform of W′bal (`W′bal = f_p + (1−f_p)·R_g/C_g`); the honest product
  framing is "W′bal plus one new number," a heuristic decomposition whose split is assumed.
- **`gate_p` (the PCr oxidative-headroom gate) is an assumption with a consequential undefended shape.**
  It fixes a real bug (§4.2) but its functional form is a choice: linear-in-CP vs √ vs sigmoid swing the
  60-s post-effort recovery number by **21–31 points at LT1** (46 / 65 / 34%). It sets the headline
  display number and is flagged here alongside the LT1-band shape. It also adds no sub-CP *drain*, so it
  does not cover the sustained-sub-CP-in-a-bunch case (§4.2).
- **`g_rate = 0.5` is load-bearing, not an aside.** Via the glycolytic flux ceiling it generates §6.9's
  headline separation (ablation: removing the ceilings costs ~30 pts), and sweeping it 0.3→0.7 moves that
  separation ~48→33 pts. It has never been fit to the sprint biopsy data that would constrain it (§6.10).
  Flagged and banded (~0.3–0.7) alongside `f_p`.
- **The PCr *depletion* rate is also assumed — and it was invisible until v0.4.** The tapered ceiling
  gives an emergent depletion constant `τ_dep = C_p/P_p_max`, tied to *no* measured PCr depletion
  kinetic; it is the ratio of three parameters and swings ~3× across plausible riders (~4–13 s). §7 was
  scrupulous about the assumed *recovery* constants and silent about this equally load-bearing
  *depletion* one. It should be sanity-checked against literature PCr depletion half-times, not left to
  fall out of `f_p`, `W′`, and a 1 s sprint power.
- **`τ_g` is calibrated to ~470 (confound resolved); `τ_off` remains assumed but is *not* load-bearing.**
  Ferguson recovered at ~20 W (gate ≈ 0.90), so `τ_g ≈ 470` (§4.1a). `τ_off = τ_on` is still an assumption
  (Parolin measured activation, not de-activation; §4.2). **Retraction:** v0.6 (crediting Reviewer 2's
  round-2 claim) said `τ_off` "is the *only* parameter carrying the depletion-phase novelty." §6.9's
  ablation falsifies that — a 20× change in `τ_off` moves the per-system split 1–2 pts; the novelty is
  carried by the **glycolytic flux ceiling (`g_rate`) scaled by the ramp**, not by `τ_off`. Reviewer 2
  retracted the original claim in the third report; it is removed here.
- **`LT1` should be measured, not derived from CP.** The `0.80·CP` fallback will be wrong for many
  riders (LT1 ranges ~65–85% of CP), and it gates whether the glycolytic tank recovers during tempo, so
  a bad value materially changes recovery estimates.
- **Several small modeling choices are assumptions, flagged not defended.** The glycolytic recovery
  *shape* (v0.7 uses Skiba's `τ_W′(CP−P)`, amplitude-anchored to Ferguson at 20 W — a defensible prior
  fitted across recovery powers, but still a choice of functional form); lumping deficit clearance and
  slow-reserve refill onto the *same* `τ_g`; and the spill order (unmet demand spills to glycolytic before
  PCr). **The spill-order flag is downgraded:** Reviewer 2 tested it and reversing the order changes §6.9
  by 0 pts (the glycolytic rate is already exhausted, so there is nothing to spill), so it is inert on the
  sessions that matter here.
- **The deficit `D` corrupts the display at maximal effort, and its recurrence mechanism was mis-stated.**
  When `D` is large the two bars read slightly full. **Correction (Reviewer 3 m4):** v0.6 attributed the
  late-effort recurrence of `D` to `P₁ₛ` decaying intra-ride — which is backwards (a decaying sprint means
  the rider produces *less* against a *fixed* cap). The real mechanism is the **fullness taper**: `rate_p =
  P_p_max·(R_p/C_p)` collapses as the fast reserve empties, so the combined flux ceiling drops below what a
  deep-but-still-sprinting rider produces, and the residual books to `D`. That is *structural*, not a
  settings error, so a "recalibrate sprint power" hint (the genuine `rate_limited`-from-full case; §4.3)
  will not fix it. `D` should be reported as a third quantity (§6.9) and the per-system split refused when
  `D` is a large fraction of total (e.g. ~45% on a 4×4).
- **The product thesis — two bars → better pacing — is untested as a human-factors claim.** §6.8 shows
  the bar is *informative* often enough to matter on interval sessions, but not that a rider *decides
  better* with it. The minimum next step is a usability check (even n=1: race on it, log whether the
  second bar changed a call) before the display's value is asserted, not just its informativeness.
- **`C_p = 0` means the *usable* alactic store is spent, not that muscle PCr is zero.** Real PCr bottoms
  out around 20–40% of resting at exhaustion; `C_p` is the usable reserve above that floor, so `R_p = 0`
  on the display is "usable punch gone," not a muscle state that never occurs.
- **The compartments are *not* permanently unfalsifiable in-modality — retracted (§6.10).** v0.6 argued
  from two true premises (the split is unidentifiable from power, §4.2; 31P-MRS cannot run during cycling,
  §6.5) to a false conclusion, by assuming 31P-MRS is the only compartment-level measurement. **Muscle
  biopsy during cycle ergometry is another, it is already cited, and the model fails against it** (§6.10:
  repeated-sprint glycolytic share, model 23%↗ vs observed 40%↘). So there *is* a depletion-side,
  compartment-level, in-modality validation route, it needs no new data, and it is the highest-value test
  in the document. Cross-modality 31P-MRS transfer remains a route for the *recovery* constants, but it is
  no longer the only path. On *correctness* vs single-tank W′bal there is still no positive evidence
  (§6.6); §6.10 supplies the first *negative* one, which is progress.
- **Does the depletion-side machinery earn its keep, and where? (Corrected.)** The null to beat is a single
  reserve depleting as W′bal and recovering bi-exponentially (`f_p`, fast `τ_p`, slow `τ_g`) — no
  caps/spill/deficit. v0.6 concluded the machinery earns its keep "in exactly one regime, the maximal one"
  and is "inert everywhere the ceiling does not bind." **§6.9's ablation shows the opposite for short
  efforts:** the glycolytic ceiling binds *constantly* on 6-s sprints (glycolysis capped at tens of watts
  vs ~645 W demanded) and is the engine of the training-load separation — so the ceiling is not a
  sprint-only term, it is load-bearing whenever efforts are short. Where the ceiling *is* slack (submaximal
  supra-CP), the model does collapse to the null: `take_p = Δ·C_p/(C_p+C_g·g)` contains neither reserve and
  settles to a fixed `Δ·f_p` split within ~20 s — *(power − CP) rescaled* — so **per-system live consumption
  is a "modelled share," not a reading**, and is labelled as such (§5). Net: the depletion machinery earns
  its keep in the two regimes where efforts are short or maximal (sprint fidelity, training-load
  partitioning), and is redundant in the steady submaximal regime — a sharper, ablation-backed answer than
  v0.6's.
- **On identifiability, name the degenerate directions before fitting (Reviewer 3 m5).** `f_p` and
  `P_p_max` both set the sprint residual; `τ_p` and the pH coefficient `k` both set the repeated-bout decay;
  `g_rate` and the activation ramp both set the §6.9 partition level. A per-athlete fit that ignores these
  degeneracies will fit noise and call it calibration (§6.7 restricts routine fitting to `CP, W′, P_p_max`
  and the τ's for this reason).
- **A structural fork the paper now states rather than drifts through (Reviewers 3 and round-5).** The
  entire lightweight-model rationale (§3's parameter economy, §5's one `exp()` per tank, literature-fixed
  constants) exists to serve the *pacing* use case on a head unit. But §6.9–§6.10 have moved the paper's
  centre of gravity to the **training-load** use case — and that is a *post-hoc computation on a power
  file*. It does not need a head unit, 1 Hz, or nine literature-fixed parameters; it needs `g`, the
  capacity share, and the flux ceiling, and it can be computed off-device in a few dozen lines. Off-device,
  §3's argument reverses: with a laptop one can afford the 8-parameter hydraulic model with per-athlete
  fitting (which already out-predicts W′bal on intermittent protocols) or the 17-parameter bioenergetic
  model, and calibrate `g_rate`/`g_fat` to the biopsy data of §6.10. So there is a genuine product decision,
  stated here for the reader (and the maintainer) to make deliberately rather than by attrition: **if the
  live two-bar pacing display is the product, the pacing case has to carry it, and that case runs on the
  fast-reserve recovery transient; if the per-session training-load metric is the product, it belongs in a
  post-ride tool (intervals.icu / GoldenCheetah), where a better-resolved model is available.** The two are
  not exclusive, but they have different centres of gravity, and v0.6 blurred them.
- **Fixed time constants** ignore the documented pH-dependence and bout-to-bout slowing of PCr
  recovery unless the optional fatigue term is enabled.
- **Hard CP boundary → over-drain on short-recovery intermittent work (tracked limitation, issue #86).**
  Aerobic `supply` is clamped at CP, so it cannot represent an above-CP aerobic (VO₂ slow-component)
  contribution during/just-after intervals — the mechanism sub-minute-recovery work exploits. On
  **short-recovery intermittent** rides (recovery valleys ≲45–60 s, e.g. 30/15 s) the model
  over-attributes supra-CP work to the anaerobic tanks, drives the glycolytic reserve to the floor, and
  then under-predicts a subsequent maximal effort — reproduced on a real 30/15 ride (2026-07-20). The
  pathology is a smooth monotonic function of recovery duration and is essentially gone by ~45–60 s, so
  the model is **sound on continuous efforts, long-recovery intervals, and isolated sprints** and fails
  **only** in the short-recovery-intermittent corner. This is the shared W′bal depletion substrate (not
  the two-tank decomposition), and it is **parameter-proof**: in-range `W′`/`f_p`/valley-refill tuning
  refills *between* reps but cannot lift the CP cap (companion calibration item #87 — note the default
  `f_p = 0.25` is PCr-light, routing ~75% of W′ into the slow glycolytic vessel, which *amplifies* the
  symptoms on short-recovery work; the calibration tool now flags PCr-light + single-session fits). It consolidates the
  caveats scattered across §3 (hydraulic models out-predict W′bal on intermittent recovery), §6.6
  (out-of-sample intermittent tolerance as the decisive test), and §6.8 (informativeness ≠ accuracy on
  this subset). **Resolution is a deliberate structural fork, not a parameter change:** either (a) add an
  above-CP aerobic term for intermittent recovery — which makes `need = (P−supply)·Δt < Δ·Δt`, breaking
  the §4.4 *CP-referenced W′bal equivalence* (internal energy conservation is retained; the proof must be
  *re-stated* with aerobic-excess as a supply source) and pulling the model toward the hydraulic family —
  or (b) bound the stated validity domain and have the tools warn rather than report a spurious "empty"
  there. The R calibration tool now takes path (b): it flags `short-recovery` rides and marks them
  outside the validated domain. The above-CP term (a) is tracked separately as issue #88 (Phase 2 of #86).
  (Also unchanged: the boundary omits onset kinetics unless the optional aerobic-ramp term is enabled,
  and expect the same over-attribution in long low-intensity recovery — the failure mode reported for the
  EJAP 2023 model.)
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
slowly-recovering glycolytic tank; share supra-CP demand between them by **capacity**, cap each by its
**peak flux** (PCr tapering with fullness), and refill them with system-specific, intensity-gated laws.
It generalizes W′bal in depletion and diverges from it — deliberately — in recovery, it runs at 1 Hz on
a Garmin head unit, and it surfaces a two-system decomposition — *punch left* and *dig left* — that is
most informative in the transients where pacing decisions concentrate.

v0.7 changes two things structurally and settles a third. **Structurally:** the recovery law is fixed —
the linear LT1 gate that made the model unable to complete a 4×4 is replaced by Skiba's intensity-dependent
shape (§4.2/§4.4), so recovery is now bounded and monotone across powers, at no cost to the Ferguson curve
or the sprint battery. And the tanks are reframed, following the review series' convergent finding, as
**compartments of W′ rather than of muscle metabolites**: W′ recovers ~4× faster than the PCr and lactate
it is named after (§4.1a), which *exonerates* the time constants (they are the right constants for W′) and
*convicts* the metabolic naming (the labels are motivation, not measurement). Every "the bar equals biopsy
PCr" reading is withdrawn.

**The settled third thing is the honest status of the whole enterprise.** There is still no evidence the
decomposition is more *correct* than single-tank W′bal for pacing (that needs §6.6). But v0.6's claim that
the compartments are permanently unfalsifiable is **wrong**: §6.10 runs the model against biopsy
repeated-sprint data — in-modality, already cited — and it **fails in level and direction** (glycolytic
share 23%↗ vs 40%↘). That is the first falsifiable result in five rounds, and it reclassifies the output:
**the per-system split is a W′-decomposition heuristic and a descriptive statistic of a power file, not a
validated bioenergetic ATP partition.** The §6.9 training-load use case remains the strongest reason to
build the second tank — but its mechanism is the glycolytic flux ceiling scaled by the ramp (not the ramp
alone), it is blind to submaximal alactic work, and it must beat a zero-parameter stopwatch, not just
W′bal. So the model is now correctly located: a lightweight, honest, *heuristic* decomposition of W′, with
a live pacing display whose value rests on the fast-reserve recovery transient, and a post-ride training
metric that is promising, descriptive, and — for the first time — has a data-in-hand test that can earn or
sink it (§6.10). The physiological framing has run its course; the remaining moves are the recovery-law
head-to-head (§6.6) and the biopsy calibration (§6.10), both experiments, not arguments.

---

## References

See `docs/literature-review-anaerobic-models.md` for the full annotated bibliography with DOIs
and PMIDs. Primary sources for this paper:

- Skiba PL et al. 2012, *Med Sci Sports Exerc* — W′bal integral model. PMID 22382171, DOI 10.1249/MSS.0b013e31824cfdc0.
- Skiba PL et al. 2015 — differential W′bal. DOI 10.1249/MSS.0000000000000226.
- Bartram J et al. 2018, *IJSPP* — elite τ_W′ recalibration. DOI 10.1123/ijspp.2017-0356.
- Chorley A, Lamb K 2020, *Sports (Basel)* — CP/W′ reconstitution review (states the 37/65/86% figures were at "nominal 20 W" recovery). DOI 10.3390/sports8090123 (PMC7552657).
- Ferguson C, Rossiter HB, Whipp BJ, Cathcart AJ, Murgatroyd SR, Ward SA 2010, *J Appl Physiol* 108(4):866–874 — W′ reconstitution 37/65/86% at 2/6/15 min (half-time 234 s) at 20 W recovery; component recovery channels VO₂ t½ 74 s and lactate t½ 1366 s; W′ recovery is *not* a unique function of PCr or lactate. PMID 20093659, DOI 10.1152/japplphysiol.91425.2008 (the `.2008` DOI stem is the submission year; the article is 2010).
- Morton RH 1986, *J Math Biol* — three-component hydraulic model. DOI 10.1007/BF01236892.
- Weigend F, Behncke, Skiba 2021 — hydraulic model & `three_comp_hyd`. arXiv 2104.07903 / 2108.04510.
- Dynamic bioenergetic model, intermittent cycling, *Eur J Appl Physiol* 2023. PMID 37369795, DOI 10.1007/s00421-023-05256-7 (PMC10638188).
- di Prampero PE, Ferretti G 1999, *Respir Physiol* — anaerobic energetics reappraisal. PMID 10647856, DOI 10.1016/S0034-5687(99)00083-3.
- Harris RC et al. 1976 — biphasic PCr resynthesis. *Pflügers Arch*.
- Yoshida et al. 2013, *Scand J Med Sci Sports* — τ_PCr by muscle. PMID 23662804, DOI 10.1111/sms.12081.
- Parolin ML et al. 1999, *Am J Physiol Endocrinol Metab* — glycogen phosphorylase / PDH activation kinetics during maximal intermittent exercise (glycolytic activation over the first ~6 s). PMID 10567017, DOI 10.1152/ajpendo.1999.277.5.E890.
- Bogdanis GC et al. 1996, *J Appl Physiol* — PCr and aerobic contribution during repeated sprints (fresh 30 s sprint → PCr ≈ 17%; PCr resynthesis correlates with power recovery at r = 0.84–0.91; PCr 78.7% recovered at 3.8 min; the 'near-full by 10 s' figure is *sprint 2*, from 78.7% recovered — mis-cited in v0.6, corrected in v0.7). PMID 8964751, DOI 10.1152/jappl.1996.80.3.876.
- Bogdanis GC et al. 1998, *Acta Physiol Scand* 163(3):261–272 — power output and muscle metabolism after *fresh* 10 s and 20 s maximal sprints, with early (~2 min) recovery of PCr and reproducible power — the fresh-sprint conditions v0.6 lacked (verify exact percentages against the publisher PDF). PMID 9715738, DOI 10.1046/j.1365-201x.1998.00378.x.
- Bogdanis GC et al. 1995, *J Physiol* 482(2):467–480 — PCr resynthesis after a 30 s maximal sprint is *slower* than after longer, milder exercise (the acidotic-domain caution behind §4.1a). PMID 7714837, DOI 10.1113/jphysiol.1995.sp020533.
- Gaitanos GC et al. 1993, *J Appl Physiol* 75(2):712–719 — human muscle metabolism during 10×6 s maximal sprints: glycolytic ATP contribution falls from ~40% (sprint 1) to <10% (sprint 10) as PCr and aerobic metabolism take over (the repeated-sprint partition tested in §6.10). PMID 8226455, DOI 10.1152/jappl.1993.75.2.712.
- *Scientific Reports* 2024 — repeated-sprint ATP partitioning by system from vastus-lateralis biopsy during cycle ergometry (compartment-level, in-modality; §6.10). DOI 10.1038/s41598-024-78916-z.
- González‑Alonso J et al. 2000, *J Physiol* — heat production at exercise onset; PCr + glycogenolysis initially provide most energy. PMID 10766936, DOI 10.1111/j.1469-7793.2000.00603.x.
- Bangsbo J et al. 1990, *J Physiol* — anaerobic energy production and O₂ deficit during exhaustive exercise. PMID 2352192, DOI 10.1113/jphysiol.1990.sp018000.

*Sourcing note:* equations for the incumbent models were cross-checked against PubMed Central
full text (PMC7552657, PMC10638188); typeset equations there were image-embedded, so published
closed forms were reconstructed from the surviving prose and standard literature. Verify exact
coefficients against publisher PDFs before hard-coding.
