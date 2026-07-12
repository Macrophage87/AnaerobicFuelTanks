# Response to the round-5 review (white paper v0.6 → v0.7)

Thank you — this round did the thing no previous one could: it pointed the model at data that can
falsify it, and it was right that the model fails. Every finding is accepted; several change the paper
structurally. All quantitative claims below were re-derived by simulation before acting (the script that
reproduces them is in the project scratchpad). Section references are to v0.7.

## The four findings

**A. §6.9's discrimination is the glycolytic flux ceiling, not the activation ramp — accepted.**
My own ablation now agrees with yours: full model 77% → no ramp 52% → no ceiling 47% → neither 25% on the
alactic session. Removing the ceiling costs ~30 pts, removing the ramp ~25; it is an interaction (the
glycolytic ceiling binds during a 6 s sprint and the spill goes to the fast reserve), and the load-bearing
parameter is `g_rate`, not `τ_on`/`τ_off`. §6.9 is rewritten with the ablation table; §7's claim that
`τ_off` "is the only parameter carrying the depletion-phase novelty" is retracted (a 20× change in `τ_off`
moves the split 1–2 pts). `g_rate` is promoted to a flagged, banded, load-bearing parameter (§4.1, §7).

**B. The signal is a power threshold, not effort structure — accepted, and now stated as a scope limit.**
Holding the 10×6 s structure fixed and sweeping power, the reading climbs 52→62→66→72→77% at
450→900 W. A textbook alactic session at 450 W reads ~52%, near the glycolytic session's 38%. §6.9 now
carries this explicitly: the metric detects supra-flux-ceiling power and is blind to submaximal alactic
work.

**C. The model contradicts Sci Rep 2024 / Gaitanos 1993, in §6.9's own protocol — accepted, and it is
now §6.10.** The repeated-sprint glycolytic share runs 23%↗46% where the biopsy literature has 40%↘<10%
— wrong level and direction. You diagnosed the cause exactly: the fast-reserve ceiling fades with
depletion (so glycolysis absorbs *more* across bouts) while glycolytic flux has no fatigue term. I added
an **optional** `g_fat` flux-fatigue term (`rate_g·(R_g/C_g)^{g_fat}`, off by default) and confirmed it
plus the aerobic ramp move the trend toward flat/falling — but they do **not** reproduce 40%→<10%, so I
have reported the failure honestly rather than claimed a fix. Reaching sprint-1's 40% needs a higher
`g_rate` that then breaks §6.9's separation; calibrating `g_rate` to the biopsy value and fitting `g_fat`
to the decay is named as the highest-value open experiment.

**D. "Unfalsifiable in-modality — permanently" is wrong — retracted (the important one).** Biopsy during
cycle ergometry *is* in-modality compartment-level data, it is in the bibliography, and the model fails
against it. §7's permanence claim is withdrawn; §6.10 hosts the test and its failure. As you put it, this
is progress: a model that can be wrong in a specific, fixable way is worth more than one that can only be
honest about being unverifiable. The per-system split is now correctly labelled a descriptive
W′-statistic, not a bioenergetic ATP partition.

**E. §6.8 holds — noted, and sharpened.** I ran your affine-residual test: regressing the fast-reserve
bar on its best affine W′bal predictor gives R² ≈ 0.03, with the bar >5 pts off that line ~93% of the
time. §6.8 now reports that (it is a stronger claim than the "<95% of ride time" proxy) and states plainly
that it establishes the bar carries *information*, not that the information is *correct* — correctness is
§6.6 and now §6.10.

## Punch list

1. **§6.9 mechanism corrected** (ceiling, not ramp); §7's `τ_off` claim updated. ✓
2. **§6.9 scope limit stated** (submaximal alactic ≈ 52%, near a glycolytic session). ✓
3. **§6.10 added** — repeated-sprint partition vs biopsy; the model fails in level and direction; it is
   flagged as the highest-value test. ✓
4. **"Permanently unfalsifiable" retracted.** ✓
5. **`g_rate` flagged; optional `g_fat` fatigue term added; aerobic ramp documented as the shortfall
   absorber.** ✓ (calibration of `g_rate`/`g_fat` to biopsy data is named as future work, not claimed.)
6. **Flag split** (`rate_limited` vs `exhausted`) now written into §4.3 — the round-4 item is closed. ✓
7. **§6.8 sharpened** — informative ≠ correct, with the affine-residual number. ✓

## The strategic note

Accepted and hosted (§7, new "structural fork" bullet). §6.9's output is a post-ride computation on a
power file — it needs `g`, the capacity share, and the ceiling, not the recovery law, the deficit, 1 Hz,
or Connect IQ. Off-device, §3's parameter-economy argument reverses and the models rejected in §3 become
available and calibratable against §6.10's data. The paper now states the product decision explicitly
rather than drifting through it: a live pacing display runs on the fast-reserve recovery transient; the
training-load metric belongs in a post-ride tool. I have not collapsed the paper onto one side — that is
your and the author's call to make deliberately — but it is no longer blurred.

Where this leaves it, in your framing: the depletion machinery has, for the first time, been pointed at
real data and does not reproduce it. That is the first falsifiable moment in the project. §6.10 is the
experiment that can now earn or sink the second tank, and it costs an afternoon against data already cited.
