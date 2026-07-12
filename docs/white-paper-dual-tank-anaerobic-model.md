# A Dual-Tank Model for Real-Time Tracking of Phosphocreatine and Glycolytic Energy Reserves in Cycling

**White paper — AnaerobicFuelTanks project**
*Version 0.4 · 2026-07-11 (third revision — capacity-weighted split decoupled from the rate ceiling; η folded into τ_p; LT1-gated deficit; guards)*

> **Scope and status (read this once).** This model is a **physiologically-motivated decomposition of
> one measured quantity — single-tank W′bal — whose split fraction `f_p` is assumed, not measured.**
> Power alone cannot identify the depletion split (§4.2). By construction the model equals single-tank
> W′bal in depletion (§4.4) and differs only in *recovery*; and because the fast PCr tank is full most
> of the time, the second (PCr) bar carries information beyond single-tank W′bal only in the ~30–60 s
> after hard efforts. **As of v0.4 there is no evidence, of any kind, that the two-bar decomposition is
> more correct or more useful than single-tank W′bal** — the case is entirely physiological and
> prospective, resting on the recovery law, which has not yet been tested (§6.6) and cannot be
> validated in-modality (31P-MRS is unavailable in real cycling, §6.5). Several defaults (`f_p`, `τ_off`,
> the PCr depletion kinetic `τ_dep`) are literature-set assumptions, flagged where they appear; `τ_g`
> and the reconstitution calibration were **verified against the primary sources** in this revision
> (§4.1a). The rest of the paper does not repeat these caveats; it builds on them.

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

Two honest qualifications, stated here rather than buried in §7. First, the split is a **modeling
assumption**, not a measurement — power alone cannot identify how W′ divides between the two systems
(§4.2). Second, the extra resolution is **concentrated in transients**: whenever the fast PCr tank is
full — which, given its ~20 s recovery, is most of the time — the glycolytic reserve is just an
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
parameter count (`CP, W′, f_p, P_p_max, g_pmax-ratio, τ_p, τ_g, τ_on, τ_off, LT1, η` — **~11**, plus
two optional realism terms) is *larger* than the hydraulic model's eight — it is **not** a smaller
model.
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

The model has **~11 parameters** (plus two optional realism terms). Only `CP` and `W′` come from a
CP test; the rest are literature-fixed defaults (see §3 — this is a real count, not a small one):

| Symbol | Meaning | Typical default |
|---|---|---|
| `CP` | critical power (W) | from 3-/12-min CP test (≈ FTP + a few %) |
| `W′` | total work above CP (J) | from same test (~15–25 kJ) |
| `f_p` | fraction of W′ assigned to the PCr tank | **0.25** — *assumed* (physiology, not data; §7) |
| `P_p_max` | PCr peak power above CP (W), at a **full** tank | ≈ P₁ₛ − CP (best 1 s power − CP) |
| `g_rate` | glycolytic peak flux as a fraction of PCr peak flux (a ratio) | 0.5 → `g_pmax = g_rate·P_p_max` (flux-ratio note) |
| `τ_p` | PCr recovery time constant (s) | **27** (= 22 s literature `τ_PCr`, mechanically inflated; see η note) |
| `τ_g` | glycolytic recovery time constant (s) | 520 — reconstitution fit; the source protocol's recovery power is now **confirmed** (20 W), so this is calibrated, not confounded (§6.3) |
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
`τ_p` when fitted. Worse, it silently made the *effective* recovery constant ≈ 27.6 s while the table
advertised 22 s. We deleted it and set `τ_p = 27 s` (22 s of literature `τ_PCr` inflated by a
mechanically-plausible efficiency), so the headline number is the one the rider actually experiences.
(The settings key `eta` remains, defaulting to 1.0 = identity, for backward compatibility only.)

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

#### 4.1a Literature verification (v0.4) — the two open items resolved

Two defaults previously flagged "assumed, needs primary-source checking" were verified against the
sources (via PubMed):

- **The reconstitution reference protocol used ~20 W (near-passive) recovery.** The 37% / 65% / 86%
  W′-recovery at 2 / 6 / 15 min (half-time 234 s) is **Ferguson et al. 2010** (*J Appl Physiol*, DOI
  10.1152/japplphysiol.91425.2008), reviewed by Chorley & Lamb 2020. Chorley & Lamb state these figures
  were obtained "when recovering at a **nominal 20 W**." This **resolves the `τ_g` confound** (finding D
  of review 3): because the gate was ≈ 1 (20 W ≪ LT1), the passive-rest fit is the correct reading, so
  `τ_g ≈ 420–520 s` — **not** the ~260 s a 0.4·CP recovery would have implied. `τ_g = 520` stands as
  calibrated. *(With `f_p` held at 0.25 the single-parameter fit gives `τ_g ≈ 520`; a joint fit gives
  `f_p = 0.20, τ_g = 420` — both inside the supported bands.)*
