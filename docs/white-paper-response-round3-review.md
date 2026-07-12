# Response to Critical Review, Round 3 (`whitepaperreviewround3.md`)

*Reply to the round-3 structural review of v0.3. Every finding was re-derived by simulation before
acting; the full synthetic battery was re-run afterward. All four findings **accepted and fixed** in
v0.4; the "when to stop" fork is answered in §7/§8; finding D is now **resolved** by verifying the
primary source. A companion reply to Reviewer 2 is in `white-paper-response-reviewer2.md`.*

---

## The shared diagnosis (this review's central insight)

You identified the root cause behind three rounds of patches: the model used **one rule to do two
incompatible jobs** — `share ∝ available rate` was asked to both (i) produce PCr dominance in
*maximal* sprints and (ii) apportion demand in *submaximal* supra-CP efforts. A single weight cannot do
both, and every pathology (the 50/50 asymptote, the 37.5% flat-line, and this round's convex
intensity-invariance) was a symptom of that conflation. This is correct, and it is the fix.

**Implemented (both codebases), exactly as you proposed:** weight the **share by capacity**
(`w_p = C_p`, `w_g = C_g·g`), keep the taper on the **rate ceiling**. Verified free in the sprint case:

| | v0.3 (rate-weighted) | v0.4 (capacity-weighted) |
|---|---|---|
| Sustained 450 W — PCr at 25/50/75/100% TTE | 37 / 8 / 1 / 0.1% (convex, pinned near 0) | **68 / 42 / 18 / ~1%** (near-linear) |
| Both tanks empty at exhaustion | no (0.2 / 0.7%) | **yes (~1% / ~0%)** |
| 945 W sprint — PCr after 10 s | 23% | **23% (bit-identical)** |

---

## Findings

| # | Finding | Verdict | Action |
|---|---|---|---|
| A | §4.4 Bogdanis claim ("empties `C_p`") false under the taper (≈23%) | **Confirmed** | Withdrawn; ~20–30% residual stated — which *matches* Bogdanis |
| B | PCr trajectory intensity-invariant; bar pinned at 7–11% by halfway | **Confirmed** | Fixed by capacity weighting; invariance re-stated as a testable prediction |
| C | Taper collapses the rate ceiling → spurious mid-effort deficits / false exhaustion | **Confirmed** | Ceiling no longer sets the share; flag renamed `rate_limited` |
| D | `τ_g = 520` confounded with the reference protocol's recovery power | **Confirmed → now RESOLVED** | Verified the source used 20 W recovery; `τ_g = 520` is calibrated |

### A — the Bogdanis claim
Correct, and it was my error: I ported a property (verified under v0.2's flat cap) into §4.4 in the
same revision whose taper destroyed it — the exact round-2 failure mode, recurring. Simulation
confirms ~23% residual at 10 s, not empty. **Withdrawn.** The residual actually *matches* Bogdanis 1996
better than "empty" (PCr ≈ 17% at 30 s), so the fix is to the sentence, not the model.

### B — intensity-invariance
Correct: at `g = 1` the v0.3 law gave `x + 0.5·ln(x) = 1 − φ/f_p`, independent of Δ/CP/W′. Capacity
weighting breaks it — PCr is now genuinely intensity-dependent (300 W → 73% vs 900 W → 32% at
quarter-TTE) while the sprint stays ceiling-dominated. The residual "both bars track W′bal in *steady*
submaximal effort" is real and now stated honestly as the consequence of capacity weighting (it is what
§1/§7 already claimed). Your point that the constant-power invariance is a **falsifiable prediction** is
taken: it's written into §4.4 (`x` as a function of %W′-spent), testable in an afternoon, and tied to
the reproducible-milieu literature.

### C — collapsed ceiling
Correct. Using `rate_p` as both share weight and rate cap made the model's belief about producible
power collapse as PCr drained, dumping mid-effort surges into `D` and firing exhaustion from a full
tank. Decoupling the ceiling from the share fixes it. The flag is split conceptually: `R_p + R_g ≈ 0`
is physiological exhaustion; `D` growing with full tanks is "the rate model can't explain this power —
usually a stale `P₁ₛ`," now labelled `rate_limited`, not `exhaustion`.

### D — the `τ_g` confound — **now resolved**
You were right that `τ_g = 520` inherited exactly the confound removed from `f_p` (LT1 gate →
effective `τ_g/gate`, so a 0.4·CP recovery would halve it to ~260 s). You named it the top open item,
correctly. **I checked the primary source:** the curve is Ferguson et al. 2010, and per Chorley & Lamb
2020 it was measured at a **nominal 20 W** (near-passive) recovery — `gate ≈ 1`. So the passive-rest fit
is correct and `τ_g ≈ 520 s` stands, calibrated, not confounded (new §4.1a). The confound was real; the
data resolves it in favour of the current default.

---

## "When to stop" — answered

Your closing framing (the model is converging on a structural limit; W′ is a cumulative capacity, PCr a
state variable) is the right lens, and I answer the fork explicitly in §7/§8 rather than discover it by
attrition. For a Connect IQ **data field**: **ship the heuristic** with this revision's fix, document
the invariance/limitation, and let §1/§7's framing stand. The re-architecture you sketch (PCr as a
state relaxing to a power-dependent equilibrium; glycolysis carrying the cumulative accounting) is the
right call for a model that *claims to track phosphocreatine* — but it abandons `W′ = C_p + C_g`, the
backward-compatibility identity, and most of §4. That is a different paper; §7 now states it as the
deliberate alternative.

**Process note, honoured:** the v0.4 synthetic battery (constant hold, interval set, supra-cap effort,
gated-`D` check, `f_p = 0` guard) was run end-to-end after every change, and its results are now *in*
§4.4 rather than asserted — because, as you noted, it is the joint behaviour that bites.
