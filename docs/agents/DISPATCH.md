# Dispatch sizing: the band metric and the issue header

How many agents a task gets, decided **before** dispatch and recorded on the
issue. This file is the versioned, reviewable copy; the orchestrator role
definition carries the same rubric so it is in context at triage time without a
file read.

**Why this is the headline mechanism.** The cost of an orchestrated loop is not
the prompt; it is **how many agents get dispatched, for what**. The StrongRow
loop this was distilled from measured 20–31 agents per issue on work that
included pure comment corrections, and halved its median to 2 by re-anchoring
these axes on real issues (`LESSONS.md`, part 2). The anchors below are this
repository's; §4 is the first scoring of its backlog, and §5 says what has not
been validated yet.

---

## 1. The five axes

Score 0–3 on each, **before** choosing agents.

### R — Reversibility

**Name the revert, then say what it does not restore.** "It lands on `main`" is
true of every issue and separates nothing.

| | Here |
|---|---|
| **0** | `git revert` restores the prior state **and nobody outside this branch has read it yet**: a scratch file, an unpushed commit, a PR body no review has quoted |
| **1** | `git revert` is a complete remedy — the whole effect is inside the tree, and one commit puts it back. Source, tests, tooling, `monkey.jungle`, workflow text and documentation are all R=1 by default. **This is the normal case, including for most bug fixes.** |
| **2** | the revert restores the tree and **not the world**: the change alters what a *shipped* build writes into a recorded `.fit` (record-scope fields **latch**, `FACTS.md` §3.3; the model-stream semantics of files recorded before and after differ and no commit reconciles them — #100, #76, #95's flip); or what a shipped build does with a stored `Application.Storage` blob (the persistence format, `validateBlob`) |
| **3** | irreversible by construction: a published release tag or asset (`v0.6` is still `latest`, `FACTS.md` §5.5 — the tag can be deleted, a downloaded `.iq` cannot); the Connect IQ **Store-Version**; a developer field **id** (`FACTS.md` §5.3 — unique per `field_description`; re-using 6–17 for a *narrower* type silently re-labels any file already recorded with the FLOAT definition, which #99 has to reason about) |

If you cannot name an artifact outside this repository that the revert fails to
reach, R is 0 or 1. Score the change the issue commits to, not the most
expensive option on the table.

### V — Verifiability cost

**0** means an existing automated check would catch the mistake without anyone
thinking about it. **3** means *nothing in this repository can catch it*.
Everything below is verified in `FACTS.md` §1.2 and §3.2.

| | Here |
|---|---|
| **0** | `model-parity` + the R testthat suite already pin it (a model coefficient, a fixture), or a runner-free checker derives it (`check_settings_defaults`, `check_manifest_appid`, `check_expected_tests`, `check_agent_facts`, `check_ceiling_notes`, `check_mc_literals`, `check_calibrate_manifest`) |
| **1** | a `(:test)` or an R test **could** cover it and this change adds one — remembering that a `(:test)` here **compiles in CI and executes only locally** (#61), so V=1 carries a local `monkeydo` run as evidence, not a CI checkmark |
| **2** | only a static check or a local simulator run can see it — anything that needs a `Session` (`createField`, the 32 B budget arithmetic), `Application.Storage`, `Activity.Info`, or the simulator's activity playback |
| **3** | **no `(:test)` can obtain a graphics `Dc`** (layouts, fonts, the red flash); **a comment cannot be red by any test**; **nothing here decodes a file this app wrote** (#100's lag, #76's fabricated dataset); **on-device load** (#96's crash was green in CI); real ride data across several sessions (#92) |

Two incident anchors for why V is the axis that gets under-scored:

* **#96 scored "verified" at every stage and crashed on every device.** Compile
  green on two devices, parity green, `(:test)` green locally — and
  `createField` inside `initialize()` raised an uncatchable error the first time
  a real device ran it. That is V=3 from the inside: it looks verified.
* **#100's lag was found by a decoder nothing in the tree owns.** The
  cross-correlation table is a number nothing committed can regenerate
  (`FACTS.md` §6). Until a fixture and a script land (`rituals/FIELD_DATA.md`),
  every conclusion drawn from it is V=3.

### S — Settledness

| | Here |
|---|---|
| **0** | an accepted design comment exists on the issue and nothing has contradicted it (#99 inherits #96's accepted v6 plan) |
| **1** | the fix is obvious and uncontested, no design comment needed |
| **2** | the issue names a symptom and more than one remedy is defensible (#76: skip vs sentinel vs gate; #100: reorder vs shift-on-read) |
| **3** | the premise is contested, or measured behaviour disagrees with the issue's own diagnosis (#61: two levers falsified; #92: waiting on evidence) |

### P — Prose surface

Prose is the most defect-prone surface here and has no compiler. What makes it
expensive is a **second reader who cannot check it against the code**. **Name
the second reader.** P ≥ 2 requires naming the file, issue or release that
would also have to change.

| | Here |
|---|---|
| **0** | no prose changes, or a comment restating the line below it: code, tests, fixture data |
| **1** | prose with exactly one reader — the next person to open that file: a source comment stating a figure or a runtime claim, a commit body, a PR body no review has quoted. **The normal case.** |
| **2** | prose the repository keeps a **second copy** of, or that another artifact **cites**: the model's parameter table (README, `connectiq/README.md`, `docs/llm-calibration-context.md`, `properties.xml` defaults and `settings.xml` ranges all state it); a fact `FACTS.md` also states; a `[Local]` issue's byte-exact pass criteria; an issue body another open issue cites by number (#96 ↔ #98 ↔ #99) |
| **3** | prose published outside this branch's diff: `README.md`, `connectiq/store/description.txt`, a release note, the white paper and journal manuscript, `docs/agents/**`, `CLAUDE.md`, a `field_description` **name or units string** a FIT consumer decodes (`PCr_J`, `kJ`) |

No job reads the prose. P=3 is a human review obligation.

### I — Interaction

**Name the open PR, the pushed branch, or the pinned budget.** An open *issue*
naming the same file is I=0 evidence: issues do not merge, branches do.

| | Here |
|---|---|
| **0** | one file, no shared constant, nothing in flight touches it |
| **1** | a shared constant, helper or fixture with a named consumer in the tree (a `TankModel` public member the view reads; `writeField`) — but nothing in flight |
| **2** | the change spends a **pinned shared budget** or edits one half of a **hand-synced set**: the 32 B FIT budget per message type; a file-scope `(:test)` (spends `fenix6pro` headroom, `FACTS.md` §5.1); `scripts/expected_tests.txt`; **the three parity-locked model implementations** (`TankModel.mc`, `tools/crosscheck/tank_model.py`, `tools/calibrate/R/model.R`) and their fixtures — change one and all three move; `properties.xml` defaults, which `check_settings_defaults.sh` and the `(:test)`s both pin. **Or** an open PR or pushed-unmerged branch edits the same function |
| **3** | a contract every branch inherits: `connectiq/manifest.xml`'s product list, `.github/workflows/ci.yml`, `monkey.jungle`, a developer field id, the `Application.Storage` blob layout (`SLOT_*`, `STATE_LEN`) |

I=2 for a collision is **checked, not assumed**:

```sh
gh pr list --state open --limit 50 --json number,headRefName,title
git fetch origin && git branch -r --no-merged origin/main
```

Measured at `30b2b99` on 2026-09-05: **zero** open PRs, and **23** remote
branches not merged into `origin/main` (`claude/*` from earlier sessions, most
of them stale ancestors of merged work). None is in flight; treat a pushed
branch as I=2 only if its commits post-date the issue's filing.

---

## 2. The band

| Band | Score | Dispatch |
|---|---|---|
| **Trivial** | 0–3 | no agent — the orchestrator does it inline |
| **Routine** | 4–6 | one small-tier implementer, no gate *(but see the guardrail)* |
| **Standard** | 7–9 | one large-tier implementer + one large-tier reviewer |
| **Heavy** | 10–12 | implementer + 3-lens gate + consolidating verdict |
| **Critical** | 13–15 | implementer + 4–5 lens gate, **re-gate after every fix round** |

### The tier ladder, and what is not on it

`implementer=` runs **small → medium → large**. Exhaustive multi-agent mode
(`ultracode`) is a **flag on top of Critical, never a rung on the ladder**: it
adds parallel lens fleets and adversarial verification over the band's
dispatch and never changes which model implements. It appears only at Critical,
or when the owner names it. A premium stall-breaker model, if one is kept,
stays **off the ladder entirely** — reached by escalation (four failed rounds on
one task), never by triage.

### Guardrails

* **A pure-prose change to a published contract is Standard minimum**, whatever
  the line count. P=3 alone floors the band at Standard.
* **Strike "no gate" from Routine whenever P ≥ 2 or R ≥ 2** — minimum one
  small-tier review lens. Say in the header which of the two triggered it, or
  that neither did. The gate that never depends on the band is `ci-required`:
  every landed change passes the jobs its `needs:` list names, on a protected
  `main`, whatever its score.
* **Proposal review is band-governed too.** Trivial and Routine skip it;
  Standard gets a small-tier design review; Heavy and Critical get the full
  reviewer.
* **Concurrency limits cap how many agents run AT ONCE, never the band.** One
  build slot, one simulator: a Critical task on a loaded machine runs its
  lenses **serially**, not with fewer of them.
* **A change to what a shipped build records is never below Standard** (R ≥ 2),
  and its verdict carries a `[Local]` record-and-save item (#98) because
  `createField` is unreachable from the suite.

### Escalation is automatic, not discretionary

Any of these raises the band **by one step** mid-task — Trivial → Routine →
Standard → Heavy → Critical, Critical being the ceiling. Record the raise as a
comment so the history is auditable:

* a gate returns blocking findings → **+1 band** for the fix round;
* a fix round introduces a new false claim → **+1 band**, and the next round is
  constrained to **subtraction only**;
* the same claim is wrong twice → **delete it**, **+1 band** (do not reword a
  third time — #96's body took two dated corrections; a third would have been
  a deletion);
* measured behaviour contradicts the issue's diagnosis → **re-triage** from
  zero, do not patch forward (this is what #96's 4-reviewer audit did);
* a test that should have failed did not → **+1 band**, the check is blind.

The unit is a **band, not a point**. A raise is recorded in the escalation
comment, not by rewriting the header's axis line. **De-escalate only** after two
consecutive clean gates, and **never below Standard while R ≥ 2**.

---

## 3. The header

One line near the top of every issue, set at filing or triage:

```
Dispatch: band=<Trivial|Routine|Standard|Heavy|Critical> (R# V# S# P# I# = total) | implementer=<tier>/<low|medium|high> | reviewers=<n>×<tier>[ + consolidator] | ultracode=<yes|no>
```

* The header is the **opening guess**. Escalation still raises it mid-task.
* The dispatcher **reads the header instead of re-scoring**; re-score only if
  the issue changed materially.
* `ultracode=yes` appears only at Critical, or when the owner names it.
* No stall-breaker tier appears in any header.
* **The axis sum must match the band.** A header whose arithmetic does not
  close is a defect in the header, not a judgement call. Check it every time
  you read one: the band, not the word, decides the dispatch.

Example, for **restoring config recording as narrowed session fields** (#99):

```
Dispatch: band=Heavy (R2 V2 S1 P3 I3 = 11) | implementer=large/high | reviewers=3×large + consolidator | ultracode=no
```

R2 because a shipped build's session record changes; V2 because no `(:test)`
can reach `createField` and the byte arithmetic is a static check until a
device saves a file; S1 because #96's accepted plan names the shape; P3 because
`field_description` names and units are decoded by consumers and the README
advertises them; I3 because ids 6–17 are a developer-field-id contract.

---

## 4. The opening scoring of this backlog (`30b2b99`, 2026-09-05)

One scorer's judgement applied to the issue bodies, under §1. **Not posted to
the issues** (§5); recorded here so each judgement can be disagreed with
individually. V and S were read from the bodies; R, P and I were scored with
the "name it" rules above.

| # | Title (short) | R | V | S | P | I | Σ | Band | Named reason for the non-obvious axis |
|---:|---|---:|---:|---:|---:|---:|---:|---|---|
| **new** | **Prune FIT writes to the display minimum** (maintainer, 2026-09-05) | 2 | 2 | 2 | 3 | 3 | **12** | **Heavy** | R2: shipped builds stop recording streams files already carry; P3: README, `connectiq/README.md`, store description, white paper §7 all advertise them; I3: developer field ids retired |
| 96 | v0.6 load crash — remaining: release + store resubmission | 3 | 3 | 0 | 3 | 0 | 9 | Standard | the code landed; what remains is `rituals/RELEASE.md`, and R3/V3 are the release's, not a patch's |
| 99 | PR-B: restore config recording, gated + narrowed | 2 | 2 | 1 | 3 | 3 | 11 | Heavy | worked in §3 |
| 98 | PR-A follow-ups: byte-budget guard, checklist, release gate | 1 | 1 | 1 | 3 | 3 | 9 | Standard | I3: `ci.yml`'s `manifest-lint` job; P3: the calibration checklist and release process are published |
| 100 | Model streams lag power by one second | 2 | 2 | 2 | 2 | 1 | 9 | Standard | V2: a seam test can pin the ordering, only a decode proves the file; P2: `docs/calibration-protocol.md` and #95 cite the alignment |
| 95 | Flip-B: enable the aerobic-excess term | 2 | 1 | 2 | 3 | 2 | 10 | Heavy | I2: three parity-locked implementations plus both fixture generators; P3: white paper |
| 92 | Reconsider the shipped default `fP=0.25` | 1 | 3 | 3 | 2 | 1 | 10 | Heavy | **field-only**: the band is for the analysis after multi-session evidence exists, not for waiting; V3 by construction |
| 61 | Stabilise headless `ciq-test`, promote to required | 1 | 2 | 3 | 2 | 3 | 11 | Heavy | S3: two levers falsified, root cause unknown; V2: the segfault reproduces only in the container, and the daemon is down locally |
| 76 | Unconfigured ride records a fabricated dataset | 2 | 2 | 2 | 1 | 1 | 8 | Standard | R2: changes what a shipped build records; S2: skip vs sentinel vs gate — and fields **latch**, so "skip" is not an option (`FACTS.md` §3.3) |
| 40 | Dependency pinning, regenerables, root `.gitignore` | 1 | 1 | 2 | 3 | 2 | 9 | Standard | P3: README policy on generated PDFs; note a root `.gitignore` now exists (this loop's landing) and covers only `.claude/` |
| 73 | Disambiguate `mStarted` at the confirm deadline | 1 | 1 | 2 | 1 | 1 | 6 | Routine | neither P ≥ 2 nor R ≥ 2, so no lens is forced; `ci-required` still gates |
| 45 | Python asset-script nits | 1 | 2 | 1 | 0 | 0 | 4 | Routine | V2: nothing runs `connectiq/store/*.py`; a manual run is the only check |
| 70 | Epic: repo hygiene (umbrella) | 0 | 0 | 1 | 1 | 0 | 2 | Trivial | tracking only; the orchestrator maintains it inline |

Histogram over the 12 existing issues: **Trivial 1, Routine 2, Standard 5,
Heavy 4, Critical 0.** Two adjacent bands (Standard + Heavy) hold 9 of 12
(75%) — crowded, as the StrongRow re-anchoring also found after its R/P/I pass,
and for the same reason: **V is the binding axis** in a repository whose test
suite does not execute in CI and which decodes none of its own files. Median
dispatch under this scoring is **2 agents** (Standard). The kit's acceptance
test for a rubric ("if almost everything lands in one band, the anchors are
wrong") passes narrowly; the V cells are where the next calibration pass goes.

---

## 5. What has NOT been done, and must not be done silently

* **No header has been posted to any issue.** Posting is a write to a public
  tracker and is taken on the owner's direction. When it is, prepend the header
  and leave the body byte-preserved; a scorer that cannot score an issue says
  why rather than guessing.
* **The rubric has not been validated on a re-scored sample.** The StrongRow
  kit validated its anchors by re-scoring 28 real issues from a committed
  worksheet and publishing the before/after histogram from a script
  (`dispatch_rescore.py`, not installed here). With 12 issues there is no
  "before"; the table in §4 **is** the worksheet, and the first re-anchoring
  pass should start by committing it as one and diffing against it.
* **`ultracode` has not been used** and no issue reaches Critical on the
  opening scoring. A developer-field-id change is the one shape that would
  (R3 V3 P3 I3 = 12 before S).
