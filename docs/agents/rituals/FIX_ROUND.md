# Ritual: a fix round

Read this **when you are addressing a verdict**. Not "if it seems like a big
one" — the rounds that most need these constraints are the ones already going
wrong.

Verdict format, ledger and re-gate rules: `docs/agents/GATE_PROTOCOL.md`.
Facts and commands: `docs/agents/FACTS.md`.

**A fix round introducing a new defect is the norm, not the exception.** A
non-trivial fix takes three to seven rounds, and rounds 3+ are usually fixing
your own fixes rather than the original defect. Budget for it; report the count
honestly.

---

## 1. Before you change anything

1. **Read the verdict file at its path.** Do not work from a summary of it.
2. **Re-run every blocking finding's verifying command** and record the output.
   A finding is a hypothesis until you have reproduced it — including the ones
   that would make the reviewer right.
3. **Re-verify every `file:line`.** Line numbers shift; re-check them every
   round, against `origin/main` or the head SHA, never a stale working tree
   (`FACTS.md` §4.3 — and use `MSYS_NO_PATHCONV=1` for dotted paths, §2.2).
4. **Append the ledger row** before you start: commit, what this round
   believes, verdict path.

## 2. While you fix

* **Address findings point by point, in the reviewer's numbering.** Where a
  finding is wrong, push back with evidence. Where your earlier claim was
  wrong, say so plainly and correct it **at its source** — the issue body, the
  PR body, the comment — not only in new text. #96's two dated correction
  blockquotes are the house style.
* **Apply substitutions verbatim from the verdict.**
* **Re-measure every number in a substitution.** Never copy one.
* **Scope discipline.** Fix the findings. Name adjacent defects and **file**
  them; do not fold them in silently. A behaviour change beyond the verdict is
  a listed decision, never a smuggled one.
* **Auto-apply review-requested *minor* changes** without waiting. Genuine
  scope changes, or reversals of a review directive, go back for review.

## 3. Red before green

Every new test guarding a behaviour change must be **shown failing before the
fix**. The commit partition:

| | |
|---|---|
| **c0** | characterization pins on existing symbols (green) |
| **c1** | behaviour-preserving refactor + new symbols + green pins on them |
| **c2** | **red differentials ONLY** — every added test named in the red run's failure list |
| **c3** | the fix. Touches **no** test file, **no** pin, **no** `scripts/`, **no** `.github/` |

**In this repository "red" for a `(:test)` is a LOCAL red** — the suite
compiles in CI and executes only in the local simulator (`FACTS.md` §1.2). So
the red evidence for c2 is a local `monkeydo` log quoting the failing case by
name, attached to the PR body. For the model, the red can be a CI red instead:
`model-parity` and the R suite run on every push, and a c2 that changes a
fixture expectation before c3 changes the model reds there.

**Open the PR at c1 and let each run complete before the next push, or the red
evidence never exists.** `cancel-in-progress: true` kills in-flight runs, so a
fast second push deletes the red run you were relying on.

## 4. The pin must call the thing it pins

A test that re-implements logic instead of calling it **pins nothing**. The
parity mirror (`tools/crosscheck/tank_model.py`) is a **port** of `TankModel`,
not the shipping code; it pins R against the mirror, and Monkey C only
transitively. A `(:test)` that drives `TankModel.stepModel` directly is the
pin on the shipping code.

So: **mutation-test every pin you add.** Break the thing it guards, run the
suite, report the numbers — *"reverting X reds exactly case Y, N−1/N."* If it
does not red, the test is decoration, and decoration is worse than nothing
because it reads as coverage.

## 5. Pins and the ceiling

* Any `(:test)` **addition, removal or rename** edits
  `scripts/expected_tests.txt` **in the same commit**.
* A **file-scope** `(:test)` costs one `globals` member on `fenix6pro`. Check
  the current headroom in `FACTS.md` §5.1 before you add several — the figure
  is deliberately not repeated here. A `(:test)` inside a `module { }` block
  costs none.
* One runner-free case reds locally on Windows for a privilege reason and is
  green in CI (`FACTS.md` §4.1). **Do not "fix" it and do not report it as a
  regression.**

## 6. When to stop patching

* **Three rounds running finding a defect in the previous fix** → the function
  has a structural problem, not a sequence of typos. Extract a pure seam and
  pin it (calling the shipping code, per §4), or split the issue.
* **After the second wrong framing of a claim, delete the claim.**
* **Body rewrites cap at three rounds.**
* **Five rounds on one function**: ask whether you are converging or circling.
  Do not run a sixth of the same shape.

## 7. Closing the round

* **Post one reply comment per round addressed**, in the reviewer's numbering.
* **Update the PR body in place.** It is the record.
* **Append the ledger row**: what the gate found, verdict path.
* **Do not start the next round until a new verdict exists.**
* **You do not gate your own fix.**
* Every comment ends with a `---` rule and the attribution line.

---

## Mid-work hazards

* **Never `git add .` / `-A` / `commit -a`** (`FACTS.md` §4.2).
* **Never kill a shared simulator** (`FACTS.md` §4.5).
* **Never write a developer key into the workspace** (`FACTS.md` §4.4).
* **`set -o pipefail`** for anything whose result you quote (`FACTS.md` §2.6).
* **The project lives in `connectiq/`**; the suite runs locally on `edge1050`;
  the release export compiles all 15.
