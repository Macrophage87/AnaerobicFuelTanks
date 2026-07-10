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

**The ordering that matters.** At any instant, demand not met by aerobic supply is met **PCr
first, then glycolytic.** This sequencing — and the very different refill rates — is exactly what
the dual-tank model must reproduce.

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
systems but are too heavy to run and calibrate on a head unit. The dual-tank model below is the
reduction that keeps the two-tank resolution of B/C with the on-device simplicity of A, using
only parameters a rider can obtain from a standard CP test plus sensible physiological defaults.

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
| `f_p` | fraction of W′ assigned to the PCr tank | 0.35 (modeling choice — see §7) |
| `P_p_max` | max power the PCr tank can deliver (W) | ≈ 0.5·(peak 5 s power − CP) |
| `τ_p` | PCr recovery time constant (s) | 22 (fast, pH-modulated) |
| `τ_g` | glycolytic recovery time constant (s) | 360 (slow) |
| `LT1_frac` | fraction of CP below which glycolytic recovery is enabled | 0.80 |
| `η` | PCr recovery efficiency (hysteresis) | 0.80 |

Derived: `C_p = f_p·W′`, `C_g = (1 − f_p)·W′`. Initial state `R_p = C_p`, `R_g = C_g` (full).

### 4.2 The 1 Hz update

Let `P` be instantaneous power (W) and `Δt = 1 s`. Define the demand relative to aerobic supply
as `Δ = P − CP`.

**Case 1 — depletion (`Δ > 0`, above CP).** Demand `need = Δ·Δt` (J) is met PCr-first, glycolytic-second:

```
take_p = min(need, R_p, P_p_max·Δt)     # PCr covers as much as it can, rate-limited
R_p   -= take_p
need  -= take_p

take_g = min(need, R_g)                  # glycolytic covers the remainder
R_g   -= take_g
need  -= take_g

if need > 0:  exhaustion = true          # both tanks empty → rider at/over the limit
```

**Case 2 — restoration (`Δ ≤ 0`, at/below CP).** Recovery "headroom" is `CP − P`. Each tank
refills exponentially toward full; glycolytic refill is gated by intensity.

```
# PCr: fast, oxidative, efficiency-limited
R_p += η · (C_p − R_p) · (1 − exp(−Δt/τ_p))

# Glycolytic: slow, only meaningfully below LT1
if P < LT1_frac · CP:
    gate = (LT1_frac·CP − P) / (LT1_frac·CP)     # 0 at LT1, → 1 toward zero power
    R_g += gate · (C_g − R_g) · (1 − exp(−Δt/τ_g))
```

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

- A short, very hard surge draws almost entirely from `R_p` (rate-limited glycolytic engagement),
  and `R_p` visibly refills within ~30–60 s of easy pedaling — matching PCr physiology.
- A sustained supra-CP effort empties `R_p` quickly, then bleeds `R_g`, which only comes back over
  minutes and only when the rider drops below LT1 — matching glycolytic physiology.
- With `f_p → 0` (or by summing the tanks) the model collapses to a single-tank W′bal, so it is a
  strict generalization of the incumbent.

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

The model is a hypothesis; it must be checked against data before its numbers are trusted.

1. **Face validity / unit tests** — synthetic power traces (single sprint, repeated sprints,
   supra-CP hold, sub-CP recovery) should produce the qualitative behaviours in §4.4.
2. **Backward compatibility** — summing the tanks must reproduce a reference W′bal implementation
   (Froncioni–Clarke) on the same trace to within numerical tolerance.
3. **Reconstitution targets** — after a full W′ depletion, combined recovery should approximate the
   published curve (≈37% / 65% / 86% at 2 / 6 / 15 min; half-time ~234 s; Chorley & Lamb 2020).
4. **System-specific truth (lab)** — where available, compare PCr-tank recovery against 31P-MRS
   τ_PCr and glycolytic-tank state against blood-lactate kinetics.
5. **Field calibration** — fit `f_p`, `P_p_max`, and `τ` per athlete to maximal-effort tests
   (e.g. a sprint-then-hold protocol) rather than trusting defaults.

---

## 7. Assumptions and limitations

- **The PCr/glycolytic split fraction `f_p` is a modeling choice,** not a directly measured
  quantity; 0.35 is a reasonable default but should be personalized. Results are sensitive to it.
- **Fixed time constants** ignore the documented pH-dependence and bout-to-bout slowing of PCr
  recovery unless the optional fatigue term is enabled.
- **Hard CP boundary** omits the aerobic slow component and onset kinetics unless the optional
  aerobic-ramp term is enabled; expect over-attribution to anaerobic tanks in long low-intensity
  recovery (the same failure mode reported for the EJAP 2023 model).
- **Power is whole-body and mechanical**, not muscle-specific; the model cannot see local fatigue,
  cadence, or fiber-type effects.
- **Not medical or diagnostic.** This is a training/pacing aid; tank levels are estimates, not
  measurements of muscle chemistry.
- **Parameters from a single CP test drift** with fitness, fatigue, heat, and altitude; periodic
  re-testing is required.

---

## 8. Conclusion

The single-tank W′ model earned its place by being power-native and light enough to run anywhere,
but it answers "how much anaerobic work is left?" without answering "in which system?" The
dual-tank model proposed here restores that resolution at negligible computational cost: split
W′ into a fast, rate-limited, fast-recovering PCr tank and a slow, large, slowly-recovering
glycolytic tank; drain them PCr-first from the power trace; and refill them with system-specific,
intensity-gated laws. It is a strict generalization of W′bal, it runs at 1 Hz on a Garmin head
unit, and it produces the two numbers a rider actually races on — punch left, and dig left. The
accompanying Connect IQ specification turns it into a live data field; the open questions are
calibration (`f_p`, per-athlete τ) and field validation against system-specific lab measures.

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

*Sourcing note:* equations for the incumbent models were cross-checked against PubMed Central
full text (PMC7552657, PMC10638188); typeset equations there were image-embedded, so published
closed forms were reconstructed from the surviving prose and standard literature. Verify exact
coefficients against publisher PDFs before hard-coding.
