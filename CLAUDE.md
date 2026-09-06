# CLAUDE.md

Guidance for AI agents working in this repository.

## Issue triage — priority labels

Every GitHub issue must carry a `priority:` label that matches the severity
stated in its title/body. The four labels already exist in the repo:

| Severity | Label                |
|----------|----------------------|
| Critical | `priority: critical` |
| High     | `priority: high`     |
| Medium   | `priority: medium`   |
| Low      | `priority: low`      |

- When **filing** a new issue, add the matching `priority:` label alongside the
  type label (`bug`, `enhancement`, or `documentation`).
- When an issue's severity is **reassessed**, update its `priority:` label to match.
- Titles in this repo prefix the severity in brackets (e.g. `[High] …`); use that
  as the source of truth for the priority label.

## Agent loop

The orchestration loop (triage, propose, implement, gate, merge, release) is
run by three project agents in `.claude/agents/` -- `ciq-orchestrator`,
`ciq-implementer`, `ciq-reviewer` -- and documented under `docs/agents/`:

| Read | When |
|---|---|
| `docs/agents/FACTS.md` | first, always: environment contract, command forms, measurements, defect classes; the `AGENTFACT` lines are machine-checked by `scripts/check_agent_facts.py` in the required `test-tooling` job |
| `docs/agents/DISPATCH.md` | sizing or triaging an issue (the five-axis band metric and the `Dispatch:` header) |
| `docs/agents/GATE_PROTOCOL.md` | gating, re-gating or writing a verdict |
| `docs/agents/rituals/` | landing, releasing, a fix round, turning a recording into evidence |
| `docs/agents/LESSONS.md` | the StrongRow lessons this loop was built from |
| `.claude/skills/release-connectiq/SKILL.md` | cutting, publishing or superseding a release (the `release-connectiq` skill; invoke it rather than improvising the ritual) |

The Connect IQ project lives in `connectiq/`, not the repository root. Never
`git add .` / `-A`: `.claude/worktrees/` holds other sessions' checkouts
(ignored since the loop landed, but stage named paths anyway).
