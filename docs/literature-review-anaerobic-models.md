# Mathematical Models of Anaerobic Metabolism in Cycling

**A literature review focused on separating the phosphocreatine (alactic) and
glycolytic (lactic) systems, and modeling their depletion & restoration from power output.**

*Compiled 2026-07-10. Sources are cited inline with DOIs / PMIDs. Full-text passages were
retrieved via PubMed / PubMed Central; please cite PubMed and the listed DOIs when reusing.*

---

## 0. TL;DR — the answer to the core question

**Yes, you can model both systems from a power trace, but no single mainstream model does
it cleanly.** The literature splits into three families, ordered by how explicitly they
separate phosphocreatine (PCr) from glycolysis:

| Family | Separates PCr vs glycolytic? | Driven by power? | Depletion | Restoration |
|---|---|---|---|---|
| **A. Critical Power / W′-balance** | ❌ No — lumps all anaerobic work into one tank `W′` | ✅ Yes | linear in `(P − CP)` | mono-exponential, `τ_W′` |
| **B. Hydraulic "tank" models** (Margaria–Morton) | ✅ **Yes — explicit AnF (phosphagen) + AnS (glycolytic) vessels** | ✅ Yes (power = outflow tap) | fluid drains by vessel | refill via inter-vessel tubes |
| **C. Bioenergetic supply/demand ODEs** | ✅ Yes — separate alactic / lactic / aerobic metabolic-rate terms | ✅ Yes | error-signal ODEs | time-constant + power-gated removal |

**If your project ("AnaerobicFuelTanks") wants literal, separately-tracked fuel tanks for
PCr vs lactic, Family B (the Margaria–Morton hydraulic model, esp. the Weigend/Morton
three-component formalization) is the closest published match, and Family C gives you the
mechanistic ODEs to make the tanks power-driven and physiologically calibrated.**

---

## 1. The two anaerobic systems (what we are trying to model)

Classic partitioning of "anaerobic" energy into two sub-systems (Margaria; di Prampero):

**Alactic / phosphagen system (ATP–PCr)**
- Highest metabolic *power* (rate), smallest *capacity* — exhausted in a few seconds of maximal effort.
- Physiological store ≈ intramuscular PCr (~20–25 mmol·kg⁻¹ wet muscle).
- Depletion: near-instant at exercise onset / any supra-demand transient.
- **Restoration is fast and largely oxidative**: classic alactic O₂-debt half-time ≈ **~30 s** (Margaria).
  31P-MRS gives PCr-recovery time constants of **~20–40 s**, strongly **pH-dependent** (acidosis slows it),
  and **biphasic** (fast + slow component) under high glycolytic load.
  - Harris et al. 1976 (the foundational biopsy study) — biphasic PCr resynthesis, fast half-time ≈ 20–22 s, slow component ~170 s.
  - Yoshida et al. 2013, *Scand J Med Sci Sports* — τ_PCr differs by muscle (17–43 s), PMID **23662804**, DOI 10.1111/sms.12081.
  - Intersubject acidosis effect on τ_PCr driven by proton-efflux rate — *Am J Physiol Cell Physiol* 2007, DOI 10.1152/ajpcell.00023.2007.

**Lactic / glycolytic system (anaerobic glycolysis → lactate)**
- Lower peak power than PCr, much larger capacity; dominant for ~10 s–~2 min all-out.
- "Fuel" state is best tracked as **accumulated muscle/blood lactate** (a proxy for H⁺ / metabolite accumulation).
- Depletion: engaged once demand outstrips aerobic + alactic supply; e.g. glycolysis supplies ~40% of ATP in the *first* of 10×6 s sprints, falling below 10% by the last (Nature *Sci Rep* 2024, DOI 10.1038/s41598-024-78916-z).
- **Restoration is slow**: lactic O₂-debt half-time ≈ **~15 min** (Margaria); blood-lactate recovery half-time ~1366 s in the CP literature below.

