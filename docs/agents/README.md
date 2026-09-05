# Agent loop documentation

The versioned half of the orchestration loop. The agent **role definitions**
live in `.claude/agents/` (`ciq-orchestrator`, `ciq-implementer`,
`ciq-reviewer`); everything they would otherwise carry as duplicated prose
lives here, so it is reviewable in a pull request and checkable by CI.

| File | Read it when |
|---|---|
| [`FACTS.md`](FACTS.md) | **always the first stop.** One copy of every volatile shared fact: environment contract, canonical command forms, measurement rules, VCS hazards, recorded measurements, defect classes. Every measurement pinned to the commit it was taken at. |
| [`DISPATCH.md`](DISPATCH.md) | sizing a task, filing an issue, or triaging — the five-axis band metric with this repository's own anchors, and the `Dispatch:` header format |
| [`GATE_PROTOCOL.md`](GATE_PROTOCOL.md) | gating, re-gating, or writing a verdict |
| [`rituals/LANDING.md`](rituals/LANDING.md) | landing a branch |
| [`rituals/RELEASE.md`](rituals/RELEASE.md) | cutting a release |
| [`rituals/FIX_ROUND.md`](rituals/FIX_ROUND.md) | addressing a verdict |
| [`rituals/FIELD_DATA.md`](rituals/FIELD_DATA.md) | turning a recording into evidence |
| [`LESSONS.md`](LESSONS.md) | the StrongRow narrative these files were distilled from — platform facts and process lessons, with the incidents that taught them |

Two rules govern how these files relate to the definitions that point at them.

**Cut and point, never summarize and keep.** A definition holds its identity,
its role-specific behaviour, and a one-line pointer per topic. A paraphrase
kept "for convenience" is a second copy that drifts independently — the exact
failure this split exists to prevent. This repository already has one instance
of the adjacent failure: `README.md` states the Monkey C is "Not compiled in
CI" while `.github/workflows/ci.yml` has compiled it on two devices since
PR #48 (`FACTS.md` §6).

**Pointers bind to the verb, not to self-assessment.** "When landing, read the
landing ritual" — not "read it if the landing looks tricky". The rounds that
most need a ritual's constraints are rounds already going wrong, so recognition
must not depend on the agent noticing it is in one.

**Mid-work hazards stay inline** in every definition — never `git add` a
directory, never kill a shared process, the project lives in `connectiq/`,
`set -o pipefail`. They fire mid-task rather than at ritual time, so an
on-demand file cannot deliver them in time.

## What CI checks here

`scripts/check_agent_facts.py` re-derives five figures in `FACTS.md` from the
tree on every run of the required `test-tooling` job — the container digest,
the manifest device count, the pinned `(:test)` count, the quoted `globals`
ceiling note and the whole developer-field id→name map. Its self-test is
`scripts/test_check_agent_facts.py`. The same job runs the pin cross-check
(`scripts/check_expected_tests.sh`), the ceiling-note arithmetic
(`scripts/check_ceiling_notes.py`) and the literal check
(`scripts/check_mc_literals.py`), each behind its own hermetic RED/GREEN suite.
Everything else in these files is prose with a commit pin and nothing more;
`FACTS.md` §9 says so in its own words.

## What was deliberately not installed from the kit

The StrongRow kit also ships a container test harness
(`run_ciq_tests.sh` + `check_ciq_tests.py`), a manifest-driven device matrix
(`list_devices.sh` + `check_manifest_appid.py`), a comment cross-reference
checker keyed on `test_` names, and a dispatch re-scoring harness. None fits
this repository as it stands: the headless simulator segfaults in CI (#61), the
compile matrix is a fixed pair, the tests are `camelCase`, and no rubric
re-anchoring has been run yet. Each is a candidate for its own issue once the
prerequisite exists; `FACTS.md` §1.2 and `DISPATCH.md` §5 say which.
