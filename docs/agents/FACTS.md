# Canonical facts for the agent loop

One copy of every volatile fact the orchestration loop shares. Agent role
definitions hold their identity and their role-specific behaviour; anything
below is **pointed at, never restated**. A paraphrase kept "for convenience"
is a second copy that drifts independently, which is the defect this file
exists to stop.

**How to read a fact here.** Every measurement is pinned to the commit it was
taken at. A fact with no pin is not a fact. If a claim below disagrees with the
tree you are working in, the **tree wins** — say so in your report and fix this
file, do not work around it.

**If this file is absent from the checkout you are on**, say so explicitly in
your report rather than reconstructing a fact from memory. It is versioned with
the code precisely so that "which version of the rule applied" is answerable.

Measurements below were taken at **`30b2b99`** (`origin/main`, the merge of
PR #97) on **2026-09-05** unless a line says otherwise.

Machine-checked by `scripts/check_agent_facts.py`, wired into the required
`test-tooling` job. Five of the figures here are re-derived from the tree on
every CI run; the rest are prose and carry only the pin. §9 says which is which.

---

## 1. Environment contract

### 1.1 The project lives in `connectiq/`, and the SDK is available locally

The Connect IQ project is **not** at the repository root: `connectiq/manifest.xml`,
`connectiq/monkey.jungle`, `connectiq/source/` (four files: `DualTankApp.mc`,
`DualTankView.mc`, `TankModel.mc`, `Tests.mc`), `connectiq/resources/`. Every
`monkeyc` invocation runs from `connectiq/`; every checker in `scripts/`
defaults its root to `connectiq/source`.

The SDK is installed on the maintainer's machine. Verified 2026-09-05:

```
~/AppData/Roaming/Garmin/ConnectIQ/Sdks/connectiq-sdk-win-9.2.0-2026-06-09-92a1605b2
~/AppData/Roaming/Garmin/ConnectIQ/Devices/      # all 15 manifest products present
```

`monkeyc` is **not on `PATH`**; call `<sdk>/bin/monkeyc.bat` by absolute path
(it needs Java — Temurin 17 is installed). `openssl` is at `/mingw64/bin/openssl`
(3.5.6). `python3` is 3.14 via the Windows Store shim.

`README.md:211` says the Monkey C is "Not compiled in CI". **That claim is
false at `30b2b99`** (§1.2) and should be corrected at its source, not
propagated.

### 1.2 What CI runs, and what it does NOT run

`.github/workflows/ci.yml` at `30b2b99`, verified from the check-runs object
for that commit (`gh api repos/Macrophage87/AnaerobicFuelTanks/commits/<sha>/check-runs`):

| Check name (as GitHub reports it) | Job id | Required? | What it proves |
|---|---|---|---|
| `Compile (edge1050)`, `Compile (fenix6pro)` | `test` | yes | `monkeyc -t -l 1` **compiles** — the `(:test)` sources included — on those two devices only |
| `CIQ (:test) headless (best-effort)` | `ciq-test` | **no** | tries to **execute** the suite under Xvfb; the simulator **segfaults after `SetLayout`** and the job skips green (#61, two levers falsified in PRs #81 and #84) |
| `R parse + lint` | `r-lint` | yes | R syntax + the deploy-manifest freshness gate |
| `R model tests (testthat)` | `r-test` | yes | the R model suite, and that `tools/crosscheck/fixtures/` regenerate byte-identical |
| `Model parity (R vs Python mirror)` | `model-parity` | yes | the Python mirror of `TankModel` matches the R reference within 0.1 J per second |
| `Manifest app-id lint` | `manifest-lint` | yes | app id shape; CP/W′ keep the sentinel-0 default (#42); the FIT developer-field byte budget — ≤ 32 B per message type for a data field, summed over the `createField` call sites in every `.mc` under `connectiq/source/` (#98 item 2) |
| `Agent-loop tooling (runner-free)` | `test-tooling` | yes | this file's `AGENTFACT` lines, the `(:test)` pin, the ceiling note, the literal check — each behind its own RED/GREEN self-test |
| `ci-required` | `ci-required` | **the only name branch protection requires** | aggregator over the required jobs (`needs:`), strict up-to-date, admins enforced |

**The `(:test)` suite does not execute in CI.** A green `Compile` is
compile-only evidence. The enforced numeric guard on the model is
`model-parity`, and it guards the Monkey C **transitively** through a
line-for-line Python port (`tools/crosscheck/test_parity.py`'s own docstring
says so). Anything a `(:test)` asserts that the mirror does not (persistence
`validateBlob`, `decideDropout`, `writeField` null-safety, settings
finiteness) is proven only by a **local** simulator run:

```sh
cd connectiq
<sdk>/bin/monkeyc.bat -f monkey.jungle -d edge1050 -o bin/app-test.prg -y <key>.der -t -l 1
<sdk>/bin/connectiq.bat &            # once
<sdk>/bin/monkeydo.bat bin/app-test.prg edge1050 -t
```

`monkeydo` returns non-zero **even when every test passes** (upstream's
`tester.sh` documents it). Read the `PASSED (passed=N, failed=0, errors=0)`
line, never the exit code. No committed script parses that line yet; the
kit's `check_ciq_tests.py` is the candidate when #61 promotes `ciq-test`.

`ci-required` uses the default `if: success()` — so when an upstream job
**fails**, the aggregator is **skipped**, and branch protection treats a
skipped required check as satisfied. The StrongRow kit's `if: always()` +
assert form closes that hole; it is not applied here yet and is worth its own
issue.

### 1.3 The digest-pinned CI container

```
ghcr.io/matco/connectiq-tester@sha256:7a6f586cb0e0393ff288da09cf27b6dad40a0058a346c529b99fd0fc19858f0f
```

SDK 9.2.0. The digest appears on **two** `image:` lines in `ci.yml` (`test`
and `ciq-test`) with **no YAML anchor**; `scripts/check_agent_facts.py`
requires every `image:` digest in the workflow to be identical and equal to
the line in §9, so the two copies cannot drift. **The digest is the pin; the
tag is a comment.** Bump it as its own commit with its own CI run, before the
change that needs it.

Running the container locally needs `--entrypoint bash` (the image's
`ENTRYPOINT` runs upstream's `tester.sh`, which compiles with `-l 3` and
launches the simulator), a clean archive extracted with `core.autocrlf=false`
(§4.1), and `-w /work/connectiq`. **The Docker daemon was down when measured**
(2026-09-05: `docker version` exits 1). When it is down, **say the container
run did not happen** (§3.1), and mind the pipeline trap in §2.6.

### 1.4 Devices

`connectiq/manifest.xml` declares **15** `<iq:product>` entries: `edge530`,
`edge540`, `edge830`, `edge840`, `edge1030`, `edge1030plus`, `edge1040`,
`edge1050`, `fr255`, `fr255m`, `fr955`, `fr965`, `fenix6pro`, `fenix7`,
`fenix7x`. CI compiles **two** of them (`edge1050`, `fenix6pro`); the release
export (`monkeyc -e`) compiles all 15 and prints `N OUT OF M DEVICES BUILT` —
**read N and M off the log for every release**, the `.iq` cannot be enumerated
afterwards. `fenix6pro` is the device that binds the `globals` ceiling (§5.1).
Measured 2026-09-05 with a throwaway key on a clean archive of `30b2b99`:
`monkeyc -e` printed **`28 OUT OF 28 DEVICES BUILT`** — 28 device parts across the
15 products (several products carry two parts), export rc 0.
Every manifest device has a local device definition (verified 2026-09-05), so a
full-matrix local build is possible; the CI matrix is a fixed pair in the
workflow, not derived from the manifest.

---

## 2. The command block

Pinned forms. Sweep for bare forms; a bare form is a defect even when it
happens to return the right answer this time.

### 2.1 `gh` — field-selected, with a saturation check

```sh
gh issue list --state open --limit 200 --json number,title,state,labels
gh issue view N   --json number,title,state,body
gh pr view N      --json number,state,headRefOid,statusCheckRollup
gh api repos/Macrophage87/AnaerobicFuelTanks/commits/<full-sha>/check-runs \
  --jq '.check_runs[] | "\(.name)\t\(.conclusion)"'
gh api repos/Macrophage87/AnaerobicFuelTanks/branches/main/protection
```

**A returned count equal to the limit means TRUNCATED.** The backlog is 12 open
at `30b2b99` (§5.4), under the 30-row default page; that is why the rule is
stated now rather than after it bites.

### 2.2 `git show origin/main:<path>` needs `MSYS_NO_PATHCONV=1` on this machine

Measured 2026-09-05 in Git Bash: `git show origin/main:.github/workflows/ci.yml`
was rewritten by MSYS path conversion into
`origin\main;.github\workflows\ci.yml` and failed with "ambiguous argument".
The form that works:

```sh
MSYS_NO_PATHCONV=1 git show origin/main:.github/workflows/ci.yml
git show "origin/main:connectiq/source/DualTankView.mc"    # no leading dot: fine either way
```

### 2.3 Search — exclusions pinned, count before read

`.claude/worktrees/` sits **inside** this repository's root and holds other
sessions' working copies (§4.2), so an unexcluded search reports every hit N
times over against several different commits. Build output lives under
`connectiq/bin/`.

```sh
grep -rn --exclude-dir=bin --exclude-dir=.git --exclude-dir=.claude \
         --exclude-dir=__pycache__ --exclude='*.pdf' --exclude='*.png' -c PATTERN .
```

### 2.4 Logs bounded at the source

Line-cap and filter at the command (`| head -n`, `sed -n 'A,Bp'`, `--jq`), not
after the output has landed. **Never re-paste a region already quoted in this
session — cite it.**

### 2.5 Waiting is not model work

```sh
gh run watch <run-id> --exit-status > /dev/null 2>&1; echo "conclusion=$?"
```

### 2.6 `set -o pipefail` for anything whose result gets quoted

In a pipeline the exit status is the **last** command's. `docker version 2>&1 | head -1`
reports `0` with the daemon down; `set -o pipefail` (or `${PIPESTATUS[0]}`)
reports the truth. The StrongRow lessons record a verification that never ran
being reported as in flight on exactly this mechanism.

### 2.7 A clean archive, and the ceiling probe

```sh
D=<scratch>; mkdir -p "$D"
git -c core.autocrlf=false archive --format=tar origin/main | tar -x -C "$D"
cd "$D/connectiq"
<sdk>/bin/monkeyc.bat -f monkey.jungle -d fenix6pro -o "$D/app.prg" -y <scratch-key>.der -t -l 1
```

The key lives in the scratch directory, **never** in the workspace (§4.4). To
re-measure the ceiling, drop N throwaway `(:test) function testZzProbeN(logger) { return true; }`
lines into a scratch file under `source/`, read `Found X members` off the
error, and confirm `X − N` by building at N = free (green) and N = free + 1
(red). That is how §5.1 was produced.

---

## 3. Measurement and verification rules

### 3.1 Never claim a verification you did not run

If the tool was unavailable, the daemon was down, or the run was cancelled,
**say that**. Retract a wrong claim by name, at the place the claim lives, not
by silently editing it away. Issue #96 is this repository's model: its body
carries two dated correction blockquotes naming exactly which earlier claims
were wrong (memory pressure, "throws", the #32 attribution, the shared budget,
`eta` droppable) and what replaced them.

### 3.2 What no `(:test)` in this repository can reach

* **No `(:test)` can obtain a `Session`**, so `createField` is unreachable from
  the suite. `Tests.mc:444-458` (`testWriteFieldNullSafe`) exercises the static
  `writeField` seam with a `null` handle; it cannot create a field. **The v0.6
  load crash (#96) was invisible to every test and to CI** for this reason: it
  fired inside `initialize()` on the device, on every target, deterministically.
* **No `(:test)` can obtain a graphics `Dc`.** Layout selection and rendering
  (`onUpdate`, `drawVertical`, `drawFull`) are field-only.
* **A comment cannot be red by any test.** Comments are stripped from the
  build. `DualTankView.mc:296` still says `createField()` "returns null when the
  FIT field budget/memory is exhausted" — #96 established that it raises an
  **uncatchable** `Out Of Memory Error` instead; the sentence beside the #97
  fix says so, the older one three lines above it does not (tracked in #98).
* **Nothing here decodes a file this app wrote.** `tools/calibrate/R/model.R`'s
  `read_power_raw()` **skips** developer-field definitions by size
  (`test-read_power_raw.R` pins it); `tools/crosscheck/` reads only R-generated
  CSV fixtures. The #100 lag measurement was made from a saved FIT with a
  decoder outside the repository; nothing committed can regenerate it (§6).
* **On-device load is field-only.** CI compiled v0.6 green on both devices and
  the shipped build could not load. A `[Local]` record-and-save gate on the
  Edge 1050 is the release gate (#98 item 1).

### 3.3 Record-scope FitContributor fields LATCH

Skipping a `setData` **re-emits the previous value** on every subsequent
record. It never produces a gap. This repository already writes every record
field on every tick, including the held and skipped paths
(`DualTankView.mc:812-816`, `:836-840`, `:876-880`, `:914-918`, live at
`:926-933`), with the comment "gap-free deficit stream (held)". Keep it that
way: a gate on a FIT write fails **open**, and "stop writing during X"
fabricates a timeline rather than omitting one.

### 3.4 A comment may state what the code CALLS, never what a decoder SEES

Until a `[Local]` simulator or decoder session has measured it. `[Local]`
issues carry: the `[Local]` title prefix, an opening ⚠️ blockquote, the
`local-test` label, and byte-exact pass criteria. **The `local-test` label does
not exist in this repository yet** (13 labels at `30b2b99`, none of them);
create it before filing the first one.

### 3.5 Clocks

`nowSec()` is `Time.now().value()` (unix seconds) — wall clock, not
`System.getTimer()`. The one `System.getTimer()` use is `mPauseAtMono`
(`DualTankView.mc:667`, #41), tested with `mPauseAtMono >= 0` at `:682` and
`-1` as "not set". `System.getTimer()` is a **signed 32-bit** millisecond
counter and is **negative from 24.9 to 49.7 days of device uptime**; during
that half the `>= 0` test reads a valid stamp as "not set" and the resume path
falls back to the wall-clock branch. That is a degradation (loss of the
clock-jump immunity #41 added), not a corruption, and it is **observed at
source, not measured on a device** — file it, do not fix it in passing.

---

## 4. Version-control hazards

### 4.1 CRLF: `core.autocrlf=true`, no root `.gitattributes`

Verified at `30b2b99`: `git config core.autocrlf` is `true` on the maintainer's
machine; the root has **no** `.gitattributes` (only `tools/calibrate/` has
one). `git ls-files --eol` reports `i/lf w/crlf` for every text file. CI checks
out LF and never sees the difference.

Measured consequence, 2026-09-05: `scripts/test_list_tests.py` reds **one**
case locally — "symlinked files, symlink cycles and FIFOs are skipped, not
followed" — with `OSError(22, 'A required privilege is not held by the client')`,
because Windows withholds the symlink-creation privilege. 34/35 locally; 35/35
in CI is the expectation. **Do not "fix" it and do not report it as a
regression.** The other suites (`test_check_ceiling_notes` 10/10,
`test_check_mc_literals` 8/8, `test_check_agent_facts` 25/25,
`test_check_fit_budget` 30/30) are green on both. (This line read
`test_check_agent_facts` **21/21** when it landed; the suite in the tree at
`cea95c8` has 25 cases, so the figure was stale on arrival. Re-measured
2026-09-05 — the tree wins.)

`scripts/check_mc_literals.py` exists because `monkeyc` accepts a raw newline
inside a string literal with no diagnostic; on a CRLF checkout that ships a
stray CR inside the compiled constant. Build releases from a clean archive
(§2.7), never the working tree.

### 4.2 Nested worktrees live inside the repository root

`git worktree list` shows checkouts rooted at `<repo>/.claude/worktrees/`.
They are ignored by the root `.gitignore` since this file landed, but
**never `git add .`, `git add -A` or `git commit -a`** — stage named paths.

### 4.3 Read `origin/main`, not the working tree — and not `origin/HEAD`

Measured 2026-09-05: `origin/HEAD` pointed at
`origin/claude/anaerobic-metabolism-cycling-bxybzy`, a branch **42 commits
behind `origin/main`** (it predates `TankModel.mc`, `Tests.mc` and the CI
workflow), so a worktree created from the default ref started stale. Fixed
locally with `git remote set-head origin main`; GitHub's default branch is
`main`. Before citing source:

```sh
git fetch origin main
git show origin/main:connectiq/source/DualTankView.mc
```

### 4.4 Never write a developer key into the workspace

`connectiq/README.md` and `connectiq/build.sh` show `openssl genrsa -out developer_key.pem`
relative to `connectiq/`. `connectiq/.gitignore` covers `developer_key*`,
`*.der`, `*.pem` — but a destroyed account-bound key is not recoverable from
`.gitignore`. Throwaway keys go in a scratch directory; the release key is
referred to by absolute path only (`CIQ_KEY=` in `build.sh`).

### 4.5 Never kill shared processes

A simulator may be serving another agent's run. Start your own; kill only what
you started.

---

## 5. Recorded measurements

### 5.1 The `fenix6pro` `globals` ceiling, and current headroom

`fenix6pro` caps module `globals` at **253** members (inclusive); a file-scope
`(:test)` costs one member; a `(:test)` inside a `module { }` block costs none.
Measured by bisection on a clean archive of `30b2b99`, SDK 9.2.0, 2026-09-05
(§2.7 recipe): 400 stubs reported `Found 427 members`; 226 stubs `BUILD
SUCCESSFUL`; 227 stubs `Found 254 members in module 'globals', exceeding the
limit of 253`. The single copy in source, `connectiq/source/Tests.mc`, reads:

    CEILING 30b2b99 fenix6pro: 27 used of 253, 226 free -- the 227th file-scope (:test) added reds

`scripts/check_ceiling_notes.py` enforces the arithmetic and that this
quotation is byte-identical to the source copy; `scripts/check_agent_facts.py`
enforces that §9 quotes the same numbers. Neither can tell you the note is
still current — re-measure when file-scope declarations are added. `edge1050`
does not bind; a green `edge1050` build says nothing about this.

### 5.2 Pinned test count

**16** `(:test)` functions, all file-scope in `connectiq/source/Tests.mc`,
matching `scripts/expected_tests.txt` exactly (`bash scripts/check_expected_tests.sh`
at `30b2b99`: "OK: 16 (:test) function(s) under connectiq/source/ match
scripts/expected_tests.txt exactly."). Measured with `scripts/list_tests.py`,
never added up.

Any `(:test)` addition, removal or rename edits `scripts/expected_tests.txt`
**in the same commit**. The check closes drift, not coordinated shrink.

### 5.3 The developer-field id map and the byte budget

**7** live developer fields at `30b2b99`, parsed from the literal
`createField` calls in `connectiq/source/DualTankView.mc`:

| id | name | type | message | bytes |
|---:|---|---|---|---:|
| 0 | `PCr_J` | FLOAT | RECORD | 4 |
| 1 | `GLY_J` | FLOAT | RECORD | 4 |
| 2 | `PCr_cons` | SINT16 | RECORD | 2 |
| 3 | `GLY_cons` | SINT16 | RECORD | 2 |
| 4 | `PCr_depleted_kJ` | FLOAT | SESSION | 4 |
| 5 | `GLY_depleted_kJ` | FLOAT | SESSION | 4 |
| 18 | `Deficit_kJ` | FLOAT | RECORD | 4 |

**RECORD = 16 B, SESSION = 8 B, against 32 B per message type** — the data-field
quota confirmed on hardware in #96 (a full app gets 256 B). Ids **6–17** are
declared as `FID_CFG_*` constants for the twelve config session fields removed
in #97 and are **reserved, not live**; `cfgField()` and `writeCfgFields()` are
inert while `mCfgFields == null`. A developer field id is unique per
`field_description`; re-using one silently re-labels every file recorded with
it. The budget is **per app**, not shared across co-installed data fields
(#96, from a saved FIT with four apps writing 53 B to RECORD) — but the
maintainer reports memory failures with several data fields installed, and
that observation is field data this repository cannot yet regenerate.

**The byte budget is machine-checked** since #98 item 2.
`scripts/check_fit_budget.py` re-derives the per-message-type totals from the
`createField` call sites in **every `.mc` file under `connectiq/source/`** —
reading each twice, raw and comment-stripped, and refusing a disagreement, as
`check_agent_facts.py` does — and fails if any message type exceeds 32 B. It
runs in the required `manifest-lint` job behind its own hermetic RED/GREEN
self-test. No filename is pinned: the totals are summed across files, because
the quota is per app per message type, and an id re-used across two files is
refused. It **runs nothing**: it is the arithmetic #96 got wrong, not evidence
that a device accepted the fields (§3.2 — only a record-and-save session
answers that).

One blind spot remains, and it is deliberate: **a `createField` whose *name
argument is a variable* is not counted.** Such a call creates no field the
checker can name, so its bytes are invisible. At `cea95c8` the only instance
is the inert `cfgField()` helper (`DualTankView.mc:332` at `cea95c8`, no call
sites); PR #105 deletes it, so the instance may disappear while the blind spot
does not. **#99 has to extend the checker before reviving any variable-named
create path, not after.**

### 5.4 Backlog size

**12** open issues at `30b2b99`, **0** of them carrying a `Dispatch:` header,
**0** open PRs. Cited to make the saturation rule concrete; it will drift.

### 5.5 Releases

Three tags: `0.1`, `v0.6`, `v0.7`. `v0.6` is the newest release **not** flagged
prerelease, so GitHub's `latest` points at it — and **v0.6 is the build that
crashes at load** (#96). `v0.7` (prerelease, from `30b2b99`) is the fix. Asset
names: `DualTank.iq` on v0.6, `DualTank-0.7.iq` on v0.7 — the version belongs
in the filename (release ritual §5). Store-Version 6 is the crashing build;
the store resubmission is #96's remaining blocker.

**Static image size is not the memory pressure.** Measured 2026-09-05 on a
clean archive of `30b2b99`, local SDK 9.2.0, `monkeyc -r -l 1` (release, debug
stripped), throwaway key, against each device's `compiler.json` `datafield`
`memoryLimit`:

| device | release `.prg` | limit | share |
|---|---:|---:|---:|
| edge530 / edge830 | 26,140 B | 131,072 B | 19.9 % |
| edge540 / edge840 | 22,316 B | 131,072 B | 17.0 % |
| edge1030 / edge1030plus | 26,220 B | 131,072 B | 20.0 % |
| edge1040 | 22,988 B | 131,072 B | 17.5 % |
| edge1050 | 29,036 B | 131,072 B | 22.2 % |
| fenix6pro | 25,228 B | 131,072 B | 19.2 % |
| fr255 / fr255m | 21,388 B | 262,144 B | 8.2 % |
| fr955 / fenix7 / fenix7x | 21,708 B | 262,144 B | 8.3 % |
| fr965 | 30,188 B | 262,144 B | 11.5 % |

A build **without** `-r` is 124–132 KB on the same devices — that is debug
information, not loaded code, and it is why a first survey read "100.3 % on
edge1050" for a build that loads fine. Runtime **peak heap** is not measured
by anything here; the simulator's memory view is the only instrument, and it
has not been read for this app. The `(:test)` helpers in `Tests.mc` do not
ship in the `-r` image (verified: `tmMake` absent from the release `.prg`).

---

## 6. Defect classes this repository keeps re-learning

* **A claim stronger than its evidence.** #96 shipped three of them in its
  first body (device memory, "throws", #32's 18→19 fields) and one in #34
  ("returns null on exhaustion" — an inference no SDK page documents).
* **A number nothing committed can regenerate.** #100's cross-correlation
  table and threshold fit came from a saved FIT decoded outside the tree.
* **A documentation claim about the environment that is false.** `README.md:211`
  "Not compiled in CI", eight weeks after PR #48 made it compile.
* **A test that re-implements logic instead of calling it pins nothing.** The
  parity mirror is a port, not the shipping code; it guards Monkey C only
  transitively, and its docstring says so. A `(:test)` that drives `TankModel`
  is the direct pin — and it only runs locally (§1.2).
* **The near neighbour.** #97 fixed the crash; #98 and #99 are the neighbours
  it left (stale comments, the budget guard, the gated return of config).
* **The wrong pair.** 32 B is per message type per app; 53 B was four apps'
  RECORD total; 56 B was this app's SESSION. Say which.
* **Absence rendered as a value.** #76: an unconfigured ride records a
  complete, plausible dataset at CP 250 / W′ 20000 the athlete never chose.

---

## 7. Permission allowlist

Tracked at `.claude/settings.json`, owned by the human. Read-only `git` and
`gh`, the `check_*` / `test_*` scripts, file inspection. Everything that
changes state — `git push`, `git commit`, `gh pr merge`, `gh issue close`,
`gh release create`, `docker run`, any write to `.github/` — stays behind the
prompt. **The loop never widens its own permissions.**

---

## 8. Rituals and the dispatch metric

| When you are… | Read |
|---|---|
| landing a branch | `docs/agents/rituals/LANDING.md` |
| cutting a release | `docs/agents/rituals/RELEASE.md` |
| running a fix round | `docs/agents/rituals/FIX_ROUND.md` |
| ingesting field data from a FIT | `docs/agents/rituals/FIELD_DATA.md` |
| sizing a task or filing an issue | `docs/agents/DISPATCH.md` |
| gating, re-gating or writing a verdict | `docs/agents/GATE_PROTOCOL.md` |

---

## 9. Machine-checked lines

`scripts/check_agent_facts.py` re-derives the following from the tree on every
CI run and fails if this file disagrees. The marker lines are the contract; the
prose above is the explanation.

    AGENTFACT ci-container sha256:7a6f586cb0e0393ff288da09cf27b6dad40a0058a346c529b99fd0fc19858f0f
    AGENTFACT manifest-devices 15
    AGENTFACT pinned-tests 16
    AGENTFACT ceiling 30b2b99 27 253 226
    AGENTFACT devfield 0 PCr_J
    AGENTFACT devfield 1 GLY_J
    AGENTFACT devfield 2 PCr_cons
    AGENTFACT devfield 3 GLY_cons
    AGENTFACT devfield 4 PCr_depleted_kJ
    AGENTFACT devfield 5 GLY_depleted_kJ
    AGENTFACT devfield 18 Deficit_kJ

The ceiling line in §5.1 is additionally checked by
`scripts/check_ceiling_notes.py`, which requires it to be byte-identical to
its copy in `connectiq/source/Tests.mc`.

**What is NOT machine-checked**, so nobody reads more into a green run: every
prose claim in §1–§4, §6 and §7, the byte and type columns of §5.3 (a
`check_fit_budget.py` run re-derives those numbers from source and enforces the
32 B quota, but it never compares them with the table above), the
backlog and release figures in §5.4–§5.5, and every `file:line` citation.
Those carry a commit pin and nothing more. Line numbers shift — re-verify
before quoting one.
