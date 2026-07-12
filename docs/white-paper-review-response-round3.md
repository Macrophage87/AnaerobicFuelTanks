# Response to the critical reviews — Round 3

*Reply to two independent reviews of v0.3: `whitepaperreviewround3.md` and
`reviewer2reportdualtankv0.3.md`. Both converged on the same root cause, and both proposed the same
structural fix. Every claim was re-derived by simulation before acting; the full synthetic battery was
re-run after the changes. Result: the structural fix and all clear bugs are **accepted and
implemented** (v0.4); the two strategic questions are **answered** in §7/§8.*

---

## The shared diagnosis (both reviews, independently)

The model was using **one rule to do two incompatible jobs**: `share ∝ available rate` was asked to
both (i) produce PCr dominance in *maximal* sprints and (ii) apportion demand in *submaximal* supra-CP
efforts. A single weight can't do both. Every pathology across three rounds — the 50/50 asymptote, the
37.5% flat-line, and now the intensity-invariant convex PCr collapse — was a symptom of that
conflation.

**The fix both reviews proposed, and I implemented:** weight the **share by capacity** (`w_p = C_p`,
`w_g = C_g·g`), keep the taper on the **rate ceiling**. Verified — it costs nothing in the sprint case
and fixes the sustained case:

| | v0.3 (rate-weighted) | v0.4 (capacity-weighted) |
|---|---|---|
| Sustained 450 W — PCr at 25/50/75/100% TTE | 37/8/1/0.1% (convex, pinned near 0) | **68/42/18/~1%** (near-linear) |
| Both tanks at exhaustion | no (0.2 / 0.7%) | **yes (~1% / ~0%)** |
| 945 W sprint — PCr after 10 s | 23% | **23% (bit-identical)** |

---

## Review 3 (round 3) — findings

| # | Finding | Verdict | Action |
|---|---|---|---|
| A | §4.4 Bogdanis claim ("empties `C_p`") false under the taper (≈23%) | **Confirmed** | Withdrawn; ~20–30% residual stated, which *matches* Bogdanis |
| B | PCr trajectory intensity-invariant; bar pinned at 7–11% by halfway | **Confirmed** | Fixed by capacity weighting; invariance re-stated as a testable prediction |
| C | Taper collapses the rate ceiling → spurious mid-effort deficits/exhaustion | **Confirmed** | Ceiling no longer sets the share; exhaustion flag renamed `rate_limited` |
| D | `τ_g = 520` confounded with the reference protocol's recovery power | **Confirmed** | Flagged "assumed, not fitted"; named the single highest-value open item |

- **A / B:** the capacity-weight fix makes PCr genuinely intensity-dependent again (300 W → 73% vs
  900 W → 32% at quarter-TTE) while leaving the sprint ceiling-dominated. The residual invariance that
  remains at low intensity (both bars track W′bal in steady effort) is now stated as an honest
  consequence, and the constant-power invariance is written up as a **falsifiable prediction** (§4.4).
- **C:** decoupling the ceiling from the share removes the spurious deficits. The exhaustion boolean is
  split conceptually: `R_p+R_g ≈ 0` is physiological exhaustion; `D` growing with full tanks is "the
  rate model can't explain this power — usually a stale `P₁ₛ`," now labelled `rate_limited`.
- **D:** accepted in full. `τ_g` inherited exactly the confound removed from `f_p` in round 2 (the
  LT1 gate makes the effective constant `τ_g/gate`, so a 0.4·CP reference recovery halves it to ~260 s).
  Flagged throughout; §6.3(c) names it the top open item.

## Reviewer 2 — findings

| # | Finding | Verdict | Action |
|---|---|---|---|
| M1 | "empties `C_p`" false; `τ_dep` is an uncalibrated emergent kinetic | **Confirmed** | Same as A; `τ_dep = C_p/P_p_max` added to §7 as an assumed depletion kinetic |
| M2 | Effective `τ_p` is 27.6 s, not 22 s (`η` inflation) — delete `η` | **Confirmed** | `η` removed; `τ_p = 27 s`; dropped from the estimator fit |
| M3 | Deficit repayment ungated by LT1 | **Confirmed** | `D` now clears only below LT1 (verified: unchanged at 0.9·CP) |
| M4 | Two divide-by-zero paths (`C_p = 0`; `total_rate = 0`) | **Confirmed** | Both guarded, both codebases |
| M5 | §6.7 promises `f_p` calibration the paper proves impossible | **Confirmed** | §6.7 scoped to `P_p_max`/τ's; `f_p` needs test-4 data or stays assumed |
| S1 | A recovery-only null model may match the display with far less machinery | **Accepted (open Q)** | §7 states the null model and asks the machinery to justify itself |
| S2 | Test 6 is a test of the *recovery law*, not the two-compartment hypothesis | **Confirmed** | §6.6 reframed; protocol sharpened to straddle LT1 |

Editorial (all done): consolidated the ~8 "`f_p` is assumed" disclaimers into one **Scope and status**
box; moved changelog parentheticals to `white-paper-CHANGELOG.md`; added the **synthetic battery
results table** to §4.4; fixed `g_pmax` naming (`g_rate` ratio vs `g_pmax` power); stated the
free-parameter count (nine free; same size as the hydraulic model, but literature-set not fitted);
added the "no evidence yet, of any kind" statement to the Scope box, §7, and §8.

## Citations (Reviewer 2 §5)
- **Bogdanis 1996** — verified against the abstract: PCr **16.9%** at the end of a fresh 30 s sprint,
  "almost completely utilized in the first 10 s" refers to *sprint 2* (from 78.7% recovered). So the
  model's ~20% residual matches; the "empties `C_p`" prose was wrong and is withdrawn (confirms M1).
- **Alactic fraction 0.20–0.30** (the sole anchor for `f_p = 0.25`) and the **0.5 flux ratio** (di
  Prampero & Ferretti 1999) are flagged in-text as needing page/table-level primary-source
  verification — PubMed keyword search did not resolve them to a quotable figure here.

---

## The two strategic questions — answered

Both reviews end at the same fork (Review 3 "When to stop"; Reviewer 2 S1). I answer it in §7/§8
rather than leave it implicit:

**Ship the heuristic.** For a Connect IQ **data field**, the right call is to apply this revision's fix,
document the intensity-invariance as a limitation/prediction, and let §1/§7's framing stand. The paper
is already written for it. The re-architecture both reviews sketch — PCr as a *state variable*
relaxing toward a power-dependent equilibrium, glycolysis carrying the cumulative W′ accounting —
abandons `W′ = C_p + C_g`, the backward-compatibility identity, and most of §4. That is a different
paper, and the right call only if the goal is a model that *claims* to track phosphocreatine rather
than a shippable pacing display. §7 now states the recovery-only **null model** explicitly and asks the
depletion-side machinery to justify itself against it; §8 lands on "no evidence yet, of any kind" and
names the three things that would change that (de-confound `τ_g`; verify the alactic-fraction citation;
run the recovery-law head-to-head).

**Process note (again):** the round-2 lesson — the *joint* behaviour is what bites — held here too. The
v0.4 battery (constant hold, interval set, supra-cap effort, gated-D check, `f_p = 0` guard) was run
end-to-end after every change, and its results are now in the paper (§4.4) rather than asserted.