**Reference reviews on this partition**
- di Prampero & Ferretti, *"The energetics of anaerobic muscle metabolism: a reappraisal…"*, PMID **10647856**, DOI 10.1016/S0034-5687(99)00083-3.
- "Measurement of Anaerobic Capacities in Humans" (MAOD as gold standard), *Sports Med* 1993, DOI 10.2165/00007256-199315050-00003.
- Alternative single-effort split: alactic (PCr) from post-exercise VO₂ + glycolytic from peak blood lactate — DOI 10.1038/srep42485 (cycling), and conversion-factor method DOI 10.3389/fphys.2023.1147321.

---

## 2. Family A — Critical Power & W′-balance (the power-native standard)

**What it is.** The dominant power-based framework in cycling. Two parameters from a
maximal power–duration test:
- **CP** (critical power, W) — highest sustainable rate, ~aerobic asymptote.
- **W′** ("W-prime", J) — a *single finite* work reserve above CP, i.e. **all anaerobic capacity lumped together** (PCr + glycolytic, not separated).

**Core equations.**
- Power–duration hyperbola: `P = W′ / t + CP`  → `t_lim = W′ / (P − CP)`.
- Linear work form: `W = W′ + CP · t`.

**Depletion + reconstitution (this is the depletion/restoration you asked about):**

*Skiba 2012 — integral "W′bal" model ("Skiba1"):*
```
W′bal(t) = W′0 − ∫₀ᵗ  W′exp(u) · e^(−(t−u)/τ_W′)  du
```
- `W′exp = (P − CP)` while `P > CP` (expenditure, linear in power above CP).
- Reconstitution is **mono-exponential** with time constant `τ_W′`, which depends on how far
  *below* CP you recover (`D_CP = CP − P_recovery`):
```
τ_W′ = 546 · e^(−0.01 · D_CP) + 316      (s)
```
  The **+316 s** asymptote means recovering harder than ~316 W below CP yields no further benefit.
  Skiba PL et al., *Med Sci Sports Exerc* 2012, **PMID 22382171**, DOI 10.1249/MSS.0b013e31824cfdc0.

*Skiba 2015 differential form ("Skiba2"):* chemical-kinetics derivation letting you compute
`W′bal` continuously / in real time (compartmentalized for `P>CP` and `P≤CP`). DOI 10.1249/MSS.0000000000000226.

*Froncioni–Clarke–Skiba differential (the GoldenCheetah implementation):*
```
dW′bal/dt = −(P − CP)                       if  P > CP     (expenditure)
dW′bal/dt = (CP − P) · (W′0 − W′bal) / W′0   if  P ≤ CP     (reconstitution)
```
Simple, τ-free, integrates the recovery rate directly from instantaneous power.

*Bartram 2018 — elite-athlete recalibration* (Skiba2 under-predicts elite reconstitution):
```
τ_W′ = 2287.2 · e^(−0.01 · D_CP) + 286.9    (s)
```
DOI 10.1123/ijspp.2017-0356.

**Reported reconstitution behaviour (calibration targets):**
- W′ recovered ≈ **37% / 65% / 86%** after **2 / 6 / 15 min** of low-power recovery.
- W′ reconstitution **half-time ≈ 234 s** — *does not* align with VO₂ half-time (~74 s) or blood-lactate half-time (~1366 s). This mismatch is itself evidence that a single lumped tank with one τ is physiologically incomplete.

**Key limitations (why it motivates a PCr-vs-lactic split):**
- W′ **lumps PCr and glycolytic capacity into one reservoir** — you cannot read out the two systems separately.
- Mono-exponential recovery with a **single τ** cannot capture the observed **slowing of reconstitution across repeated bouts** (a known PCr behaviour), nor the fast/slow biphasic PCr kinetics.
- τ_W′ derived on **untrained** subjects and is **highly individual**; recommend personalizing.
- Caen et al.: faster depletion → faster reconstitution despite no VO₂/lactate/pH differences — mechanism still unresolved.

**Best single entry point:** Chorley & Lamb narrative review, *"Application of CP, W′, and its
Reconstitution"*, **PMC7552657**, *Sports (Basel)* 2020, DOI 10.3390/sports8090123 — this is
where Eqs. 5–9 above are laid out and critiqued.

