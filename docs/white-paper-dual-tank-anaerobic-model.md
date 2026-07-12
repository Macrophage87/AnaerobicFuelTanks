# A Dual-Tank Model for Real-Time Tracking of Phosphocreatine and Glycolytic Energy Reserves in Cycling

**White paper — AnaerobicFuelTanks project**
*Version 0.6 · 2026-07-12 (adds the training-load-partitioning use case — §6.9 — where the decomposition provides information W′bal and the recovery-only null model both lack)*

> **Scope and status (read this once).** This is a **physiologically-motivated decomposition of one
> measured quantity — single-tank W′bal — whose split fraction `f_p` is assumed, not measured** (power
> cannot identify the depletion split; §4.2). The two-bar display is precisely characterised, and the
> characterisation is narrow: **during steady supra-CP effort both bars are affine in W′bal**
> (`R_p/C_p ≈ R_g/C_g ≈ W′bal + const`; §4.2, §4.4), and when the PCr tank is full — most of the time —
> the PCr bar is likewise an affine transform of W′bal. **All non-redundant content lives in exactly two
> transients:** (i) the glycolytic *activation ramp* at effort onset, governed by `τ_on` (measured) and
> `τ_off` (**not** measured), and (ii) the *PCr recovery transient* after hard efforts, governed by `τ_p`
> and its new oxidative-headroom gate (§4.2). **There is still no experiment showing the two-bar
> decomposition is *more correct* than single-tank W′bal** — that requires the recovery-law head-to-head
> (§6.6), and at the compartment level it is unfalsifiable in-modality *even in principle* (§6.5, §8). But
> v0.5–0.6 add **usefulness** arguments the "affine with W′bal" critique does not reach. (i) On real
> interval rides the PCr bar is informative (below 95%) ~45% of the time and the caps move it up to
> ~25–60 pts vs a recovery-only null at decision points (§6.8). (ii) For **training** (as opposed to
> pacing), the *cumulative per-system load* distinguishes an alactic session (~76% PCr) from a glycolytic
> one (~41%) — information W′bal and the recovery-only null both structurally lack, since the null reports
> a fixed `f_p` for every session (§6.9). This second point is the strongest standalone reason to build
> the second tank. `f_p`, `τ_off`, and the emergent `τ_dep` remain assumed;
> `τ_g`/reconstitution were verified against primary sources (§4.1a). The rest of the paper builds on
> these; it does not re-litigate them.

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
(§4.2). Second, the extra resolution is **concentrated in transients**: whenever the fast PCr tank is
full — which, given its ~27 s recovery, is most of the time — the glycolytic reserve is just an
affine rescaling of the existing single W′bal, so the second bar adds decision-relevant information
mainly in the ~30–60 s after a hard effort (which is, however, exactly when covering-the-next-attack
decisions are made). The model earns its keep as a *heuristic decomposition*, not as two independently
measured reserves.

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
free-parameter count (`CP, W′, f_p, P_p_max, g_rate, τ_p, τ_g, τ_on, LT1`, with `τ_off = τ_on` by
default — **nine free**, plus two optional realism terms) is essentially the hydraulic model's eight —
**the same size, not a smaller model.**
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

The model has **nine free parameters** (plus `τ_off = τ_on` and two optional realism terms). Only `CP` and `W′` come from a
CP test; the rest are literature-fixed defaults (see §3 — this is a real count, not a small one):

