# Response to the critical review of the Dual-Tank white paper

*Companion to `white-paper-dual-tank-anaerobic-model.md`. Records how each review concern was
handled — accepted, and where the review itself was sharpened or pushed back on. Quantitative
claims were checked by simulating the actual model before acting.*

---

## Summary

The review's core verdict — *"an assumed decomposition presented as recovered physiology, and the
one quantitative validation target it names is both un-hittable by the defaults and blind to the
feature that matters"* — was largely correct, and several of the flagged inconsistencies were ones
introduced by the earlier parallel-draw change. Two points required **model/code** changes; the rest
were **white-paper** revisions. Two points were **sharpened** rather than complied with verbatim.

| # | Concern | Verdict | Where fixed |
|---|---|---|---|
| 1 | §4.2 ("recovery pins the split") contradicts §7 ("f_p assumed") | **Accepted** | §4.2, §7 |
| 2 | §6.3 reconstitution target is blind to the fast (PCr) tank | **Accepted** | §6.3, §6.4 |
| 3 | Default parameters don't reproduce §6.3 (~53% vs 37% at 2 min) | **Accepted (verified)** | §6.3, default `f_p` 0.35→0.25 |
| 4 | "Strict generalization of W′bal" overstated | **Accepted** | §4.4, §8 |
| 5 | §6.2 backward-compat test fails in recovery by construction | **Accepted** | §6.2 |
| 6 | "Lightweight middle ground" oversells parameter economy | **Accepted** | §3 |
| 7 | `P_p_max` defined two incompatible ways (0.5·P₅ₛ vs P₁ₛ) | **Accepted** | §4.1 |
| 8 | `η` is a τ-rescale mislabeled as hysteresis | **Accepted** | §4.1, §7 |
| 9 | 50/50 asymptotic draw + glycolytic has no rate cap | **Accepted (code)** | model + §4.1/§4.2 |
| 10 | `LT1` as a fixed %CP is a weak default | **Accepted** | §4.1, §4.2, §7 |
| 11 | 31P-MRS can't validate PCr in real cycling | **Accepted** | §6.5, §7 |
| 12 | No falsifiability; needs intermittent head-to-head vs single-tank | **Accepted** | §6.6 |
| 13 | "Two numbers a rider races on" overstated | **Accepted, sharpened** | §7, §8 |
| — | Revise default `f_p` down to ~0.15 | **Sharpened → 0.25** | §4.1, §7 |

---

## Accepted — required model/code changes

