# Response to Critical Review, Round 4 (`whitepaperreviewround4.md`)

*Reply to the round-4 structural review of v0.4. The bug (finding A) is fixed and verified; the
foundational finding (B) is now hosted as the paper's strongest datum rather than a footnote; the
null-model challenge (C) is answered with data from real rides; the stale-strata items (D, E) are
corrected. Companion replies: `white-paper-response-reviewer2-r2.md`, `white-paper-response-reviewer3.md`.*

---

## A — PCr recovery gate missing (the headline bug)

**Accepted; fixed; it was the highest-priority item and you were right to rank it so.** PCr recovered at
the same rate whether stopped or at 99% CP — so the "punch" bar went green while the rider was still
under load, in exactly the "*can I cover this attack?*" scenario the field exists for. Implemented your
one-line fix in both codebases:

```
gate_p = max(0, (CP − P) / CP)
R_p += gate_p · (C_p − R_p) · (1 − exp(−Δt/τ_p))
```

Verified — after a 20 s / 700 W effort (PCr → 23%), 60 s of recovery now gives:

| Recovery power | 0 W | 0.5·CP | 0.8·CP | 0.95·CP | 0.99·CP |
|---|---|---|---|---|---|
| **v0.5 (gated)** | 87% | 68% | 46% | 30% | 25% |
| v0.4 (ungated) | 92% | 92% | 92% | 92% | 92% |

At P = 0 it is identical to the old law, so depletion and the reconstitution fit don't move. This is now
§4.2's marquee fix, with the headline-use-case consequence stated explicitly.

## B — Ferguson's components contradict the model's (foundational)

**Accepted, and promoted from footnote to the strongest single datum in the paper (§4.1a).** You are
right that §4.1a cited Ferguson's channel *separation* as support while ignoring that his channel
*values* contradict the model's identification. Now stated as a table:

| Component | Model | Ferguson channel | ratio |
|---|---|---|---|
| fast | `τ_p = 27 s` → t½ 18.7 s | VO₂ 74 s | 4.0× slower |
| slow | `τ_g = 470 s` → t½ 326 s | lactate 1366 s | 4.2× slower |

Both components ~4× too fast, aggregate fits — the signature of fitting two exponentials to a sum. And
Ferguson's own conclusion (W′ recovery is "not a unique function of PCr or lactate… unlikely to reflect
a finite energy store") is quoted as what it is: *the primary source used to calibrate the recovery law
denies the decomposition the model performs.* The two honest defences (VO₂ off-kinetics ≠ PCr
resynthesis; 31P-MRS `τ_PCr` 20–40 s does support `τ_p`) are stated with their limits. This is the
finding; the paper hosts it.

## C — adopt the null model

**Answered with data, and the answer is more precise than "adopt it wholesale."** Rather than decide by
argument, I ran the experiment you and Reviewer 3 both asked for, on the user's six real interval rides
(§6.8): dual-tank vs the recovery-only null. The caps move the PCr bar by up to **~25–60 pts at
recovery-valley starts** — above the ~5-pt actionable threshold — so they are **not** inert. But they
earn their keep in **exactly one regime**: the maximal one, where the tapered ceiling binds and sets the
post-effort PCr level the recovery law then acts on. Everywhere the ceiling is slack the machinery is
inert, and (Reviewer 2's sharper point) per-system live consumption is `(power − CP)` rescaled, not a
reading. So §7 now answers S1: **keep the ceiling scoped to sprint fidelity; relabel live consumption as
"modelled share"; drop the claims the equations show are empty** — not "adopt the null wholesale," but
"keep the one part that does work."

## D — §6.3(b) stale

**Deleted.** You were right that the "~0.13" was a `τ_g = 360` fossil. With `τ_g = 470` the same point
gives `f_p ≈ 0.21`. §6.3(b) is gone; its surviving content folded into (b)/(c) with the joint-fit result
`(f_p 0.20, τ_g 470)` moved into the body, and "two independent lines" downgraded to "the curve is
consistent with `f_p`; physiology selects it on the ridge."

## E — smaller items

- **Parameter count** (§3 said ~11 with `η`): fixed to **nine free** (`τ_off = τ_on`), "same size as"
  the hydraulic model's eight; `g_pmax-ratio` → `g_rate`; §4.1 opening corrected.
- **Flag split** (was a rename): now genuinely two flags — `exhausted` (`R_p+R_g ≈ 0`) and
  `rate_limited` (`unmet > 0`) — in code and §4.3.
- **Battery parameter set published** (§4.4): `CP 255, W′ 20 kJ, f_p 0.25, P_p_max 690, τ_p 27, τ_g 470,
  τ_on=τ_off 6, LT1 204`. *(Your 6×[10 s/30 s] row differed because the recovery gate wasn't in v0.4;
  with it, the numbers are now 49→17→10→8→8→7 — the gated recovery correctly refills little at 150 W.)*
- **`P_p_max` added to §5's settings list.**

## Where this leaves it (your closing)

Agreed on the substance: the depletion model is finished; the remaining questions are on the recovery
side; one was a bug (A, fixed) and one is foundational (B, now hosted). Where I'd refine your framing:
§6.8 shows the depletion machinery is *not* entirely "hardening the part that provably does not matter" —
on interval sessions the caps change the display materially at decision points, which is the first
evidence any part of the machinery earns its keep. But you are right that this does not validate the
*compartments* (unfalsifiable in-modality; now stated as a hard boundary in §7/§8), and that only §6.6
moves the correctness question. The paper now says all of that, and points at §6.6 as the only thing left
that can.
