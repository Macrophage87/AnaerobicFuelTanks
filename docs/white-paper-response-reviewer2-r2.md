# Response to Reviewer 2, Second Report (`reviewer2secondreportdualtankv0.4.md`)

*Reply to Reviewer 2's second report (recommendation: minor revision). The two arithmetic errors are
corrected, the "not done" items are now actually done, the affine-in-W′bal finding is stated, and S1 is
answered from the model's own equations — exactly as you said it could be. Companion replies:
`white-paper-response-round4-review.md`, `white-paper-response-reviewer3.md`.*

---

## §0 — the "claimed done, not done" items

You were right on all three, and the meta-point (v0.4 was a *stratified* document — fixes applied at the
point of criticism, not propagated) was fair and is the thing I most needed to hear. A full top-to-bottom
consistency pass was done for v0.5:

| Your finding | Status in v0.5 |
|---|---|
| Disclaimers not consolidated (repetition went *up*) | Scope box rewritten and **narrowed**; the per-section disclaimers trimmed to cross-references. |
| Changelog narration still in the body | Moved to `white-paper-CHANGELOG.md`; the worst in-body "three rounds of…" parentheticals removed. *(A few "v0.3 said X, corrected" notes remain where a reader needs to know a number was superseded; flagged as such, not narrated.)* |
| Param count half-done (§3 still "~11", still lists `η`) | Fixed: §3, §4.1 opening, and the table all say **nine free**; `η` gone; `g_pmax-ratio` → `g_rate`. |
| S1 transcribed, not answered | **Answered** — see below. |

## §2 — both bars are affine in W′bal (the finding that matters)

**Accepted as the central v0.4 finding, and it now leads the Scope box.** You are right: capacity
weighting gives `d(R_p/C_p)/dt = d(R_g/C_g)/dt = d(W′bal)/dt = −Δ/W′` once `g → 1`, so both bars are
`W′bal + const` through steady effort — the *same* zero-information property v0.4 convicted v0.3's rule
of. The Scope box now states it: **the two bars are affine in W′bal during steady depletion and during
PCr-full recovery; all non-redundant content lives in (i) the activation-ramp offset — a function of
`τ_on` (measured) and `τ_off` (not) — and (ii) the post-effort PCr recovery transient (`τ_p`).** That is
the narrower, true claim. The fix is not reverted (capacity weighting is right); its implication is now
owned.

### §2.1 — the "falsifiable prediction" is lose–lose and not runnable in-modality
Both accepted. §4.4 now labels it a **falsification** test (pass ⇒ the depletion bar is a deterministic
restatement of W′bal, i.e. redundant; fail ⇒ architecture wrong), and withdraws "testable in an
afternoon" — checking PCr in-cycling needs 31P-MRS, which §6.5 says is unavailable, so a surrogate
(post-exercise sampling / knee-extension) is named instead.

### §2.2 — live consumption is the power meter rescaled
Accepted, and it is the key to answering S1. When the ceiling is slack,
`take_p = Δ·C_p/(C_p+C_g·g)` contains neither `R_p` nor `R_g` — it settles to a fixed `Δ·f_p` / `Δ·(1−f_p)`
split within ~20 s, i.e. *(power − CP) × a clock*. §5 and §7 now say so: **per-system live consumption is
relabelled "modelled share," not a reading** (or dropped). The caps earn their keep **only** in the
maximal regime where the ceiling binds (the ~23% sprint residual, the post-effort PCr level) — confirmed
empirically in §6.8.

## §3 — the two arithmetic errors

Both corrected; thank you for the precision.

- **§3.1 — gate at 20 W is 0.90, not 1.** With `LT1 ≈ 0.8·CP ≈ 200 W`, `gate(20 W) = 0.90`, so the model
  reproducing Ferguson needs **`τ_g ≈ 470 s`**, not 520. Default changed to **470**, with the ±few-%
  caveat on the cohort's unreported LT1.
- **§3.2 — the joint fit `(0.20, 420)` was not an optimum.** Correct — SSE 30.7 > the nested single-param
  18.9, which is impossible for a genuine optimum. The true optimum is **`(0.20, 470)`, SSE 10.7**, which
  §4.1a now reports. And the convergence you flag is real and worth stating: the gate-corrected `τ_g`
  (§3.1) and the joint-fit `τ_g` (§3.2) both land on **470** — two independent corrections, same number.
  `τ_g = 470` it is.

## §4 — S1 was transcribed, not answered

Accepted, including the sharper sting: the v0.4 response letter *misdescribed its own §8* ("leans toward
the leaner model" when §8 said "keep the machinery"). §7 now contains an actual answer, and it is the one
you said my own equations already held: **the caps are justified for sprint fidelity and nothing else;
live consumption is not an output worth keeping as a reading; adopt the null model's framing while
retaining the ceiling.** §6.8 supplies the evidence (caps move the display only in the maximal regime).
On the broader worry — that this paper *discloses* problems with candour instead of *solving* them, and
risks converging on a very well-annotated null result — you are right, and v0.5 tries to break the
pattern: it *decides* S1, *runs* the two experiments (§6.8), and *changes the default* (`τ_g`) rather than
flagging and moving on.

## §5 — stale strata

All corrected in the consistency pass: §1 "~20 s" → 27; §3 "~11/η/g_pmax-ratio" → nine free / `g_rate` /
"same size"; §4.1 opening "~11" → nine free; §4.2 and the Bogdanis reference annotation now say "fresh
30 s sprint → ~17%; the 'near-full by 10 s' figure is sprint 2." §6.3(b) deleted (the "~0.13" fossil).
The two minor notes: the `f_p = 0` battery row is relabelled "does not crash" (it tests the guard, not
sensible behaviour); and §4.4 now signposts which regime is "front-loaded" (share-limited) vs
"geometric" (ceiling-limited).

---

## On the verdict

Minor revision, accepted. The two errors are fixed, the arithmetic converges on `τ_g = 470`, the fossil
is gone, and S1 is answered from the equations. Your closing line — that the response was accurate
everywhere except where it said "done" — landed, and the v0.5 consistency pass is the direct answer to
it. The Ferguson identification you credited is kept prominent, and its uncomfortable corollary (the
component mismatch) is now hosted rather than buried.
