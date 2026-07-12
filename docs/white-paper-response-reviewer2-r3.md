# Response to Reviewer 2 — third report (white paper v0.6 → v0.7)

Thank you — this is the report that resolved the identifiability problem the series has circled, and the
resolution is yours: the tanks are compartments of W′, not of muscle. Every item in the v0.7 punch list
is done. Two of your findings (the §4.1a reinterpretation and the §6.9 mechanism) rewrote sections; the
rest are hygiene, all applied. Numbers below were re-simulated before acting.

## 1–2. §6.9 is right — but the mechanism is the flux ceiling, not the ramp. Corrected.

Your ablation reproduces in my code (I get full 77% → no-ramp 52% → no-ceiling 47% → neither 25%; the
same story as your 40/10/10-point decomposition — a strong interaction, not a ramp effect). §6.9 now
credits the **glycolytic flux ceiling scaled by the ramp**, with the ablation table, and names `g_rate`
as the mechanism. §7's "everywhere the ceiling does not bind the machinery is inert" is rewritten: the
ceiling binds *constantly* on short efforts and is the engine of §6.9 — it is not a sprint-only term.
This is, as you say, a stronger answer to S1 than v0.6 gave, and it was sitting in the simulation.

`g_rate` is promoted to a flagged, banded (~0.3–0.7), load-bearing parameter (§4.1, §7), with the
sensitivity noted (separation 48→33 pts across the band). The spill-order flag is **downgraded** per your
test — reversing it changes §6.9 by 0 pts because `rate_g` is already exhausted (§7).

## 3. §4.1a and §6.9 are on a collision course — insulated, with your τ_p = 107 s check.

Added to §4.1a, in three sentences as you prescribed: §4.1a is about the **recovery law**, §6.9's signal
is about the **depletion law**, which is anchored in measured activation kinetics (`τ_on`, Parolin) and
flux ratios (`g_rate`, di Prampero), not the recovery constants. I re-ran §6.9 with `τ_p = 107 s`
(Ferguson's VO₂ channel) and confirm the separation barely moves (<1 pt in my run; your table shows it
never falls below 30 pts across every perturbation). So §6.9's best claim is no longer left exposed to
§4.1a's best objection.

## 4. The 4× offset is forced by the data — it exonerates the τ's and convicts the naming. Adopted.

This is the heart of v0.7. §4.1a is rewritten around your two facts: (1) the *ratio* is preserved — model
17.4× vs Ferguson 18.5×, within 6% — so it is not fitting-two-exponentials-to-a-sum; (2) building the
model from Ferguson's own channel constants (107 s, 1971 s) predicts 20/35/50% vs the observed 37/65/86%,
i.e. **W′ recovers ~4× faster than its metabolites**. The τ's are the right constants for W′ (the quantity
displayed); the metabolic *naming* is what fails. I added the symmetric defence you flagged — blood
lactate t½ is no more muscle H⁺/Pi clearance than VO₂ off-kinetics is PCr resynthesis — and drew the
honest conclusion: neither Ferguson channel measures a tank, so Ferguson cannot adjudicate the
decomposition either way, which is Ferguson's point and ours.

**The rename is adopted (your item 12).** The paper now uses **fast reserve / slow reserve**, with the
metabolic identification as motivation, and §4.1 states it explicitly. Every "the bar equals biopsy PCr"
reading is withdrawn — including the flattering §4.4 "matches Bogdanis 17%" claim, since (per Reviewer 3)
one cannot use the muscle-PCr mapping where it passes and disown it where it fails.

## 5. `gate_p` is the largest un-flagged assumption. Flagged.

Added to the §4.1 table, to §7's assumptions list, and the free-parameter accounting (it is a
functional-form gate, no new tunable constant, now counted among the assumptions rather than hidden). Its
shape sensitivity is reported: linear/√/sigmoid swing the 60-s post-effort recovery number 46/65/34% at
LT1 — a 21–31 pt swing on the head unit.

## 6. The paper is under-claiming under `gate_p`. Fixed, in your favour.

§1, §7, and the Scope box now state that under the gate the effective PCr recovery constant is 44 s at
100 W, 66 s at 150 W, 135 s at LT1 — 100–500 s while riding, not 27 s. So "PCr full most of the time" is
withdrawn; the fast-reserve bar is live for a substantial fraction of interval-ride time (§6.8: 20–79%),
and the "affine most of the time" caveat now applies to stopped/easy recovery, not to riding.

## 7. `τ_off` is not load-bearing. Your error removed, as requested.

Done — and thank you for catching your own round-2 attribution. §7 no longer says `τ_off` carries the
depletion novelty; §4.2's `τ_off` warning is proportionately relaxed; the §4.1 table marks it not
load-bearing (a 20× change moves the split 1–2 pts).

## 8. Smaller items.

- **§6.8 reproducibility / mean-vs-range:** now reports per-ride figures (20/31/38/52/61/79%, median ~45%)
  and carries the **divergence ≠ accuracy** caveat up into the Scope box.
- **§6.9 session definitions:** fully specified (alactic 10×[6 s@900 / 300 s@150]; glycolytic
  5×[60 s@360 / 120 s@150]); the reproducing script is in the repo.
- **Changelog narration** ("the fix that ended a three-round patch cycle") deleted.
- **`D` on the over/under session:** you were right to worry — a 4×4 books ~45% of its anaerobic work to
  `D`. §6.9 now reports `D` as a third column and refuses the split when `D` is a large fraction of total.

## Recovery-law fix (beyond your list)

Reviewer 3 and round-5 showed v0.6's linear LT1 gate could not complete a 4×4 (recovery → ∞ at LT1). v0.7
replaces it with Skiba's `τ_W′(CP−P)` shape, amplitude re-anchored to Ferguson at 20 W — so the Ferguson
curve you verified (40/63/87) and the §4.4 sprint battery are unchanged, while the 4×4 now completes
(100/49/7/−24%). This does not touch your τ-exoneration argument; it fixes the recovery *shape*, not the
constants.

You have recommended revision three times and been right each time, including about your own errors. The
model argued itself into a narrower, better-located claim this round — a W′-decomposition heuristic with
an honest name — which is the outcome your reports were driving toward.