---

## 3. Family B — Hydraulic "tank" models (the explicit PCr-vs-lactic split)

**This is the family your repo name evokes.** Energy systems are literal *vessels of fluid*;
power output is a **tap** draining fluid; recovery is fluid **flowing back between vessels
through connecting tubes**. Crucially it has **two separate anaerobic tanks**.

**Lineage**
- **Margaria (1976)** — original hydraulic analogy of the three energy systems.
- **Morton, R.H. (1986)** *"A three component model of human bioenergetics"*, *J Math Biol*, DOI 10.1007/BF01236892 — formalized three interconnected vessels; also *"Modelling human power and endurance"*, DOI 10.1007/BF00171518.
- **Sundström** — applied/validated hydraulic-analogy models (sprint roller skiing), showing they generalize across sports.
- **Weigend, Behncke & Skiba (2021)** — *"A new pathway to approximate energy expenditure and recovery of an athlete"* (arXiv 2104.07903) and the **`three_comp_hyd`** open-source implementation (github.com/faweigend/three_comp_hyd). Removes ties to concrete metabolic measures and **fits the 8 parameters per-athlete by evolutionary computation**.
- **Weigend et al. 2021** — *"A hydraulic model outperforms work-balance models for predicting recovery kinetics from intermittent exercise"* (arXiv 2108.04510) — direct head-to-head vs W′bal.

**The three vessels**
1. **Ae** — aerobic / oxidative (effectively large-capacity source, feeds the anaerobic tanks).
2. **AnF** — *anaerobic fast* = **phosphagen / PCr** tank (small, drains & refills fast).
3. **AnS** — *anaerobic slow* = **glycolytic / lactic** tank (larger, slower).

**Mechanics (conceptual equations).** Each vessel has a capacity (cross-section × height) and
liquid level `h`. Power demand `p(t)` sets the outflow. Flow between vessels is proportional to
the **difference in liquid levels** and gated by **tube height/position parameters** — so a tank
only refills once the level it draws from is high enough. The Weigend abstraction uses ~**8
parameters**: `{ AnF capacity, AnS capacity, Ae max flow (M_Ae), tube position φ (height of the Ae→AnF/AnS outlet), γ (AnS tube height), θ (positions/offsets of the anaerobic tank tops) }`, fitted per athlete.

**Why this family answers your question best**
- **Depletion is separated by construction**: PCr (AnF) drains first and fastest on any
  power transient; glycolytic (AnS) engages as AnF empties — reproducing the physiological
  sequencing without you hard-coding it.
- **Restoration is naturally multi-rate**: AnF refills quickly from Ae/AnS via its tube;
  AnS refills slowly — giving the fast/slow, power-dependent recovery that Family A's single τ
  misses. Weigend 2021 shows this **out-predicts W′bal for intermittent recovery kinetics**.
- Fully **power-driven**: the only time-series input is the power demand trace.

**Trade-off:** parameters are abstract (fitted, not directly measured), so mapping tank levels
back to "mmol PCr" or "mmol lactate" requires an extra calibration step (see §5).

---

## 4. Family C — Bioenergetic supply/demand ODE models (mechanistic, from power)

These write **metabolic rate** as *demand = supply*, with supply split into **explicit
alactic, lactic, and aerobic terms** — the most physiologically direct "PCr vs lactic from
power" formulation.

**Lineage:** di Prampero's energetics → Artiga Gonzalez et al. (VO₂ from power) → the
intermittent-cycling model below.

**Anchor paper (has a full state-space ODE system):**
**"Development and validation of a dynamic bioenergetic model for intermittent ergometer cycling"**,
*Eur J Appl Physiol* 2023, **PMID 37369795**, DOI **10.1007/s00421-023-05256-7** (PMC10638188).
14 trained cyclists; 17 parameters (14 fit by grey-box `nlgreyest`). Structure:

