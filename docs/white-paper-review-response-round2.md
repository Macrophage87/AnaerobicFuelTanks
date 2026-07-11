# Response to the critical review — Round 2

*Reply to `whitepaperreviewround2.md`. The round-2 review found that two round-1 fixes, each locally
correct, were **jointly wrong** — applied together they broke the depletion dynamics. Every finding
was re-derived by simulation before acting, and the full synthetic battery was re-run after the fixes.
Verdict: all four findings accepted and fixed.*

---

## Summary

| # | Finding | Severity | Verdict | Fix |
|---|---|---|---|---|
| A | PCr empties at a fixed ~37.5% of time-to-exhaustion and flat-lines — contradicts §2's anchor | Structural | **Confirmed** | Taper PCr's available rate with tank fullness |
| B | Glycolytic rate cap discards measured work → combined W′bal reads optimistically high; §6.2 breaks | Structural | **Confirmed** | Deficit accumulator `D` |
| C | The reconstitution "fix" was tuned to 1 of 3 points and indicts the wrong parameter (`τ_g`, not `f_p`) | Calibration | **Confirmed** | `τ_g` 360 → 520; `f_p` re-anchored on physiology |
| D | The `g` decay is in prose/comments but absent from the paper's Case 2 pseudocode | Spec gap | **Confirmed (paper)** | Wrote the decay law; added `τ_off` |

The diagnosis was exactly right: fixes #3 (lower `f_p`) and #9 (PCr-weighted split) were validated
individually but never jointly, and they pushed the PCr-empty crossover the same direction, roughly
halving it. That is the failure mode called out in the review's closing note, and it is fixed both
technically and procedurally (the full battery is now re-run after any structural/parameter change).

---

## A — PCr flat-lining *(structural)*

**Confirmed.** For constant supra-CP power, once `g` saturates the split is fixed, so `R_p` empties at
`f_p·(1+r)` of TTE — 0.35·2 = 0.70 under the round-1 (50/50) parameters, and **0.375** under the new
ones. Simulation of the actual model gave **0.354** (450 W). PCr then reads 0 for the remaining ~65%
of the effort, contradicting §2's cited anchor (*PCr nadir coincides with exhaustion*). No admissible
`f_p` fixes it — you'd need 0.67, outside the 0.15–0.35 band.

**Fix (both codebases).** Make the *available* PCr rate taper with tank fullness (creatine-kinase
equilibrium — flux falls as the store depletes):

```
rate_p  = P_p_max · (R_p / C_p)        # was: constant P_p_max
share_p = need · rate_p / (rate_p + rate_g)
```

One extra multiply. `R_p` now decays asymptotically and reaches its minimum **at** exhaustion, with
the split becoming intensity- and history-dependent instead of a flat 2:1. `take_p + take_g` and
`TTE = W′/Δ` are preserved. Re-verified on a constant 450 W hold:

```
 25% TTE → PCr 37.6%   50% → 8.4%   75% → 1.3%   90% → 0.4%   100% (exhaustion) → 0.1%
```

Bonus: a maximal ~10 s sprint empties `C_p` as an *emergent* property of the rate rule (not tuned),
matching Bogdanis 1996 — now stated as a result in §4.4.

---

## B — the rate cap stops conserving energy *(structural)*

**Confirmed.** On 1200 W (`need` = 945 J/s) with `R_p` empty, `take_g` caps at 345 and the spill loop
can't place the remaining **600 J/s** — measured work, silently discarded. Combined W′bal then
under-drains (reads optimistically high — the dangerous direction), and §6.2 fails whenever a cap
binds, which per finding A is most of every hard effort.

**Fix.** Bank the residual as a deficit `D` (standard W′bal already permits a negative balance):

```
D += unmet
combined_Wbal = (R_p + R_g − D) / W′
```

Now `(R_p + R_g − D)` drops by exactly `Δ` per second regardless of caps. Verified: after 15 s at
1200 W the combined balance is 7297 J vs the expected 7297 J — **leak = 0**. `D` is repaid during
recovery with glycolytic kinetics. §6.2 restored (and rescoped to depletion-only, since recovery
diverges by design).

---

## C — the curve indicts `τ_g`, not `f_p` *(calibration)*

**Confirmed, and the round-1 reasoning was wrong.** Running the model forward with the round-1
settings (`f_p` = 0.25, `τ_g` = 360) misses two of the three Chorley–Lamb points badly (55% vs 65% at
6 min; 79% vs 86% at 15 min) — it only nailed the 2-min point it was implicitly tuned on. Solving each
target for `τ_g` (passive rest, `f_p` = 0.25) gives **688 / 472 / 537 s**; the 234 s half-time cited
in v0.1 implies **`τ_g` ≈ 578 s** independently.

**Fix.** Least-squares over all three points → **`τ_g` ≈ 520 s** (raised from 360), giving 40/62/87%
vs the 37/65/86% targets — max error ~4 pts, versus 8–9 at 360.

Crucially, **`f_p` was *not* re-derived from this curve.** The review's methodological point is right:
`f_p` is confounded with the reference protocol's assumed recovery power (implied `f_p` swings ~0.13
at passive rest to ~0.25 at soft-pedal), so the curve can't pin it. `f_p` = 0.25 now stands solely on
**physiological alactic-fraction grounds** (~0.20–0.30 of anaerobic ATP capacity; di Prampero &
Ferretti 1999, Bangsbo 1990), and §6.3 says exactly that. *(Open item, flagged in-text: state the
recovery power the Chorley–Lamb source protocol used — if near-passive, the physiological anchor is
doing all the work of justifying 0.25.)*

---

## D — the `g` decay was unspecified in the paper *(spec gap)*

**Confirmed for the paper** (the *code* already decays `g` with `τ_off = τ_on`). Without a stated
decay, `g` ratchets to 1 on the first surge and every later interval starts at a flat split — the
Parolin activation ramp inert for the rest of the ride. Added the decay law to the Case 2 pseudocode
and a `τ_off` row to §4.1 (default = `τ_on`; phosphorylase reverts by bout end, Parolin 1999).
Verified over a 6×[10 s hard / 30 s easy] set: the ramp re-fires each bout and PCr partially recovers
between bouts (41 → 24 → 19 → 17 → 16 → 15.6%).

---

## E — smaller items (all fixed)

- **§3 parameter count** corrected to **~11** (added the `g_pmax` ratio and `τ_off`); the `0.5` flux
  ratio is now **cited** (di Prampero & Ferretti 1999), not asserted.
- **Abstract and §1** now carry §7's honesty up front — the split is an assumption, and the extra
  resolution is concentrated in post-surge transients — instead of the strong claim sitting six
  sections ahead of the caveat.
- **§4.3** combined W′bal now carries the `−D` term and the depletion-only note; **§5** footprint
  corrected (four scalars: `R_p`, `R_g`, `g`, `D`; `LT1` added to the settings list); **version**
  bumped to **0.3**.
- **§4.4 face-validity** rewritten for the new dynamics and backed by the synthetic battery.

---

## What genuinely improved (acknowledged in the review)

The graded-onset physiology in §2, the identifiability-for-convenience paragraph in §3, the §6.6
falsifiability test, the honest `η` disclosure, and the round-1 pushback on `f_p` = 0.25 vs 0.15 were
all endorsed. The 2:1 split's emergent Bogdanis match is now stated as a result.

**Process note taken to heart:** every structural or parameter change in this round was checked
against the full synthetic battery — constant hold, interval set, and supra-cap effort, plotted
end to end — because it is the *joint* behaviour that bites.
