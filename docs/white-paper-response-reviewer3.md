# Response to Reviewer 3 (`reviewer3reportdualtankmodelv0.4.md`)

*Reply to Reviewer 3 (recommendation: accept as engineering spec, major revision as scientific claim).
The two experiments you flagged as the highest-value, data-in-hand items were run (§6.8); the four
language/parameter items are fixed. Companion replies: `white-paper-response-round4-review.md`,
`white-paper-response-reviewer2-r2.md`.*

---

## 1 — run the null-model experiment (your top item)

**Done.** I ran the full model and the recovery-only null on the user's six real interval/VO₂max rides
and report the divergence of the *displayed* PCr bar, especially at recovery-valley starts (§6.8). Result:
mean ~6 pts, **up to ~25–60 pts at valley starts** — above your ~5-pt "a rider could act on it" threshold.
So the caps *do* change the display in the decision-relevant window, and the fork you describe (it
collapses if the caps don't move the bars) resolves the other way: **the caps earn their keep, but only in
the maximal regime** where the ceiling binds. Everywhere else they are inert — so the answer is "keep the
ceiling scoped to sprint fidelity, drop the inert claims," not "delete 40% of the code." Exactly the
one-afternoon experiment you asked for, and it decided the question with data.

## 2 — unfalsifiable in-modality, permanently

**Accepted and stated as a hard boundary** (§7, §8). Stacking §4.2 (split unidentifiable from power) and
§6.5 (no 31P-MRS in cycling) gives not "untested" but "**no in-modality measurement, even in principle,
distinguishes two compartments from one with the same aggregate recovery.**" §7 now says the two-tank
framing is *terminally* a heuristic for cycling, and names the only route to compartment evidence — your
suggestion — **cross-modality transfer** (knee-extension 31P-MRS for `τ_p`, then assume it transfers), as
a nameable, stress-testable assumption rather than no path at all.

## 3 — the falsifiable prediction is contradicted by the ramp; the drawdown is not linear

**Both accepted.** §4.4 now states that the activation ramp is a *second* intensity dependence acting in
the opposite corner (a hard effort reaches a given `φ` fast, with `g` lower → PCr *lower* at that `φ`), so
`R_p`-at-`φ` is invariant only *asymptotically* — for efforts long relative to `τ_on` and below the
ceiling regime, which for short hard efforts is a narrow-to-empty window. The prediction is re-scoped
accordingly and relabelled a **falsification** test. And the drawdown is now called **front-loaded (mildly
concave)**, not "near-linear" — the 68/42/18/1 shape *is* the ramp, as you note.

## 4 — "corroborated by two independent lines" overstates independence

**Accepted; this was the sharpest catch and it's fixed throughout.** §4.1a, §6.3, and §7 now say the
reconstitution curve constrains a **`(f_p, τ_g)` ridge**, and **physiology selects `f_p` on it** — so the
two lines are *not* independent, and the honest phrasing is "**consistent with**," not "corroborated." The
recovery data alone would prefer `f_p ≈ 0.20`; we keep 0.25 as the physiological midpoint and say so.

## 5 — the Bogdanis residual is a single-rider result

**Accepted.** §4.4 no longer presents `τ_dep ≈ 7 s` as general: it states `τ_dep = C_p/P_p_max` swings
~4–13 s across riders, so the 10 s residual ranges ~10% (fast riders) to **~46%** (`τ_dep ≈ 13 s`) — and
the high tail *does* violate the Bogdanis anchor the central case matches. As you say, that is an argument
for a **measured** PCr depletion constant (the re-architect fork), and §4.4/§7 now frame it that way
rather than congratulating a one-point match.

## 6 — `τ_p = 27 s` = 22/0.8 was cosmetic

**Accepted.** `τ_p = 27` is now justified on its own terms — inside the 31P-MRS `τ_PCr` range of 20–40 s
(Yoshida 2013; Harris 1976) — *not* "22 inflated by η" (which just re-imports the double-count). A
**deprecation note** is carried on the retained `eta` settings key so a maintainer cannot silently
reintroduce the rescale.

## 7 — the product thesis has no test (your highest-value item)

**Partly answered with data, and the rest flagged as required.** The "how often is `R_p` below 95% in
real files" statistic you proposed is now computed (§6.8): **~45% of ride time (20–79%)** across six real
interval sessions — above your "20–25% = real" bar, though I state the caveat that these are hard interval
files and a steady endurance ride would score far lower. That converts "there are enough transients to
matter" from assumption to measurement (for interval training). The *decision*-quality half — does a rider
pace *better* with two bars — remains untested, and §7 now names the minimum next step (a usability check,
even n=1: race on it and log whether the second bar changed a call) as a precondition for the product
claim, not an optional extra.

## Minor points

- **`D` corrupts the display at max effort** — accepted as a *failure mode*, not a footnote (§7); the
  field should surface a "recalibrate sprint power" hint when `D` grows from full tanks (`rate_limited`).
- **Aggregate recovery is mildly misspecified** — accepted; §4.1a notes a single exponential per tank
  can't hit 37/65/86 exactly (per-point `τ_g` runs 688→472→537), so "calibrated" means "best fit within a
  mildly misspecified single-exponential-per-tank family."
- **LT1 gate shape, `D`-on-`τ_g` lumping, spill ordering** — all flagged in §7 as unmodeled/assumed
  choices rather than asserted.
- **Test 6 needs an optimally-fit single-tank baseline** — added to §6.7 (else the dual-tank wins
  trivially by having more recovery freedom).
- **Reconstructed incumbent equations** — the sourcing note's "verify against publisher PDFs" is now
  called a **blocking** task before v1.0, not a footnote.
- **Ferguson DOI/year** — annotated (the `.2008` stem is the submission year; article is 2010).

---

## On the fork

You are right that the fork is less symmetric than presented: "ship the heuristic" is really "ship the
recovery-only heuristic and keep the ceiling only if the caps move the display" — and §6.8 now shows they
do, in the maximal regime, so the ceiling stays (scoped) and the rest is relabelled honestly. The
re-architect path (a *measured* PCr depletion constant so `R_p` is a real state variable matching Bogdanis
across riders) is the right answer to point 5's high tail, and §7 keeps it as the named alternative for a
model that wants compartment-level truth rather than a shippable display. For a v1.0 data field, v0.5 ships
the heuristic — now with the informativeness statistic and the null-model comparison behind it, rather than
on faith.
