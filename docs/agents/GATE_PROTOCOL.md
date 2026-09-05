# The gate protocol

Read this when gating, re-gating, or writing a verdict. It governs where a
verdict lives, what a round records, what a re-gate is allowed to read, who is
allowed to write the verdict, and how many times the suite is measured.

Facts and canonical commands: `docs/agents/FACTS.md`. Sizing: `DISPATCH.md`.

---

## 1. Verdicts are files

The reviewer or consolidator **writes the verdict to a file** and returns a
one-paragraph summary plus the path. The fix agent is handed the **path**, not
a re-narration.

This kills the pattern of one verdict being retold in full three times per
round — dispatcher to reviewer to fixer to PR comment. It also survives an
agent that dies at its reporting step, because the verdict is already on disk.

**Where.** An absolute scratch path **outside the repository**, the same
constraint the reviewer gives its lenses. Verdicts are not committed: they are
working artifacts about a commit, and a repository that accumulates them starts
inviting agents to read stale ones. The **record** is the branch, the PR body
and the issue thread. (This repository's existing convention posts the
per-lens tally and the overall verdict as a GitHub comment — `reviewer_agent.MD`
— and that posting is the public record; the file is the working copy.)

### 1.1 Findings

Each finding carries four fields. `file:line` is **optional** — an
absence-finding has no line, and a schema that requires one quietly deletes the
most valuable finding class.

| Field | |
|---|---|
| **claim** | what the artifact asserts, quoted |
| **required fix** | the smallest change that clears it, written as a **verbatim substitution** where possible |
| **verifying command** | the command that proves the finding, runnable as written |
| **rationale** | why the claim is wrong — distinguish *false* from *imprecise* from *unsupported* |
| *(optional)* **file:line** | pinned to the SHA reviewed |

A blocking finding without a verifying command is not blocking yet. Run it
first.

Substitutions are applied **verbatim from the verdict**; a fresh paraphrase is
how the same claim goes wrong a third way. But **any number in a substitution
is re-measured, never copied** — the byte arithmetic in #96 was corrected
twice in place, and the second correction was to a number a reviewer had
supplied.

### 1.2 Required top-level sections

A findings array alone silently deletes these. All three are mandatory, and the
first one is mandatory **in those words**:

1. **WHAT WAS NOT VERIFIED.** Literally that heading. "No simulator was run",
   "the Docker daemon was down so the container job did not execute", "the
   `file:line` references were read from the diff and not from a checkout" —
   whichever applies. A reviewer that cannot distinguish *checked* from
   *assumed* is not reviewing.