| Symbol | Meaning | Typical default |
|---|---|---|
| `CP` | critical power (W) | from 3-/12-min CP test (≈ FTP + a few %) |
| `W′` | total work above CP (J) | from same test (~15–25 kJ) |
| `f_p` | fraction of W′ assigned to the PCr tank | **0.25** — *assumed* (physiology, not data; §7) |
| `P_p_max` | PCr peak power above CP (W), at a **full** tank | ≈ P₁ₛ − CP (best 1 s power − CP) |
| `g_rate` | glycolytic peak flux as a fraction of PCr peak flux (a ratio) | 0.5 → `g_pmax = g_rate·P_p_max` (flux-ratio note) |
| `τ_p` | PCr recovery time constant (s) | **27** — within the 31P-MRS `τ_PCr` range (20–40 s), gated by oxidative headroom (§4.2) |
| `τ_g` | glycolytic recovery time constant (s) | **470** — reconstitution fit (Ferguson 2010 at 20 W ⇒ gate ≈ 0.90; joint optimum with `f_p`; §4.1a) |
| `τ_on` | glycolytic activation time constant (s) | 6 (Parolin 1999) |
| `τ_off` | glycolytic **de**-activation time constant (s) | = `τ_on` — *assumed* (Parolin measured activation, not de-activation; §7) |
| `LT1` | first lactate threshold power (W); glycolytic tank recovers below it | **measured** (a threshold test), *not* a fixed %CP |

Derived: `C_p = f_p·W′`, `C_g = (1 − f_p)·W′`. Initial state `R_p = C_p`, `R_g = C_g` (full).

**Free-parameter count.** Nine free (`CP, W′, f_p, P_p_max, g_rate, τ_p, τ_g, τ_on, LT1`); `τ_off = τ_on`
by default. Only `CP` and `W′` are fitted per athlete; the rest are literature-set. That is essentially
the hydraulic model's eight — **the same size, but the parameters are literature-set rather than
fitted per athlete** (the real trade; §3). A PCr *depletion* kinetic, `τ_dep = C_p/P_p_max`, also falls
out of the above (§4.4) and is equally assumed — see §7.

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
Parolin 1999 / Bogdanis 1996), so PCr is the higher-power system by about 2:1.

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
- **Ferguson's own components contradict the model's identification — and this is the strongest single
  datum in the paper.** Ferguson reports the two recovery channels underlying W′ reconstitution: VO₂
  t½ = 74 s (a proxy for oxidative/PCr resynthesis) and blood-lactate t½ = 1366 s. Put those beside the
  model's component half-times:

  | Component | Model | Ferguson channel | ratio |
  |---|---|---|---|
  | fast | `τ_p = 27 s` → t½ **18.7 s** | VO₂ **74 s** | 4.0× slower |
  | slow | `τ_g = 470 s` → t½ **326 s** | lactate **1366 s** | 4.2× slower |

  **Both of the model's components are ~4× too fast, yet the aggregate 234 s half-time reproduces.** That
  is the signature of fitting two exponentials to a *sum* without checking them against the *components* —
  the identifiability problem this review series has circled, now with a number. And Ferguson's own
  conclusion is blunter still: W′ reconstitution is "**not a unique function of phosphocreatine
  concentration or arterial [lactate], and it is unlikely to simply reflect a finite energy store that
  becomes depleted.**" *The primary source used to calibrate the recovery law explicitly denies that the
  recovery decomposes the way the model decomposes it.* We host that here rather than resolve it by
  citation-picking. Two defences, and their limits: (i) VO₂ off-kinetics is **not** PCr resynthesis — it
  includes slower circulatory processes — and muscle 31P-MRS `τ_PCr` of 20–40 s does support `τ_p = 27`;
  so `τ_p` is defensible against the 31P literature while being 4× off against the channel measured in
  the very protocol that produced the recovery curve. (ii) The channel *separation* (74 s vs 1366 s, ~18×)
  genuinely supports a bi-exponential structure, even if the channel *values* are not the tanks. The
  tension is the finding; the two-tank recovery is a heuristic that fits the aggregate, not a measured
  decomposition of it.

### 4.2 The 1 Hz update

Let `P` be instantaneous power (W) and `Δt = 1 s`. Define the demand relative to aerobic supply
as `Δ = P − CP`.

