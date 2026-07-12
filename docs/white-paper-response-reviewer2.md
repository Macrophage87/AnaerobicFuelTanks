# Response to Reviewer 2 (`reviewer2reportdualtankv0.3.md`)

*Reply to Reviewer 2's report on v0.3 (recommendation: major revision). Bugs M1–M5 are fixed, the
strategic questions S1–S2 are answered in the paper, the editorial items are done, and the load-bearing
citations were verified against the primary sources — resolving both flagged risks positively. A
companion reply to the round-3 structural review is in `white-paper-response-round3-review.md`.*

---

## Major issues (§2)

| # | Issue | Verdict | Fix |
|---|---|---|---|
| M1 | "A 10 s sprint empties `C_p`" is false; `τ_dep` is an uncalibrated emergent kinetic | **Confirmed** | Prose fixed to ~20–30% residual (matches Bogdanis); `τ_dep = C_p/P_p_max` added to §7 |
| M2 | Effective `τ_p` is 27.6 s, not the advertised 22 s (`η` inflation) — delete `η` | **Confirmed** | `η` removed; `τ_p = 27 s`; `eta` key kept at 1.0 identity, dropped from the estimator fit |
| M3 | Deficit repayment ungated by LT1, defeating the gate it should respect | **Confirmed** | `D` now clears only below LT1, on the same gate as `R_g` (verified: unchanged at 0.9·CP) |
| M4 | Two divide-by-zero paths (`C_p = 0`; `total_rate = 0`) | **Confirmed** | Both guarded, both codebases |
| M5 | §6.7 promises `f_p` calibration the paper proves impossible | **Confirmed** | §6.7 scoped to `P_p_max`/τ's; `f_p` needs test-4 data or stays assumed |

- **M1.** Your recollection was right and it matters: Bogdanis 1996's "near-fully used in 10 s" refers to
  *sprint 2* (from 78.7% recovered), while a *fresh* 30 s sprint reaches PCr ≈ 16.9%. So the model's
  ~20% residual at 10 s *matches* the time-course; the "empties `C_p`" prose was wrong and is withdrawn.
  The emergent depletion kinetic `τ_dep = C_p/P_p_max` (≈ 4–13 s across riders) is now named in §7 as an
  equally load-bearing, equally assumed quantity that had been invisible.
- **M2.** Fully accepted. `η = 0.80` silently made the effective recovery constant ≈ 27.6 s while the
  table advertised 22 s — a 25% misstatement of the number the whole recovery-novelty case rests on.
  `η` deleted; `τ_p = 27 s` set as the honest default; the `eta` settings key remains at 1.0 (identity)
  for backward compatibility and is dropped from the estimator's fitted vector (removing the degeneracy).
- **M3–M4.** One-liners, both done. `D` is supra-cap byproduct load, so it now respects the LT1 gate
  like the glycolytic tank; and `C_p > 0` plus the share-denominator are guarded (a NaN on a head unit
  is unrecoverable mid-ride, as you note).
- **M5.** Correct — a sprint-then-hold without early recovery sampling cannot fit `f_p`. §6.7 is now
  scoped to `P_p_max` and the τ's; `f_p` is explicitly *not* a routine calibration target and needs
  test-4-class data or stays assumed.

## The strategic objection (§3)

- **S1 — recovery-only null model.** Accepted as the key open question. §7 now states it explicitly: a
  **single reserve that depletes exactly as W′bal and recovers bi-exponentially** (fast `τ_p` +
  LT1-gated slow `τ_g`, split `f_p`) produces the same two bars in recovery, the same divergence from
  Skiba, and none of the rate caps / spill / deficit / guards that generated three rounds of bugs. The
  paper now either must justify the depletion machinery against this null or adopt it; for a data field,
  §8 leans toward the leaner model, keeping the caps only for the (least-identifiable) live-consumption
  output and the genuine CK-flux constraint.
- **S2 — test 6 tests the recovery law, not the two-compartment hypothesis.** Correct and sharp. Since
  depletion is single-tank by construction, the only lever to beat single-tank on intermittent tolerance
  is the recovery shape (bi-exponential + LT1 gate). §6.6 now says so, and adopts your protocol
  refinement: choose recovery-valley powers that **straddle LT1**, where the two recovery laws diverge
  most.
- **"No evidence yet."** Your observation that the individually-acknowledged caveats sum to a stronger
  conclusion — *as of v0.4 there is no evidence, of any kind, that the second bar beats single-tank
  W′bal* — is now stated plainly in the Scope box, §7, and §8, rather than gestured at.

## Minor / editorial (§4)

All done: the ~8 "`f_p` is assumed" disclaimers are consolidated into one **Scope and status** box;
the changelog parentheticals moved to `white-paper-CHANGELOG.md`; the **synthetic battery results** are
now a table in §4.4 (not an unshown claim); `g_pmax` naming fixed (`g_rate` = ratio 0.5, `g_pmax` =
`g_rate·P_p_max` = power); the free-parameter count is stated (nine free — the same size as the
hydraulic model, but literature-set not fitted, which §3 now frames as the actual trade).

## Citations (§5) — both load-bearing risks verified, and they resolve

You flagged these as needing verification "before publication," correctly. I checked them (via PubMed):

- **Bogdanis 1996** — verified: PCr **16.9%** at the end of a fresh 30 s sprint; "near-full by 10 s" is
  *sprint 2*. This *supports* the M1 residual and confirms the "empties `C_p`" prose was wrong.
- **The reconstitution recovery power** — the 37/65/86% curve is **Ferguson et al. 2010** (DOI
  10.1152/japplphysiol.91425.2008), measured at **20 W** recovery per Chorley & Lamb 2020. This resolves
  the `τ_g` confound in favour of the passive-rest fit (`τ_g ≈ 520`). Ferguson also cautions that W′
  recovery is *not* a unique function of PCr or lactate — now cited as an honesty anchor.
- **Alactic fraction 0.20–0.30 (the `f_p` anchor)** — di Prampero & Ferretti 1999 (DOI
  10.1016/s0034-5687(99)00083-3; alactic O₂-debt t½ ≈ 30 s ↔ `τ_p ≈ 27 s`) and Bangsbo 1990 (~20%). With
  the recovery power now known, the reconstitution curve *independently* implies `f_p ≈ 0.20–0.25`, so
  the anchor no longer rests on a single citation — the two lines converge. Written up as new §4.1a.

**Net:** the two highest-stakes citations you flagged both survived contact with the primary sources,
and one (`τ_g`) turned a flagged assumption into a calibrated value.

---

## On the recommendation

Reviewer 2's core challenge — *does the depletion machinery earn its complexity, and is the recovery
law alone enough to win the decisive test?* — is now the explicit subject of §7 (the null model) and
§6.6 (a recovery-law test). The paper takes the position it was avoiding: for a Connect IQ data field,
ship the heuristic with these fixes; the depletion caps are retained for a genuine flux constraint and
the live-watts output, flagged as the least-identifiable part. The remaining open item is empirical, not
editorial: run §6.6.