- **The alactic fraction (`f_p`) is corroborated, not just assumed.** di Prampero & Ferretti 1999
  (*Respir Physiol*, DOI 10.1016/s0034-5687(99)00083-3) confirm the classic two-component split —
  alactic O₂-debt half-time ≈ 30 s (↔ `τ_p ≈ 27 s`), lactic ≈ 15 min (↔ slow `τ_g`); Bangsbo et al.
  1990 give ~20% alactic of anaerobic ATP. With the recovery power now known, the reconstitution curve
  *also* implies `f_p ≈ 0.20–0.25`, so two independent lines converge — a stronger footing than the
  physiology alone.

**One caution the same source raises**, worth stating: Ferguson et al. 2010 conclude that W′
reconstitution is "**not a unique function of phosphocreatine concentration or arterial [lactate]**, and
it is unlikely to simply reflect a finite energy store that becomes depleted." That is a direct warning
against reading the two tanks literally — precisely the heuristic-not-literal framing of the Scope box
and §2. The large separation it reports between the fast (VO₂ t½ = 74 s) and slow (lactate t½ = 1366 s)
recovery channels does, however, support a bi-exponential recovery structure.

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

# PCr: fast, oxidative — recovers at ANY sub-CP intensity (ungated)
R_p += (C_p − R_p) · (1 − exp(−Δt/τ_p))           # τ_p already absorbs the old η (§4.1)

# Glycolytic tank AND the deficit clear only below LT1 (a MEASURED power, not a %CP)
if P < LT1:
    gate = (LT1 − P) / LT1                        # 0 at LT1, → 1 toward zero power
    R_g += gate · (C_g − R_g) · (1 − exp(−Δt/τ_g))
    D   -= gate · D · (1 − exp(−Δt/τ_g))          # debt clears on the same gate as R_g