**Case 1 — depletion (`Δ > 0`, above CP).** Demand `need = Δ·Δt` (J) is met by **both systems in
parallel**. This matters: glycolytic ATP supply is not instantaneous. Glycogen phosphorylase (the
rate-limiting glycolytic enzyme) transforms to its active form over the first several seconds of
maximal effort — Parolin *et al.* (1999) measured it rising from 12% at rest to 47% by 6 s — while
phosphocreatine is the immediate buffer (a fresh 30 s sprint drains it to ~17%; a 10 s sprint leaves ~20–30%; Bogdanis *et al.*
1996); both contribute from the onset, not in sequence (González‑Alonso *et al.* 2000). We model this
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

**Why the share and the ceiling are different objects** (this is the fix that ended a three-round patch
cycle). The rate ceiling — `P_p_max`, `g_pmax` — encodes "PCr is the higher-power system." That is true
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
  ~10 s all-out sprint leaves `R_p ≈ 20–30%`, matching Bogdanis 1996; §4.4), and PCr dominance emerges
  from the ceiling, not the weight.
- **Energy conserved even when a cap binds.** Residual `unmet` is banked in a **deficit `D`** (standard
  W′bal permits a negative balance), so `(R_p + R_g − D)` drops by exactly `Δ`·Δt per second and §6.2
  holds. `D` clears only below LT1 (Case 2) — it is supra-cap byproduct load and must respect the same
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

# PCr: fast, oxidative — resynthesis needs aerobic ATP ABOVE the ride's own demand, so it is
# gated by the OXIDATIVE HEADROOM (CP − P): full at rest, near-arrested at CP.
gate_p = max(0, (CP − P) / CP)
R_p += gate_p · (C_p − R_p) · (1 − exp(−Δt/τ_p))  # τ_p from 31P-MRS τ_PCr (§4.1)

# Glycolytic tank AND the deficit clear only below LT1 (a MEASURED power, not a %CP)
if P < LT1:
    gate = (LT1 − P) / LT1                        # 0 at LT1, → 1 toward zero power
    R_g += gate · (C_g − R_g) · (1 − exp(−Δt/τ_g))
    D   -= gate · D · (1 − exp(−Δt/τ_g))          # debt clears on the same gate as R_g