2. **Items only field or manual testing can answer.** Everything needing a
   real device, a saved FIT, a human-driven simulator or a decoder — in this
   repository that is every `createField` change (#96), every recorded-stream
   semantics change (#100, #76) and every calibration-default change (#92).
   Each becomes a `[Local]` issue (`FACTS.md` §3.4).
3. **What holds up.** Specific, with evidence. A review that only lists defects
   is not calibrated and reads as noise; the author then treats every finding
   as negotiable.

Then: the tally and the one overall verdict up front, the blocking findings,
the non-blocking items clearly marked, and the SHA reviewed — named, always.

---

## 2. The rounds ledger

One **append-only** file per PR or issue under gate. One row per round.

| Column | |
|---|---|
| **round** | 1, 2, 3 … |
| **commit** | the full SHA gated |
| **what that round believed** | the claim the round was built on, in one sentence |
| **what the gate found** | blocking count and the shape of it |
| **verdict path** | absolute path to §1's file |

Append only. A round is never edited after the fact; a correction is a new row
saying what the earlier row got wrong.

**Rounds are the honest count.** A non-trivial fix takes three to seven rounds,
and rounds 3+ are usually fixing the previous fix rather than the original
defect. Report the number; it is what the owner needs to decide whether to keep
going or ship.

---

## 3. Re-gates run on the delta

A fix-round closure lens gets exactly three inputs: the **scoped diff** since
the last gated commit, the **prior verdict file**, and the **ledger**. Not the
whole branch.

**Never scope down two lenses**, because scoping them down removes the thing
they are for:

* the **near-neighbour lens** — its value comes from looking *outside* the
  diff. #97 fixed the crash and left the stale "returns null" comment three
  lines above the fix (#98 item 3);
* the **final pre-land consolidator** — the last reader of the whole change.

### 3.1 Reviewer continuation — direction matters

A **continued** reviewer is permitted **only as the diff-holder**:
round-over-round body comparisons need the prior text.

**The verdict on any round that touched prose goes to a FRESH lens.**

**An author of a substitution never re-gates it.** This is the one rule in
this file with no exception, because the failure it prevents — a wrong claim
confirmed by the agent that wrote it — is silent by construction.

---

## 4. One shared measurement per gate

**One** designated agent runs the measurement **once** per gate and publishes
the commit (full SHA), the exact command, the result, and the raw output at a
path every lens can read. **No lens accepts a relayed number.**

What "the measurement" is here, because it is not one thing (`FACTS.md` §1.2):

| Layer | The measurement of record | Evidence it actually ran |
|---|---|---|
| Monkey C compiles | the CI check-runs object for the exact SHA: `Compile (edge1050)`, `Compile (fenix6pro)` | the run id and conclusion, read with the §2.1 form |
| Model numerics | `Model parity (R vs Python mirror)` + `R model tests (testthat)` on the same SHA | same |
| `(:test)` assertions | a **local** `monkeydo … -t` run on `edge1050`, quoting the `PASSED (passed=N, failed=0, errors=0)` line, with N equal to `scripts/expected_tests.txt`'s count | the log file; a simulator that died before any test ran cannot produce that line with the right N |
| Anything with a `Session` or a `Dc` | a `[Local]` item, not a measurement | — |

`bash scripts/check_expected_tests.sh` is the **pin** check, not execution
evidence: it is a static scan and is green with no simulator running.

**Exemption: mutation runs stay per-mutation.** "Reverting X reds exactly case
Y, N−1/N" is a claim about one specific run, and a shared total cannot make it.

### 4.1 Local greens are not the measurement

A local run is necessary and never sufficient. The measurement of record for
the compile and parity layers is the CI run object for the exact commit; for
the `(:test)` layer it is the only measurement there is, so state the device,
the SDK version and the `PASSED` line verbatim. **If the Docker daemon is down,
the container run did not happen** (`FACTS.md` §1.3, §2.6).

---

## 5. Gate actions

**Merging a PR and closing an issue are gate actions.** They are taken only on
explicit direction, and only when *both* approval and CI hold. When directed to
"merge on accept and CI", say plainly which of the two failed if either does.
Filing issues, posting comments and editing issue text you authored are **not**
gate actions.

Landing itself has its own checklist: `docs/agents/rituals/LANDING.md`.

---

## 6. When rounds stop converging

* **Three rounds running finding a defect in the previous fix** → stop
  patching. Either **extract a pure seam and pin it** (a `static` taking plain
  values, the way `decideDropout`, `validateBlob` and `writeField` were
  extracted — and the pin must **call** the shipping code), or **split the
  issue** so adjacent code does not hold a P0 hostage.
* **Body rewrites cap at three rounds.** At the cap, whatever is still
  contested is **deleted** and the remainder is filed as its own issue.
* **After the second wrong framing of a claim, the claim goes.** Delete, do not
  reword.
* **Remainders live in the tracker.** A leftover named only in a commit body or
  a report does not exist.

---

## 7. Reports are claims; the branch is the record

Gates verify at source — run objects, file contents, the actual commit message
— never the narration. A report that a commit says X is not evidence that it
does; read the commit.

Correct forward. Pushed-but-unlanded history may be amended, with the tree-hash
identity verified commit-for-commit when only messages move. **Landed history
is never rewritten**; its errors are corrected in the next commit's body,
naming the error plainly.
