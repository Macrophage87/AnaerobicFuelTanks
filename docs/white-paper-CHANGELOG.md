# Changelog — Dual-Tank white paper & model

Revision history for `white-paper-dual-tank-anaerobic-model.md` and the model implemented in
`connectiq/source/DualTankView.mc` and `tools/calibrate/app.R`. Full point-by-point review responses
live in `white-paper-review-response*.md`.

## v0.6 — 2026-07-12 (training-load use case)
- **Added §6.9 — training-load partitioning.** The reviews evaluated the model as a *pacing* aid; this
  adds the *training* use case, where the cumulative per-system load (already recorded as
  `PCr_depleted_kJ`/`GLY_depleted_kJ`) distinguishes an alactic session (~76% PCr) from a glycolytic one
  (~41%) via the activation ramp. W′bal (one number) and the recovery-only null (fixed `f_p` every
  session) both structurally lack this — so it is the strongest standalone argument for the second tank,
  and gives the depletion machinery a purpose the reviews did not credit. Motivated by the asymmetric
  recovery cost of alactic vs glycolytic work. No code change (the FIT fields already record it).

## v0.5 — 2026-07-11 (review round 4 / Reviewer 2 2nd / Reviewer 3)
- **PCr recovery gated by oxidative headroom** `gate_p = (CP−P)/CP` (both codebases) — fixes the
  headline bug (PCr no longer refills at full rate while the rider is under load). After a 700 W/20 s
  effort, 60 s recovery now gives 87% @0 W but 46% @0.8·CP and 25% @0.99·CP (was a flat 92%).
- **`τ_g` 520 → 470** (Ferguson recovered at 20 W ⇒ gate ≈ 0.90, and the true joint optimum is
  `(f_p 0.20, τ_g 470)`, SSE 10.7). Deleted the stale §6.3(b) fossil; downgraded "corroborated by two
  independent lines" → "consistent with (the curve constrains a `(f_p, τ_g)` ridge; physiology selects)."
- **Exhaustion flag split** into genuine `exhausted` (tanks ≈ 0) vs `rate_limited` (unmet > 0).
- **Confronted the Ferguson component mismatch** (§4.1a): model half-times 18.7 s / 326 s vs Ferguson's
  74 s / 1366 s (~4× each) while the aggregate fits, and Ferguson concludes the decomposition can't be
  done — now hosted as the strongest datum in the paper, not a footnote.
- **First empirical results (§6.8)** on six real interval rides: PCr bar informative (<95%) ~45% of
  ride time (20–79%); dual-tank vs recovery-only null diverges up to ~25–60 pts at recovery-valley
  starts — answering the null-model challenge (S1/point 1/point 7) with data.
- **Answered S1**: caps earn their keep only in the maximal regime; per-system live consumption is
  `(power−CP)` rescaled → relabelled "modelled share," not a reading. `τ_p = 27` re-justified from
  31P-MRS (not "22 inflated by η"). `τ_dep` residual reported across its 4–13 s range (not just centre).
  Scope box narrowed (both bars affine in W′bal); falsification-test reframed; hard epistemic boundary
  (compartments unfalsifiable in-modality) stated; consistency pass on stale strata; `P_p_max` added to
  settings; battery parameter set published; drawdown relabelled front-loaded (not linear).

## v0.4 — 2026-07-11 (review round 3 / Reviewer 2)
- **Decoupled the share weight from the rate ceiling.** Submaximal supra-CP demand is now split by
  **capacity** (`w_p = C_p`, `w_g = C_g·g`); the peak-flux **ceiling** (`P_p_max` tapered by fullness,
  `g_pmax`) governs maximal efforts only. Fixes the intensity-*invariant*, convex PCr trajectory (PCr
  was ~9% by the midpoint of any hard effort) without changing the sprint case (ceiling-dominated).
- **Withdrew the false "a 10 s sprint empties `C_p`" claim** (§4.4). Under the taper the residual is
  ~20–30%, which actually matches Bogdanis 1996 (PCr ≈ 17% at 30 s).
- **Removed `η`.** It only rescaled the effective PCr recovery constant (to `τ_p/η`, ≈ 27.6 s) while the
  table advertised 22 s. Set `τ_p = 27 s`; `eta` settings key retained at 1.0 (identity) for
  compatibility and dropped from the estimator's fitted set.
- **LT1-gated the deficit repayment** — `D` now clears only below LT1, like the glycolytic tank.
- **Guards:** `C_p > 0` (rate taper divides by it) and `w_p + w_g > 0` (share denominator).
- **Flagged `τ_off` and `τ_dep = C_p/P_p_max` as assumptions**; added a "Scope and status" box; scoped
  §6.7 (`f_p` not a routine fit target); reframed §6.6 as a test of the *recovery law*; added the
  recovery-only null-model question (§7).
- **Literature verification (§4.1a) — two open items resolved.** Confirmed (via PubMed) that the
  37/65/86% reconstitution curve is Ferguson et al. 2010 measured at **20 W (near-passive) recovery**,
  so `τ_g = 520` is calibrated, **not** confounded to ~260 s; and that the same curve, once its recovery
  power is known, corroborates `f_p ≈ 0.20–0.25`, converging with the physiological alactic fraction.
  Noted Ferguson's caution that W′ recovery is not a unique function of PCr/lactate.

## v0.3 — 2026-07-11 (review round 2)
- Fullness-tapered PCr flux (PCr reaches nadir at exhaustion, not ~37.5% of TTE).
- Deficit accumulator `D` — combined `(R_p+R_g−D)` conserves energy when rate caps bind.
- `τ_g` 360 → 520 s (least-squares to the Chorley–Lamb reconstitution curve); `f_p` re-anchored on
  physiology, not reconstitution. Documented the `g` de-activation.

## v0.2 — 2026-07-11 (review round 1)
- Parallel PCr + glycolytic draw with a glycolytic activation ramp (`τ_on ≈ 6 s`, Parolin 1999),
  replacing the sequential PCr-first draw. Added the glycolytic rate cap; `f_p` 0.35 → 0.25;
  `P_p_max` from 1 s peak. Reconciled the identifiability claims; validation section rewritten.

## v0.1 — 2026-07-10
- Initial dual-tank proposal: W′ split into a fast PCr tank and slow glycolytic tank, sequential draw,
  system-specific recovery, Connect IQ implementation, validation strategy.