### 9. Glycolytic rate cap and the 50/50 split
The parallel draw used `share_p = need/(1+g)`, giving a 50/50 split at full activation and — worse —
`take_g = min(share_g, R_g)` with **no rate cap**, so once `g→1` the glycolytic tank could absorb an
arbitrarily large one-second demand. Both contradict §2 ("PCr is the highest-power source; glycolytic
has lower peak power").

**Fix (both codebases):** glycolytic peak rate `g_pmax = 0.5·P_p_max` (PCr is the higher-power
system); demand split in proportion to *available rate* (`P_p_max : g_pmax·g`); **both** tanks
rate-capped. Result: ~2:1 PCr-weighted steady-state split, glycolysis bounded. Verified:

```
450 W effort:  PCr 181 W / Gly 14 W at t=0  →  131 W / 64 W at t=20 s   (PCr-weighted, both draining)
1200 W effort: Gly capped at 345 W once PCr tank empties (was: unbounded)
```

### 3 + f_p default. The defaults don't reproduce the reconstitution curve
Simulated the actual model (full depletion → recovery) against Chorley–Lamb (37/65/86% at 2/6/15 min):

| `f_p` | recovery @2 min (P=0) | @2 min (realistic ~0.4·CP) |
|---|---|---|
| **0.35 (old)** | **0.53** | 0.45 |
| 0.25 (new) | 0.46 | 0.36 |
| 0.15 | 0.39 | 0.28 |

The review's ~53%-vs-37% overshoot is confirmed. Structural reason: putting 35% of W′ in a tank that
is ~fully recovered by 2 min forces combined 2-min recovery above 35%. The curve pulls `f_p` **down**.
Default revised **0.35 → 0.25** (see sharpening note below).

---

## Accepted — white-paper fixes

- **1 · §4.2 ↔ §7 contradiction.** Committed to the §7 position: the split is **assumed and weakly
  constrained**, not recovered from power. In principle recovery constrains it; in practice the fit is
  ill-conditioned (the fast component is invisible at standard sampling — see #2), so `f_p` is an
  assumption. Removed "measured latent state" language.
- **2 · §6.3 blind to the fast tank.** A `τ_p ≈ 22 s` process is 99.6% complete by the first (2-min)
  reconstitution sample, so passing §6.3 validates glycolytic recovery and the *size* of the PCr
  offset — not PCr kinetics, the feature that distinguishes this from W′bal. Stated explicitly; added
  a dedicated early-recovery (10/20/30/45/60 s) test for `τ_p`.
- **4 · "Strict generalization."** Softened: a faithful generalization **in depletion**
  (`take_p+take_g = need`), but recovery is deliberately different, and `f_p→0` gives a single
  *glycolytic* tank with an LT1 gate — not standard W′bal. Structure/depletion generalization, not a
  strict superset.
- **5 · §6.2 backward-compat.** Rescoped to **depletion only**; agreement in recovery is not expected
  (a test the model is designed to "fail" was removed).
- **6 · "Lightweight."** Reframed: core parameter count (~9) ≈ the hydraulic model's 8 — *not* smaller.
  The difference is that all but `CP`/`W′` are literature-fixed defaults, and the load-bearing ones
  (`f_p`, `P_p_max`, `LT1`, τ's) are exactly what a CP test doesn't determine. Named as an
  identifiability-for-convenience trade.
- **7 · `P_p_max` double definition.** Removed the `0.5·(P₅ₛ − CP)` table entry; standardized on
  `P₁ₛ − CP`, with a note that at 1 s glycolysis is already ~15% active so this mildly over-attributes
  to PCr (read as an upper bound).
- **8 · `η`.** Relabeled honestly: it rescales the effective recovery constant to `τ_p/η` (asymptote
  still full recovery ⇒ no hysteresis), is **degenerate with `τ_p`** when fitted, and a true
  efficiency loss would need an asymptote below `C_p`. Flagged as a redundant knob.
- **10 · `LT1`.** Reframed as a **measured** first-lactate-threshold power, not a fixed %CP (LT1 is
  ~65–85% of CP and independent of it; it gates whether the glycolytic tank recovers during tempo).
  `0.80·CP` demoted to a flagged fallback.
- **11 · 31P-MRS.** Stated plainly (§6.5, §7) that the PCr gold standard is unavailable in real
  cycling — it needs the muscle in a magnet, so only knee-extension or immediate post-exercise — so
  the headline feature can't be checked in-modality.
- **12 · Falsifiability.** Added §6.6: because the model is a near-superset in depletion, "fits
  better" is guaranteed and proves nothing. The decisive test is an **out-of-sample intermittent
  tolerance** head-to-head vs single-tank (the protocol class where the hydraulic model beat W′bal).

---

## Sharpened / pushed back

- **13 · "Two numbers a rider races on."** The affine-transform argument is correct — when `R_p ≈ C_p`
  (most of the time), the glycolytic bar is a rescaling of the existing single W′bal, so the PCr bar
  adds information *only* in the ~30–60 s after a hard effort. Accepted and softened to "a heuristic
  decomposition whose split is assumed." **But** those post-surge transients are precisely where race
  pacing decisions concentrate (can I cover this attack right after the last one?), and a data field
  can drive an alert/colour, not only a glance-read gauge — so the extra resolution is real, just
  temporally concentrated. Noted alongside the limitation rather than conceding pure redundancy.
- **Default `f_p` → 0.25, not ~0.15.** The review's direction (down from 0.35) is robust, but the
  reconstitution curve only *weakly* pins `f_p`: it's confounded with `τ_g` and dominated by the slow
  tank, so the implied value swings from ~0.13 (passive rest) to ~0.25 (realistic soft-pedal
  recovery), and a single slow exponential can't fit all three Chorley–Lamb points anyway.
  Physiological alactic-fraction-of-W′ estimates sit at ~0.20–0.30. I set **0.25** as a
  physiologically-anchored, reconstitution-consistent default and documented the full ~0.15–0.35 band
  rather than committing to a falsely precise single number.

---

## What the review got right (retained strengths)

The fuel-vs-byproduct distinction in §2 (PCr = depletable substrate; glycolytic "tank" = tolerance to
Pi/H⁺/K⁺ accumulation; lactate as marker/fuel; glycogen excluded on this timescale), the Parolin-
grounded activation ramp, the exact-ODE recovery discretization, the parallel (not sequential) draw
with the explicit non-identifiability note, and the realistic on-device framing were all endorsed and
left intact.