- **Demand** = principal cycling work `MR_work = a + b·P` (linear in measured power) + ventilation cost (~11% of MR) + accumulated-metabolite cost (~6.9% of MR) + resting metabolism.
- **Supply** = alactic + lactic + aerobic:

  - **Aerobic** — mono-exponential toward demand:
    `d(MR_aer)/dt = (MR_demand − MR_aer) / τ_aer`, with **τ_aer ≈ 25 s** (constrained 10–100 s, per di Prampero).

  - **Lactic (glycolytic)** — same error-signal/time-constant form but the error subtracts
    *both* current aerobic and lactic rates, and is damped by `0.8 × d(MR_aer)/dt`;
    **τ_la ≈ 12.5 s** (constrained 10–15 s, from Gastin's kinetics). Constrained ≥ 0.
    - **Fuel state = normalized muscle lactate `[mLa] ∈ [0,1]`** (0 = fully recovered, 1 = max accumulation).
    - **Depletion:** `[mLa]` accumulates at the (normalized) lactic rate.
    - **Restoration is power-gated:** removal ∝ `[mLa] × demand_factor`, where `demand_factor = 1` at rest and **falls linearly to 0 at the lactate threshold (LT1)**. → lactate clears fastest at low power and **stops clearing above LT1**. This is exactly a *power-driven* restoration law for the glycolytic tank.

  - **Alactic (phosphocreatine)** — an **instantaneous buffer**: it supplies whatever demand
    aerobic + lactic cannot, capped by `MR_max − MR_aer`.
    - **Fuel state = normalized alactic depletion `∈ [0,1]`** (0 = full PCr, 1 = empty).
    - **Restoration with a hysteresis/efficiency cost:** when the alactic rate goes *negative*
      (during low-power phases) the tank refills, but only a fraction `η` of the diverted energy
      becomes usable alactic store — cost `(1−η)`. This is the model's PCr-recovery law.

**Reported outputs (calibration targets):** anaerobic contribution ≈ 59.6 kJ / 75.6 kJ across
protocols; in the harder protocol the alactic state overshot to 1.12 and `[mLa]` to 1.21 (i.e.
the P2-fit capacities were exceeded by 12% / 21%).

**Stated limitations:** no aerobic **slow component** (→ under-predicts aerobic MR, over-predicts
anaerobic in long low-intensity recovery); a two-compartment lactate model and an `[mLa]`-dependent
τ were tried but made the system underdetermined — a caution for your own parameterization.

**Related dynamic model:** the **bi-exponential** reconstitution/expenditure of W′ in trained
cyclists, *Eur J Sport Sci* 2023, DOI 10.1080/17461391.2023.2238679 — a bridge between Family A
and the fast/slow (PCr-like vs glycolytic-like) two-component idea.

---

## 5. Synthesis — how to actually model PCr vs lactic from power

A pragmatic recipe combining the families, matched to "depletion & restoration":

1. **Two anaerobic tanks, power as the only time-series input** (Family B geometry, Family C laws):
   - **PCr tank (AnF):** small capacity (~PCr store); drains first on any `demand > aerobic supply`;
     refills fast, oxidatively, **efficiency-limited** (`η` hysteresis cost), with a
     **biphasic / pH-slowed** rate (τ_fast ~20–30 s, slowed by acidosis / repeated bouts).
   - **Glycolytic tank (AnS):** larger capacity; engages as PCr empties; **fuel state tracked as
     accumulated lactate `[mLa]`**; refills **slowly and power-gated** — fastest at rest, ceasing
     above LT1 (Family C law); half-time on the order of minutes.

2. **Aerobic supply as a mono-exponential toward demand** (`τ_aer ≈ 25 s`) sets how much of the
   demand the anaerobic tanks must cover — the coupling that makes depletion power-dependent.

3. **Depletion law:** at each instant, `demand(P)` is met by aerobic first, then PCr (instant
   buffer), then glycolytic — draining tanks in that order.

4. **Restoration laws (the part single-τ models get wrong):**
   - PCr: fast, oxidative, pH/efficiency-limited, and **slows across repeated bouts**.
   - Glycolytic: slow, and **only below LT1** (power-gated removal).

5. **Validate against** the CP/W′ reconstitution targets (37/65/86% at 2/6/15 min; half-time
   ~234 s) and, if you have lab data, 31P-MRS τ_PCr and blood-lactate kinetics.

**Reference implementations to start from:** `three_comp_hyd` (Weigend, Python, evolutionary
fitting) for the tank machinery; the *EJAP 2023* bioenergetic ODEs (§4) for the power→system laws;
GoldenCheetah's Froncioni–Clarke–Skiba integrator (§2) for a simple W′ baseline to benchmark against.

---

## 6. Annotated key references

**Critical Power / W′ (Family A)**
- Skiba et al. 2012, *MSSE* — original W′bal integral + τ_W′ = 546·e^(−0.01·D_CP)+316. **PMID 22382171**, DOI 10.1249/MSS.0b013e31824cfdc0.
- Skiba et al. 2015, *MSSE* — differential W′bal. DOI 10.1249/MSS.0000000000000226.
- Bartram et al. 2018, *IJSPP* — elite τ_W′ = 2287.2·e^(−0.01·D_CP)+286.9. DOI 10.1123/ijspp.2017-0356.
- Chorley & Lamb 2020, *Sports* — **review of all of the above**, PMC7552657, DOI 10.3390/sports8090123.
- Clarke & Skiba 2013, *Adv Physiol Educ* — rationale / teaching of the power–duration model.

**Hydraulic tank models (Family B)**
- Morton 1986, *J Math Biol* — three-component model. DOI 10.1007/BF01236892.
- Morton, *"Modelling human power and endurance"*, *J Math Biol*. DOI 10.1007/BF00171518.
- Weigend, Behncke, Skiba 2021 — abstract three-component hydraulic model, arXiv 2104.07903; code: github.com/faweigend/three_comp_hyd.
- Weigend et al. 2021 — hydraulic vs W′bal for recovery kinetics, arXiv 2108.04510.
- Sundström et al. 2021 — hydraulic-analogy validity/reliability (roller skiing), ResearchGate 354553483.
- "Individualized physiology-based digital twin… reinterpretation of Margaria–Morton", *Sci Rep* 2024, DOI 10.1038/s41598-024-56042-0 (PMC10915161).

**Bioenergetic supply/demand ODEs (Family C)**
- Dynamic bioenergetic model, intermittent cycling, *EJAP* 2023 — **PMID 37369795**, DOI 10.1007/s00421-023-05256-7 (PMC10638188). *(Primary mechanistic source for §4.)*
- Bi-exponential reconstitution/expenditure of W′, *EJSS* 2023, DOI 10.1080/17461391.2023.2238679.
- Evaluating bioenergetic pathway contributions single→multiple sprints, *Sci Rep* 2024, DOI 10.1038/s41598-024-78916-z.
- Dynamic model of bioenergetics / grey-box VO₂-from-power (Artiga Gonzalez et al.).

**PCr / glycolytic depletion & restoration kinetics (physiology to calibrate against)**
- Harris et al. 1976 — biphasic PCr resynthesis (fast t½ ≈ 20–22 s), *Pflügers Arch*.
- Yoshida et al. 2013, *Scand J Med Sci Sports* — τ_PCr by muscle, **PMID 23662804**, DOI 10.1111/sms.12081.
- Proton-efflux / acidosis effect on τ_PCr, *AJP Cell* 2007, DOI 10.1152/ajpcell.00023.2007.
- di Prampero & Ferretti 1999 — anaerobic energetics reappraisal, **PMID 10647856**, DOI 10.1016/S0034-5687(99)00083-3.
- MAOD / anaerobic capacity measurement, *Sports Med* 1993, DOI 10.2165/00007256-199315050-00003; single-effort cycling split DOI 10.1038/srep42485.

---

*Notes on sourcing:* full text of PMC10638188 and PMC7552657 was retrieved via PubMed Central;
their typeset equations were embedded as images, so the closed forms in §2 and §4 are the
standard published forms cross-checked against the surviving prose (variable definitions, the
"+316 W" asymptote, the τ constraints and values). Verify exact coefficients against the
publisher PDFs before hard-coding.