```

**The PCr recovery gate is new in v0.5, and it fixes the model's headline use case.** Until now PCr
recovered at the same rate whether the rider was stopped or holding 99% of CP — so the "punch" bar went
green while the rider was still under load, in exactly the "*can I cover this next attack?*" scenario the
field exists for (sitting in a bunch between attacks is recovery at high sub-CP power). PCr resynthesis
is oxidative and needs spare aerobic capacity, which vanishes as P → CP; the `gate_p = (CP − P)/CP` term
encodes that. At P = 0 it is identical to the old law (`gate_p = 1`), so nothing in depletion or the
reconstitution fit moves; at tempo it does the physiologically obvious thing. Verified: after a 20 s /
700 W effort (PCr → 23%), 60 s of recovery now restores PCr to **87% at 0 W, 46% at 0.8·CP, and 25% at
0.99·CP** — versus a flat 92% at every recovery power before the gate.

The `g` de-activation is what makes the activation ramp re-fire on each interval of a repeated-bout
set (without it, `g` would ratchet to 1 on the first surge and every later bout would start at a flat
split — the ramp inert for the rest of the ride). **`τ_off = τ_on` is an assumption, and a
load-bearing one:** Parolin (1999) measured phosphorylase *activation*, not *de*-activation, which is a
separate quantity. If de-activation runs on a minutes timescale rather than seconds, the ramp would not
re-fire on 30 s recoveries and the repeated-sprint behaviour changes materially — so `τ_off` is flagged
alongside `f_p`, `τ_g` (§7).

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
- **Combined W′bal** `= (R_p + R_g − D)/W′` — the deficit term keeps this **energy-conserving in
  depletion** (it drops by exactly `Δ`·Δt per second) so it matches a single-tank W′bal reference on
  above-CP segments. It intentionally **diverges in recovery** (bi-exponential + LT1 gate; §4.4/§6.2),
  so it is *depletion-compatible*, not identical everywhere.
- **Depletion / exhaustion flag** — the rider is producing power beyond the tanks' rate/capacity
  (`D` growing), or both reserves are at/near zero.

### 4.4 Why this behaves correctly

- A short, very hard surge draws mostly from `R_p` (glycolysis has not yet ramped in), and `R_p`
  refills after — *at a rate set by recovery intensity* (§4.2 gate). A maximal ~10 s sprint leaves
  **`R_p ≈ 20–30%`, not empty**, from the tapered ceiling's emergent depletion constant
  `τ_dep = C_p/P_p_max`. **But `τ_dep` is not a fixed 7 s** — §7 notes it swings ~4–13 s across riders,
  so the 10 s residual ranges from ~10% (fast riders) to **~46%** (`τ_dep ≈ 13 s`). The central case
  matches Bogdanis 1996 (PCr ≈ 17% at 30 s); the high tail does *not*, which is an argument for a
  *measured* PCr depletion constant (the re-architect fork, §7), not an emergent ratio.
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
- **Synthetic battery (v0.5).** Parameters: `CP = 255 W`, `W′ = 20 kJ`, `f_p = 0.25`, `P_p_max = 690 W`
  (`g_rate = 0.5`), `τ_p = 27`, `τ_g = 470`, `τ_on = τ_off = 6`, `LT1 = 204 W`.

  | Test | Result |
  |---|---|
  | Sustained 450 W — PCr at 25/50/75/100% of TTE | 68 / 42 / 18 / ~1% (front-loaded, nadir at exhaustion) |
  | Both tanks at exhaustion | PCr ~1% / GLY ~0% (empty together) |
  | 945 W (= P₁ₛ) 10 s sprint — PCr residual | 23% (ceiling-dominated; share rule doesn't bind) |
  | 6×[10 s@700 W / 30 s@150 W] — PCr at each bout end | 49→17→10→8→8→7% (gated recovery: 150 W is high sub-CP, so little refill) |
  | 1200 W hold (caps bind) — combined W′bal conservation | leak = 0 J |
  | PCr recovery after 700 W/20 s, 60 s @ {0, 128, 204, 242, 252} W | 87 / 68 / 46 / 30 / 25% (headroom gate) |
  | Debt repayment at 0.9·CP (above LT1) | `D` unchanged (LT1-gated) |

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
interval/VO₂max sessions (the model's best case — a steady endurance ride would score far lower):

- **How often is the PCr bar informative?** The bar carries information beyond single-tank W′bal only
  when the PCr tank is not full. Across the six rides, **`R_p` is below 95% for ~45% of ride time
  (range 20–79%)** — well above the ~3% ("curiosity") and ~20% ("real") thresholds a reviewer proposed.
  On interval sessions the second bar is live nearly half the time. *(Caveat: these are hard interval
  files; on a steady endurance ride PCr is full most of the time and the figure would be small.)*
- **Does the depletion machinery change the display, vs the recovery-only null model?** Running the full
  model and the null (§7) on the same traces, the PCr bar diverges by a **mean of ~6 pts but up to
  ~25–60 pts**, with the maxima at the **starts of recovery valleys** — right after attacks, the
  decision-relevant window. That is well above the ~5-pt "a rider could act on it" threshold, so **on
  interval sessions the caps earn their keep**: they set the post-effort PCr level the recovery law then
  acts on, and a null model would read materially differently exactly when it matters. This is the first
  evidence that the depletion-side machinery is not merely inert plumbing — though only in the maximal
  regime (§7 discusses where it is, and is not, doing work).

Neither result validates the *compartments* (that is §6.6, and at the compartment level unfalsifiable
in-modality — §6.5, §8). They answer a narrower, real question — *is the two-bar display worth showing,
and does the model's complexity change what it shows* — with data instead of assertion, and the answers
are yes and yes, for interval training.

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

The model can, because the **activation ramp** makes the per-system split depend on *effort structure*,
not just `f_p`: short efforts keep `g` low (PCr-weighted); sustained efforts let `g → 1`
(glycolytic-weighted). Simulated per-system load for three archetypal sessions (default parameters):

| Session | PCr load | Glyc load | **PCr % of anaerobic load** | W′bal | recovery-only null |
|---|---|---|---|---|---|
| 10 × [6 s @ 900 W / full recovery] — **alactic** | 26.8 kJ | 8.7 kJ | **76%** | one number | 25% |
| 5 × [60 s @ 360 W / short recovery] — **glycolytic** | 12.1 kJ | 17.7 kJ | **41%** | one number | 25% |
| 3 × [8 min over-under / sustained] — **glycolytic** | 12.7 kJ | 18.3 kJ | **41%** | one number | 25% |

Two things stand out. First, the model **discriminates** the alactic session (76% PCr) from the
glycolytic ones (41%) — the qualitative signal a training plan needs. Second, this is a use case where
**the depletion-side machinery earns its keep and the recovery-only null model does not**: the null
depletes both tanks proportionally to capacity regardless of effort structure, so it reports a fixed
`f_p` (25%) for *every* session and is blind to exactly the distinction that matters here. The
discriminating content is the activation ramp — precisely the `τ_on`/`τ_off` term the reviews identified
as the depletion phase's only non-redundant information (§7), now shown to carry a concrete, actionable
signal.

Honest limits: the *absolute* per-system kJ scale with the assumed `f_p`, so the exact percentages are
soft; what is robust is the **ordering and separation** between session types, which the ramp drives. And
this is still a training-*design* signal, not a validated training *outcome* — it says a session was
alactic- or glycolytic-dominant, not that partitioning training by it improves adaptation (an
intervention study, not a modelling result). But unlike the pacing case, here the two-bar model provides
information W′bal and the null model both *structurally lack* — which is the strongest standalone argument
in the paper for building the second tank at all.

---

## 7. Assumptions and limitations

- **The PCr/glycolytic split `f_p` is assumed (physiology), and *consistent with* — not corroborated
  by — the recovery data.** Power cannot identify the depletion split (§4.2). We default to **0.25** from
  physiological alactic-fraction estimates (~0.20–0.30; di Prampero & Ferretti 1999, Bangsbo 1990 ~20%).
  The reconstitution curve constrains a `(f_p, τ_g)` ridge, not `f_p`, and physiology is what selects
  `f_p` on it (§4.1a) — so the two "lines" are not independent, and the recovery data alone would prefer
  ~0.20. Supported band ~0.20–0.25; a per-athlete target; outputs are sensitive to it.
- **The reserves are a decomposition, not latent state.** The two bars are a physiologically-motivated
  split of one measured quantity (W′bal), not two independently measured reserves. When the PCr tank is
  full — which, given `τ_p ≈ 27 s`, is most of the time except the ~30–60 s after a hard effort — the
  glycolytic bar is an affine transform of the existing single W′bal (`W′bal = f_p + (1−f_p)·R_g/C_g`),
  so it carries no new information there. The PCr bar adds decision-relevant content **only** in those
  post-surge transients. Those transients *are* where race decisions concentrate (can I cover this
  attack right after the last one?), which is the case for the display — but the honest framing is a
  heuristic decomposition whose split is assumed, not "the two numbers a rider races on" as if both
  were measured.
- **The PCr *depletion* rate is also assumed — and it was invisible until v0.4.** The tapered ceiling
  gives an emergent depletion constant `τ_dep = C_p/P_p_max`, tied to *no* measured PCr depletion
  kinetic; it is the ratio of three parameters and swings ~3× across plausible riders (~4–13 s). §7 was
  scrupulous about the assumed *recovery* constants and silent about this equally load-bearing
  *depletion* one. It should be sanity-checked against literature PCr depletion half-times, not left to
  fall out of `f_p`, `W′`, and a 1 s sprint power.
- **`τ_g` is calibrated to ~470 (confound resolved); `τ_off` remains assumed.** Ferguson recovered at
  ~20 W (gate ≈ 0.90), so `τ_g ≈ 470` — not 520, and not the 260 a soft-pedal recovery would have implied
  (§4.1a). `τ_off = τ_on` is still an assumption (Parolin measured activation, not de-activation; §4.2)
  and, per Reviewer 2, it is the *only* parameter carrying the depletion-phase novelty: since both bars
  are affine in W′bal in steady effort, the non-redundant depletion content is the activation-ramp
  offset, which is a function of `τ_on` (measured) and `τ_off` (not).
- **`LT1` should be measured, not derived from CP.** The `0.80·CP` fallback will be wrong for many
  riders (LT1 ranges ~65–85% of CP), and it gates whether the glycolytic tank recovers during tempo, so
  a bad value materially changes recovery estimates.
- **Several small modeling choices are assumptions, flagged not defended.** The LT1 gate shape
  (`(LT1−P)/LT1`, linear, vanishing just below LT1 — its slope depends on LT1's absolute value, and it
  arguably switches off metabolite clearance too abruptly through the tempo band); lumping deficit
  clearance and glycolytic-tank refill onto the *same* `τ_g`; and the spill order (unmet demand spills
  to glycolytic before PCr). Each is a defensible default, none is derived — named here so a reader
  weights them accordingly.
- **The deficit `D` corrupts the display precisely at maximal effort.** When `D` is large the two bars
  read slightly full; `D` grows when power exceeds the (possibly stale) `P_p_max` rate cap, and `P₁ₛ`
  decays intra-ride with fatigue, so this recurs late in hard efforts — a display *failure mode*, not
  just an accounting footnote. The field should surface a "recalibrate sprint power" hint when `D` grows
  from full tanks (the `rate_limited` flag; §4.3).
- **The product thesis — two bars → better pacing — is untested as a human-factors claim.** §6.8 shows
  the bar is *informative* often enough to matter on interval sessions, but not that a rider *decides
  better* with it. The minimum next step is a usability check (even n=1: race on it, log whether the
  second bar changed a call) before the display's value is asserted, not just its informativeness.
- **`C_p = 0` means the *usable* alactic store is spent, not that muscle PCr is zero.** Real PCr bottoms
  out around 20–40% of resting at exhaustion; `C_p` is the usable reserve above that floor, so `R_p = 0`
  on the display is "usable punch gone," not a muscle state that never occurs.
- **The compartments are unfalsifiable in-modality — permanently, not "not yet."** Two facts compound:
  the depletion split is unidentifiable from power (§4.2), *and* 31P-MRS cannot be run during real
  cycling (§6.5). Together these are not "untested" — they are "**no in-modality measurement, even in
  principle, distinguishes the two-compartment model from a one-compartment model with the same
  aggregate recovery.**" So for cycling the "two tanks" framing is *terminally* a heuristic: it can be
  motivated, never confirmed in-modality. The only route to compartment-level evidence is
  **cross-modality transfer** — measure `τ_p` by knee-extension 31P-MRS (where the magnet works) and
  assume it transfers — which is itself a nameable, stress-testable assumption, unlike the current
  no-path-at-all. On *correctness* vs single-tank W′bal there is still no evidence (that needs §6.6). On
  *usefulness*, v0.5 adds the first real-ride evidence (§6.8): the bar is informative ~45% of interval-
  ride time and the caps move it materially at decision points — necessary, not sufficient, for the
  product thesis.
- **Does the depletion-side machinery earn its keep? (Now answered, with data.)** The null model to
  beat is **a single reserve that depletes exactly as W′bal and recovers bi-exponentially** (fast `τ_p`
  + LT1-gated slow `τ_g`, split `f_p`) — the same two bars in recovery, none of the caps/spill/deficit/
  guards. The answer, from §6.8: the caps **do** move the display on real interval sessions (up to
  ~25–60 pts at recovery-valley starts), so they are not inert — but they earn their keep in **exactly
  one regime, the maximal one**, where the tapered ceiling binds and produces the ~23% sprint residual
  and the post-effort PCr level the recovery law then acts on. Everywhere the ceiling does *not* bind
  the machinery is inert, and in particular **per-system live consumption (§4.3) is not a reading**:
  when the ceiling is slack, `take_p = Δ·C_p/(C_p+C_g·g)` contains neither `R_p` nor `R_g` — it settles
  to a fixed `Δ·f_p` / `Δ·(1−f_p)` split within ~20 s, i.e. it is *(power − CP) × a clock*, the power
  meter rescaled. So: **keep the ceiling (scoped to sprint fidelity), and relabel per-system live
  consumption as "modelled share," not a measurement** (or drop it). That is the answer to Reviewer 2's
  S1, drawn from the model's own equations — not "adopt the null wholesale," but "keep the one part that
  does work and stop claiming the parts that don't." **And there is a second regime the null cannot
  touch:** cumulative per-system *training load* (§6.9) — the activation ramp makes the split
  effort-structure-dependent (alactic 76% vs glycolytic 41% PCr), while the null reports a fixed `f_p`
  for every session. So the depletion machinery earns its keep in **two** places (maximal sprint
  fidelity, and training-load partitioning), not zero as the affine-with-W′bal critique implies for
  pacing alone.
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
slowly-recovering glycolytic tank; share supra-CP demand between them by **capacity**, cap each by its
**peak flux** (PCr tapering with fullness), and refill them with system-specific, intensity-gated laws.
It generalizes W′bal in depletion and diverges from it — deliberately — in recovery, it runs at 1 Hz on
a Garmin head unit, and it surfaces a two-system decomposition — *punch left* and *dig left* — that is
most informative in the transients where pacing decisions concentrate.

The honest bottom line, stated rather than gestured at: **there is still no evidence the two-bar
decomposition is more *correct* than single-tank W′bal** (that needs §6.6, and at the compartment level
is unfalsifiable in-modality even in principle — §6.5, §7). What v0.5–0.6 *do* add is
**usefulness** arguments: on real interval rides the PCr bar is informative ~45% of the time and the
caps move the display up to ~25–60 pts at decision points (§6.8); and — the strongest standalone point —
for **training** the cumulative per-system load distinguishes an alactic session (~76% PCr) from a
glycolytic one (~41%), information both W′bal and the recovery-only null structurally lack (§6.9). So the
depletion machinery is not inert. That resolves the fork
more precisely than "ship vs re-architect": **ship the heuristic, keep the ceiling scoped to sprint
fidelity, and stop claiming the parts of the machinery the equations show are inert** (per-system live
consumption is `(power − CP)` rescaled, not a reading — §7). The `τ_g` confound is closed (Ferguson at
20 W ⇒ 470; §4.1a), and a genuine tension is now hosted rather than buried: Ferguson's *own* recovery
components are ~4× slower than the model's while the aggregate fits, and Ferguson concludes the
decomposition cannot be done — the strongest single datum in the paper, and it points at the model's
premise. What remains decisive is the **recovery-law head-to-head** (§6.6). The physiological framing has
run out of room; only that experiment can move this further.

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
- Bogdanis GC et al. 1996, *J Appl Physiol* — PCr and aerobic contribution during repeated sprints (fresh 30 s sprint → PCr ≈ 17%; the 'near-full by 10 s' figure is *sprint 2*, from 78.7% recovered). PMID 8964751, DOI 10.1152/jappl.1996.80.3.876.
- González‑Alonso J et al. 2000, *J Physiol* — heat production at exercise onset; PCr + glycogenolysis initially provide most energy. PMID 10766936, DOI 10.1111/j.1469-7793.2000.00603.x.
- Bangsbo J et al. 1990, *J Physiol* — anaerobic energy production and O₂ deficit during exhaustive exercise. PMID 2352192, DOI 10.1113/jphysiol.1990.sp018000.

*Sourcing note:* equations for the incumbent models were cross-checked against PubMed Central
full text (PMC7552657, PMC10638188); typeset equations there were image-embedded, so published
closed forms were reconstructed from the surviving prose and standard literature. Verify exact
coefficients against publisher PDFs before hard-coding.
