# Response to Reviewer 3 (white paper v0.6 → v0.7)

Thank you for re-implementing the model and checking the two load-bearing time constants against primary
data. Both findings reproduced in my own simulation, and both are fixed — though `τ_p` is fixed by
*renaming* rather than recalibrating, for a reason your own report and Reviewer 2's converge on, spelled
out below. All numbers were re-derived before acting.

## M1. `τ_p = 27 s` vs Bogdanis — resolved by reframing, not recalibration, and here is why.

You are right that the fast-reserve bar recovers to ~100% by 2 minutes while Bogdanis's muscle PCr is
78.7% at 3.8 min, and that four independent data points imply `τ_p ≈ 80–170 s` at the *metabolite* level.
I tried your first fix — turning on the pH term with a calibrated `k`. To hit Bogdanis's 78.7% needs
`k ≈ 16`, and when I do that the model **breaks the two things it is actually calibrated to**: the
Ferguson W′ curve drops from 40/63/87 to 30/68/94, and the 4×4 goes to −30% at rep 4. That is not a tuning
accident — it is Reviewer 2's finding restated: **W′ recovers ~4× faster than the metabolites it is named
after** (built from Ferguson's own channel constants, a two-compartment model predicts 20/35/50% vs the
observed 37/65/86%). You cannot make the fast reserve track muscle-PCr recovery *and* W′ recovery with one
constant, because they are not the same quantity.

So v0.7 takes the resolution both your report and Reviewer 2's point at: the tanks are compartments of
**W′**, not of muscle. The τ's are the right constants for W′ (which is what the device displays and
Ferguson measures); the **metabolic naming** is what was wrong. §4.1 introduces fast/slow-reserve naming
with the metabolic identity as motivation; every "the bar equals biopsy PCr" claim is withdrawn —
**including** the flattering §4.4 "10 s sprint residual matches Bogdanis 17%," because, exactly as you
argue, one cannot use the muscle-PCr mapping where it passes and disown it where it fails. §4.1a now hosts
your r = 0.84–0.91 premise-support alongside the recovery gap, and states the honest split: the premise
(punch tracks a fast W′ reserve) is supported; the metabolite-level *number* is not the model's to claim.
**Bogdanis 1998 (PMID 9715738) is added** (fresh 10/20 s conditions), as are Bogdanis 1995 and Gaitanos
1993. The `m1` misattribution in §4.2 (a fresh 10 s sprint "leaves 20–30%, Bogdanis 1996") is corrected —
that residual is a fast-reserve-of-W′ level, not muscle PCr, and 1996's 10 s datum is the fatigued sprint 2.

## M2. The LT1 gate makes recovery 2–7× too slow and cannot complete a 4×4 — fixed with your prescription.

Confirmed: v0.6's linear `(LT1−P)/LT1` gate gives W′bal half-times of 675 s at 150 W and 2601 s at 190 W
(∞ at LT1), and the 4×4 goes 100/38/−23/−76%. I did exactly what you suggested — used Skiba's
`τ_W′(D_CP)` shape (already fitted across recovery powers) and re-anchored its amplitude on Ferguson at
20 W. Result: half-times **201/241/291/367 s** at 20/100/150/190 W — within ~15% of Skiba everywhere and
bounded — the Ferguson curve is unchanged (40/63/87), the sprint battery is bit-identical, and the **4×4
now completes: 100/49/7/−24%**. This is in both codebases (`app.R`, `DualTankView.mc`). And per your
warning, this is done *before* §6.6's test 6, so that experiment no longer measures the gate shape.

## M3. §6.9's discriminator is the ceiling, and it loses to a stopwatch — both accepted.

Ablation reproduces (full 77% → no-ramp 52% → no-ceiling 47% → neither 25%): the ceiling, scaled by the
ramp, does the work, not the ramp alone. §6.9 is rewritten accordingly. And you are right that the honest
baseline is not W′bal but a zero-parameter stopwatch — "% of supra-CP work in efforts <15 s" separates
100% vs 0%. §6.9 now states this, retracts "W′bal cannot tell these apart — it is one number," and reframes
the open question as *does the per-system load carry information beyond duration and intensity* (regress
against a duration/intensity baseline; if R² > 0.9 it is an expensive stopwatch).

## M4. §6.9 silently discards the deficit — fixed. M5. Non-monotone / turnover labeling — stated.

`D` is now reported as a third column in §6.9, and the split is refused when `D` is a large fraction of
total — with your 4×4 example (45% booked to `D`) called out. On M5: §6.9 now defines the metric as a
share of cumulative *turnover*, not of capacity, and notes the tension with the `f_p` capacity fraction —
so a reader will not read the two numbers as contradictory. (The full non-monotone-in-duration table is
acknowledged as a consequence of turnover + deficit rather than reproduced line-by-line.)

## M6. Headline swings on `τ_on`/`g_rate` — flagged. M7. `gate_p` half-fix and shape — flagged.

`g_rate` is promoted to load-bearing/flagged/banded (§4.1, §7); `τ_on` sensitivity is acknowledged.
`gate_p` is added to the §4.1 table and §7 with its shape sensitivity (linear/√/sigmoid = 46/65/34% at
LT1, a 21–31 pt swing). And M7b is stated plainly: the gate scales the refill, adds no sub-CP drain, so a
rider at 0.95·CP for 30 min keeps a 100% bar — a named blind spot, with the structurally-correct fix
(relax toward an intensity-dependent steady state) noted as future work.

## Where you were wrong (your section) — recorded.

- §6.8's usefulness result: I ran your affine-residual test — R² ≈ 0.03, bar >5 pts off the affine line
  ~93% of the time — and §6.8 now reports that stronger number and the informative-≠-correct distinction.
- `τ_off` not load-bearing: confirmed and propagated (§7 retraction).
- The glycolytic-bar affine claim and the "W′bal + one new number" framing: adopted in §7.

## Minor points

- **m1** (Bogdanis attribution + Bogdanis 1998): fixed and added, above.
- **m2** (gate_p in exponent vs amount): the pseudocode and both codebases scale the *amount*
  (`gate_p·(1−exp)`), matching your 87/68/46/30/25 read of the paper's intent — §4.2 now says so
  explicitly. (Your rebuild's 92/74/50/31/25 used gate-in-exponent.)
- **m3** (Sci Rep 2024 missing from refs): added, with a full entry, and now load-bearing in §6.10.
- **m4** (`D` repayment mechanism backwards): corrected in §7 — the recurrence is the **fullness taper**
  collapsing the ceiling, not `P₁ₛ` decay, so a "recalibrate sprint power" hint will not fix it.
- **m5** (degeneracy map): added to §7 — `f_p`/`P_p_max` both set the sprint residual, `τ_p`/`k` both set
  the repeated-bout decay, `g_rate`/ramp both set the §6.9 level; named before any per-athlete fit.

## The structural fork, and §6.10.

Adopted. §7 now states the product decision explicitly (live pacing display running on the fast-reserve
transient vs a post-ride training metric that does not need a head unit), rather than drifting through it.
And the deepest point — that biopsy during ergometry is in-modality, compartment-level, already cited, and
falsifying — is now **§6.10**: I ran the repeated-sprint partition and the model fails it (23%↗ vs 40%↘).
§7's "unfalsifiable in-modality — permanently" is retracted. The premise is right and the number is wrong,
both in a paper we already had; v0.7 fixes the framing and hosts the failing number rather than the claim
that no such number could exist.
