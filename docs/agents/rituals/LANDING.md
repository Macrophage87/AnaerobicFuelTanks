# Ritual: landing a branch

Read this **when you are landing**, not when you think you might need it.

The orchestrator lands. Landing is a **gate action**: taken only on explicit
direction, never on your own initiative however green the PR.

Facts and canonical command forms: `docs/agents/FACTS.md`.

---

## The checklist

Run all seven. A landing that skips one is not a landing that went faster.

### 1. Fresh fetch

```sh
git fetch origin main
```

Not the local `main`, and not `origin/HEAD` — measured 2026-09-05, `origin/HEAD`
pointed at a branch 42 commits behind `origin/main` (`FACTS.md` §4.3).

### 2. The base has not moved under you

```sh
git rev-parse origin/main
git merge-base --is-ancestor origin/main <head-sha> ; echo "ff=$?"
```

`ff=0` means `main` is an ancestor of your head. `ff=1` means something landed
under you since the gate: **re-gate**, do not merge. Branch protection is
`strict` (up to date required), so GitHub will refuse anyway — but re-gating is
the point, not the refusal.

### 3. CI verified from the run object, on the exact commit

```sh
gh api repos/Macrophage87/AnaerobicFuelTanks/commits/<full-sha>/check-runs \
  --jq '.check_runs[] | "\(.name)\t\(.conclusion)"'
```

These must read `success`: `ci-required`, `Compile (edge1050)`,
`Compile (fenix6pro)`, `R model tests (testthat)`, `R parse + lint`,
`Model parity (R vs Python mirror)`, `Manifest app-id lint`,
`Agent-loop tooling (runner-free)`. `CIQ (:test) headless (best-effort)` will
also read `success` — **it skips green when the simulator segfaults** (#61), so
its success is not evidence the suite ran. **Use the full SHA**, the one you
are about to push.

`ci-required` is the only name branch protection requires. It uses the
default `if: success()`, so an upstream failure **skips** it rather than
failing it (`FACTS.md` §1.2) — read the individual checks, not the aggregate.

Two attempts of one run on the same runner pool is a **flake check, not
independent evidence** — phrase it that way.

### 4. The scope diff is explicable file by file

```sh
git diff --stat origin/main...<head-sha>
```

Read every path. A file you cannot explain in one sentence is either scope
creep to be split out or a mistake to be reverted. Adjacent defects get
**filed**, not folded in.

### 5. A delta read of all changed prose

```sh
git diff origin/main...<head-sha> -- '*.md'
git diff origin/main...<head-sha> -- 'connectiq/source/*.mc' | grep -n '^[+-].*//'
```

The two commands are separate on purpose: a `//` filter over `'*.md'` discards
markdown. Ask of each changed sentence:

* does the **cross-reference resolve**, and does the target say what the
  pointer claims?
* is every **figure** reproducible from something committed?
* does it state what the code **calls**, or what a decoder **sees**? Only the
  first is allowed without a `[Local]` measurement.
* does it assert a **gap** where a record-scope field **latches**?
* does the change make a statement **elsewhere in the file** false? (The #97
  fix left `DualTankView.mc:296`'s "returns null" standing three lines above
  its own correction.)
* does it move one of the **hand-synced copies** (`DISPATCH.md` I=2: the three
  model implementations, the parameter table in four documents, the
  `AGENTFACT` lines) without the others?

### 6. Commit prose says why it is known to be correct

Not just what changed. Name the differentials, the review round, and the
retractions. A retraction names the wrong claim.

**No internal model or vendor identifiers** in anything pushed — commit
messages, PR bodies, code comments, docs. No CI job scans for this. Build the
pattern at the shell from the strings you were told not to publish; do not
commit it.

### 7. Push the verified hash, not the branch name

```sh
git push origin <full-sha>:refs/heads/<branch>
```

The hash is what you verified. A branch name resolves at push time.

---

## Merge method

If the shared feature branch **continues into a follow-up PR**, use a **merge
commit** — this repository's merged PRs are merge commits (#97, #93). A squash
or rebase leaves the branch diverged from `main` and makes the next PR's diff
re-present everything already merged.

Use a closing keyword (`Fixes #N`) in the PR body. "Does not close #N" also
closes #N; check `gh pr view N --json closingIssuesReferences` after every body
edit, and once more after the API's propagation delay.

---

## After landing

* **Restart the branch from the new `main`.**
  `git fetch origin main && git checkout -B <branch> origin/main`.
* **Landed history is never rewritten.**
* **Partial resolution**: close the parent as resolved, file a follow-up
  capturing the remainder, note the split on both (#96 → #98, #99 is the
  house pattern). The close comment states plainly what was **not** done.
* **Post-merge recommendation** (`reviewer_agent.MD`): name the next issue and
  the pipeline stage of each open epic.
* Every comment you author ends with a `---` rule and the attribution line.

---

## Mid-work hazards that fire during a landing

* **Never `git add .`, `git add -A` or `git commit -a`** (`FACTS.md` §4.2).
* **Never kill a shared simulator** (`FACTS.md` §4.5).
* **`set -o pipefail`** for anything whose result you quote (`FACTS.md` §2.6).
