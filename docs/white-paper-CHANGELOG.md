# Changelog — Dual-Tank white paper & model

Revision history for `white-paper-dual-tank-anaerobic-model.md` and the model implemented in
`connectiq/source/DualTankView.mc` and `tools/calibrate/app.R`. Full point-by-point review responses
live in `white-paper-review-response*.md`.

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
- **Flagged `τ_g`, `τ_off`, and `τ_dep = C_p/P_p_max` as assumptions** (`τ_g` is protocol-confounded up
  to 2×; Parolin measured activation, not de-activation; `τ_dep` is an emergent, uncalibrated
  depletion kinetic). Added a "Scope and status" box; scoped §6.7 (`f_p` not a routine fit target);
  reframed §6.6 as a test of the *recovery law*; added the recovery-only null-model question (§7).

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