```

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
  refills within ~30–60 s of easy pedaling — matching PCr physiology. A maximal ~10 s sprint leaves
  **`R_p ≈ 20–30%`, not empty** — the tapered ceiling drains it geometrically with an emergent
  depletion constant `τ_dep = C_p/P_p_max ≈ 7 s`, so `R_p(10 s)/C_p ≈ 20–30%`. That residual *matches*
  Bogdanis 1996 (PCr ≈ 17% of rest at the end of a 30 s sprint) better than "empty" would; the earlier
  "empties `C_p`" claim was false under the taper and is withdrawn.
- A sustained supra-CP effort draws from **both** tanks, both declining ≈ linearly to their nadir
  together at exhaustion (capacity-weighted share; §4.2). During such steady efforts the two bars track
  each other and W′bal closely — the honest consequence of capacity weighting, and the behaviour §1/§7
  advertise; the earlier rate-weighted split manufactured apparent divergence that was a deterministic
  restatement of W′bal, not new information.
- **A falsifiable prediction the model makes.** For a constant supra-CP effort, integrating the draw
  gives `R_p/C_p` as a function only of the fraction `φ` of W′ spent — largely independent of intensity
  except where the rate ceiling bites. This connects to the reproducible-metabolic-milieu-at-exhaustion
  literature (§2) and is testable in an afternoon: hold different supra-CP powers to exhaustion and
  check whether PCr-at-a-given-%W′-spent is intensity-invariant. If it is grossly *not*, the tank
  architecture is wrong (see §7's "when to re-architect").
- **Synthetic battery (v0.4), all checks re-run after this revision's changes:**

  | Test | Result |
  |---|---|
  | Sustained 450 W — PCr at 25/50/75/100% of TTE | 68 / 42 / 18 / ~1% (near-linear, nadir at exhaustion) |
  | Both tanks at exhaustion | PCr ~1% / GLY ~0% (empty together) |
  | 945 W (= P₁ₛ) 10 s sprint — PCr residual | 23% (unchanged by the share-rule fix — ceiling-dominated) |
  | 6×[10 s@700 W / 30 s@150 W] — PCr at each bout end | 49→31→22→17→15→14% (ramp re-fires) |
  | 1200 W hold (caps bind) — combined W′bal conservation | leak = 0 J |
  | Debt repayment at 0.9·CP (above LT1) | `D` unchanged (correctly LT1-gated) |
  | `f_p = 0` | runs (guarded), no divide-by-zero |

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
- **Configuration:** `CP`, `W′`, `f_p`, **`LT1`** (a measured threshold, not a %CP default — §4.2),
  and the recovery constants exposed via Connect IQ app settings (`Application.Properties`), so a rider
  enters them from Garmin Connect.
- **Display:** two vertical bar gauges (PCr and glycolytic reserve) with numeric % and color
  bands (green → amber → red), plus optional live consumption in W.
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
3. **Reconstitution targets — what the curve actually constrains.** After a full W′ depletion,
   combined recovery can be compared to the published curve (≈37% / 65% / 86% at 2 / 6 / 15 min;
   Chorley & Lamb 2020). Two things follow, and the second corrects the previous revision:
   (a) **the curve is blind to the fast tank.** A `τ_p ≈ 27 s` process is `1 − e^(−120/27) ≈ 99%`
   complete by the first (2 min) sample, so this test validates *glycolytic* recovery and the *size* of
   the PCr offset — **not** PCr recovery kinetics, i.e. not the feature that distinguishes this model
   from W′bal. To constrain `τ_p` you need samples at ~10/20/30/45/60 s (test 4).
   (b) **the curve indicts `τ_g`, not `f_p`.** Solving each target point for `τ_g` (passive rest,
   `f_p = 0.25`) gives 688 / 472 / 537 s — all far above the old 360 s default; the ~234 s half-time
   cited for the incumbent implies `τ_g ≈ 578 s` independently. A least-squares fit lands at **`τ_g ≈
   520 s`**, giving 40 / 62 / 87% vs the 37 / 65 / 86% targets (max error ~4 pts, versus 8–9 pts at
   360 s). So the default `τ_g` was raised 360 → 520; **`f_p` was *not* re-derived from this curve.**
   The earlier "matching pulls `f_p` down" reasoning was confounded: the implied `f_p` swings from ~0.13
   (passive rest) to ~0.25 (soft-pedal recovery) depending entirely on the assumed recovery power of
   the reference protocol, so the curve cannot pin it. `f_p = 0.25` stands on **physiological**
   grounds (§4.1), not reconstitution.
   (c) **the `τ_g` confound is now RESOLVED** (it was the top open item of review 3). Because glycolytic
   recovery is LT1-gated, the *effective* constant is `τ_g/gate`, so the fit depends on the reference
   protocol's recovery power: passive rest (`gate ≈ 1`) → `τ_g ≈ 520`; a 0.4·CP recovery (`gate ≈ 0.5`)
   → `τ_g ≈ 260`. That protocol detail is now known: the source is **Ferguson et al. 2010** (DOI
   10.1152/japplphysiol.91425.2008), and per Chorley & Lamb 2020 the recovery was at a **nominal 20 W** —
   near-passive, `gate ≈ 1`. So `τ_g ≈ 520 s` is the calibrated value, not a 2× overshoot (§4.1a).
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
   sampling) can constrain it — and even then the fit is ill-conditioned. A sprint-then-hold protocol
   *without* early recovery sampling cannot fit `f_p`; absent test-4 data it stays assumed.

---

## 7. Assumptions and limitations

- **The PCr/glycolytic split `f_p` is assumed, but now corroborated by two independent lines.** Power
  alone cannot identify the depletion split (§4.2). We default to **0.25** from physiological
  alactic-fraction estimates (~0.20–0.30 of anaerobic ATP capacity; di Prampero & Ferretti 1999,
  Bangsbo 1990 ~20%); and with the reconstitution recovery power now known (20 W; §4.1a) the
  reconstitution curve *also* implies `f_p ≈ 0.20–0.25`. The supported band is ~0.20–0.25 — still a
  per-athlete calibration target, and outputs are sensitive to it, but no longer resting on a single
  citation.
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
- **`τ_g` is now calibrated (confound resolved); `τ_off` remains assumed.** The reconstitution source
  (Ferguson et al. 2010) recovered at ~20 W, so `τ_g ≈ 520` is the correct passive-rest reading, not a
  2× overshoot (§4.1a, §6.3c). `τ_off = τ_on` is still an assumption — Parolin measured activation, not
  de-activation (§4.2) — and remains the load-bearing one for repeated-sprint behaviour.
- **`LT1` should be measured, not derived from CP.** The `0.80·CP` fallback will be wrong for many
  riders (LT1 ranges ~65–85% of CP), and it gates whether the glycolytic tank recovers during tempo, so
  a bad value materially changes recovery estimates.
- **`C_p = 0` means the *usable* alactic store is spent, not that muscle PCr is zero.** Real PCr bottoms
  out around 20–40% of resting at exhaustion; `C_p` is the usable reserve above that floor, so `R_p = 0`
  on the display is "usable punch gone," not a muscle state that never occurs.
- **The headline feature is hard to validate in-modality — and unvalidated.** 31P-MRS cannot be run
  during real cycling (§6.5), depletion "fit-better" is guaranteed by construction, and the recovery
  law (which carries 100% of the novel signal) has not been tested (§6.6). So, stated plainly: **as of
  v0.4 there is no evidence, of any kind, that the second bar is more correct or more useful than
  single-tank W′bal.** The case is entirely physiological and prospective. That is a legitimate v0.4
  position, but it is the position.
- **Does the depletion-side machinery earn its keep? (An open design question.)** Everything
  decision-relevant — *punch back fast, dig back slow* — is a **recovery** phenomenon, and depletion is
  single-tank by construction. So the obvious null model to beat is: **a single reserve that depletes
  exactly as W′bal and recovers bi-exponentially** (fast `τ_p` + LT1-gated slow `τ_g`, split `f_p`).
  That yields the same two bars in recovery, the same divergence from Skiba, and **none** of the rate
  caps, spill logic, deficit, or guards — i.e. none of the machinery that generated three rounds of
  bugs. What the caps buy is (a) a non-instantaneous `C_p` drain and a genuine CK-flux constraint, and
  (b) per-system live consumption in watts (§4.3) — which is also the least identifiable, least
  actionable output. The rate caps are not worthless, but the paper should either **justify them
  against this null model or adopt it**; for a Connect IQ field, the null model may deliver the same
  display for a fraction of the code.
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

The honest bottom line, stated rather than gestured at: **as of v0.4 there is no evidence, of any kind,
that the two-bar decomposition beats single-tank W′bal.** Depletion is single-tank by construction; the
split `f_p` is assumed, not measured; and 100% of the novel signal lives in a recovery law that has not
been tested and cannot be validated in-modality (31P-MRS is unavailable in real cycling). The case is
entirely physiological and prospective. Three review rounds have also surfaced a real fork (§7): a
recovery-only null model may deliver the same display with a fraction of the machinery, and it is worth
choosing between "ship the heuristic" and "re-architect PCr as a state variable" deliberately rather
than by attrition. For a Connect IQ **data field**, the heuristic — with this revision's fixes — is the
right call: buildable, honest, and already what §1/§7 describe. Two of the three round-3 open items are
now **closed** by checking the primary sources (§4.1a): the reconstitution protocol recovered at ~20 W,
so `τ_g = 520` is calibrated (not confounded), and the same curve corroborates `f_p ≈ 0.20–0.25`. What
remains is the decisive **recovery-law head-to-head** (§6.6) — the test that would turn "physiologically
plausible, and now consistent with the recovery data" into "validated."

---

## References

See `docs/literature-review-anaerobic-models.md` for the full annotated bibliography with DOIs
and PMIDs. Primary sources for this paper:

- Skiba PL et al. 2012, *Med Sci Sports Exerc* — W′bal integral model. PMID 22382171, DOI 10.1249/MSS.0b013e31824cfdc0.
- Skiba PL et al. 2015 — differential W′bal. DOI 10.1249/MSS.0000000000000226.
- Bartram J et al. 2018, *IJSPP* — elite τ_W′ recalibration. DOI 10.1123/ijspp.2017-0356.
- Chorley A, Lamb K 2020, *Sports (Basel)* — CP/W′ reconstitution review (states the 37/65/86% figures were at "nominal 20 W" recovery). DOI 10.3390/sports8090123 (PMC7552657).
- Ferguson C, Rossiter HB, Whipp BJ, Cathcart AJ, Murgatroyd SR, Ward SA 2010, *J Appl Physiol* — W′ reconstitution 37/65/86% at 2/6/15 min (half-time 234 s) at 20 W recovery; W′ recovery is *not* a unique function of PCr or lactate. PMID 20093659, DOI 10.1152/japplphysiol.91425.2008.
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
