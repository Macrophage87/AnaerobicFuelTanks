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
`DualTankView.mc`, `TankModel.mc`, `Tests.mc`), `connectiq/resources/`, and
since #114 eight device-qualified `connectiq/resources-<device id>/` folders
that hold only a launcher icon at that device's size. Every
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

`README.md:211` said the Monkey C was "Not compiled in CI". **That claim was
false from PR #48 (2026-07-16)** (§1.2) and was corrected at its source in
#103 / PR #107; the bullet now there describes what CI does and does not
prove. Retained as the worked example of §6's "a documentation claim about
the environment that is false".

### 1.2 What CI runs, and what it does NOT run

`.github/workflows/ci.yml` at `30b2b99`, verified from the check-runs object
for that commit (`gh api repos/Macrophage87/AnaerobicFuelTanks/commits/<sha>/check-runs`):

| Check name (as GitHub reports it) | Job id | Required? | What it proves |
|---|---|---|---|
| `Compile (edge1050)`, `Compile (fenix6pro)` | `test` | yes | `monkeyc -t -l 1` **compiles** — the `(:test)` sources included — on those two devices only |
| `CIQ (:test) headless (best-effort)` | `ciq-test` | **no** | tries to **execute** the suite under Xvfb. It **did** execute it on the three runs measured 2026-09-05; historically the simulator segfaulted after `SetLayout` and the job skipped green (#61; levers falsified in PRs #81 and #84). Read the retraction below before citing this row |
| `R parse + lint` | `r-lint` | yes | R syntax + the deploy-manifest freshness gate |
| `R model tests (testthat)` | `r-test` | yes | the R model suite, and that `tools/crosscheck/fixtures/` regenerate byte-identical |
| `Model parity (R vs Python mirror)` | `model-parity` | yes | the Python mirror of `TankModel` matches the R reference within 0.1 J per second |
| `Manifest app-id lint` | `manifest-lint` | yes | app id shape; CP/W′ keep the sentinel-0 default (#42); the FIT developer-field byte budget — ≤ 32 B per message type for a data field, summed over the `createField` call sites in every `.mc` under `connectiq/source/` (#98 item 2) |
| `Agent-loop tooling (runner-free)` | `test-tooling` | yes | this file's `AGENTFACT` lines, the `(:test)` pin, the ceiling note, the literal check, the `(:test)` log parser `ciq-test` gates on, and (since #117 item A) that the `RIDEFACT` lines in `docs/fielddata/ride-2026-09-20-edge1050.md` agree with the committed ride fixtures. Each has its own RED/GREEN self-test |
| `ci-required` | `ci-required` | **the only name branch protection requires** | aggregator over the required jobs (`needs:`), strict up-to-date, admins enforced |

> **RETRACTION, 2026-09-05 (PR for #61 item 2).** This paragraph used to open
> "**The `(:test)` suite does not execute in CI.**" **That claim is withdrawn.**
> On three consecutive `ciq-test` runs on 2026-09-05, on branch
> `claude/fit-prune-102`, the `Run (:test) headless under xvfb` step executed the
> suite: run [33990588668](https://github.com/Macrophage87/AnaerobicFuelTanks/actions/runs/33990588668)
> printed `PASSED (passed=16, failed=0, errors=0)`,
> [33990860226](https://github.com/Macrophage87/AnaerobicFuelTanks/actions/runs/33990860226)
> printed `FAILED (passed=16, failed=0, errors=1)` and reddened the job, and
> [33991598740](https://github.com/Macrophage87/AnaerobicFuelTanks/actions/runs/33991598740)
> printed `PASSED (passed=17, failed=0, errors=0)`. **N = 3 runs, one branch, one
> day, and nobody knows why it changed** — the `SetLayout` segfault is still
> visible in the job's separate diagnostic step, which runs the simulator
> standalone. So: do not cite a green `ciq-test` as evidence that a `(:test)`
> ran; the job's SKIP branch is still green, and the job is still not required.
> A **red** `ciq-test` is strong evidence; a green one is weak.

**Eight other copies of the retracted claim survive and are deliberately not
corrected here**, re-derived on the merged tree (PR #105 round 3; the count was
five at `be73a75`):
`connectiq/source/Tests.mc:443`, the comment above
`testCpWprimeDefaultUnconfigured`; `scripts/check_settings_defaults.sh:8`;
`scripts/check_fit_budget.py:15` ("`ciq-test` is best-effort and skips green"),
**new with PR #106 and not yet reported on #61**; `docs/agents/DISPATCH.md:47`
("a `(:test)` here **compiles in CI and executes only locally**"), which is the
**V=1 anchor** of the dispatch rubric and so governs every future scoring;
`docs/agents/DISPATCH.md:232` ("a repository whose test suite does not execute
in CI"), the V-axis rationale of §4's histogram;
`docs/agents/rituals/LANDING.md:47-49`, which tells a landing agent the job
"will also read `success`" — falsified by run `33990860226`, conclusion
`failure`; `docs/agents/rituals/RELEASE.md:76` ("The `(:test)` suite runs only
locally (`FACTS.md` §1.2)"), which cites **this section** for a claim this
section withdraws; and `.github/workflows/ci.yml:507`. The six other than
`check_fit_budget.py:15` and `RELEASE.md:76` are reported on #61; those two are
not, and belong there before this paragraph is cited again. `ci.yml:85`'s copy
is **conditional** — it skips green "when the captured log holds no summary line
at all" — and is not falsified, so it is not counted. A further copy is in
PR #105's own `b5de5f2` commit message; it is landed history, cited by SHA from
`scripts/fixtures/monkeydo-red-run.log:8` and
`scripts/test_check_ciq_tests.py:37`, and is corrected forward rather than
rewritten.

**A green `Compile` is compile-only evidence.** The enforced numeric guard on
the model is `model-parity`, and it guards the Monkey C **transitively** through
a line-for-line Python port (`tools/crosscheck/test_parity.py`'s own docstring
says so). Anything a `(:test)` asserts that the mirror does not (persistence
`validateBlob`, `decideDropout`, `writeField` null-safety, settings finiteness)
is proven either by that best-effort CI job — weakly, per the retraction above —
or by a **local** simulator run:

```sh
cd connectiq
<sdk>/bin/monkeyc.bat -f monkey.jungle -d edge1050 -o bin/app-test.prg -y <key>.der -t -l 1
<sdk>/bin/connectiq.bat &            # once; never kill a simulator you did not start (§4.5)
<sdk>/bin/monkeydo.bat bin/app-test.prg edge1050 /t
```

**The test flag is `/t` on Windows and `-t` in the container.** Verified
2026-09-05 by reading `<sdk>/bin/monkeydo.bat`: its third argument must be `/n`,
`/a` or `/t`, and anything else jumps straight to `usage` — a `-t` there prints
the usage text and runs nothing. The Linux `monkeydo` in the CI container takes
`-t` (`ci.yml`'s `ciq-test` run step, which executed the suite on the three runs
above).

`monkeydo` returns non-zero **even when every test passes** (upstream's
`tester.sh` documents it). Read the `PASSED (passed=N, failed=0, errors=0)`
line, never the exit code. **`scripts/check_ciq_tests.py` now parses that line**
— it is the whole verdict of the `ciq-test` gate, and it is what a local run
should be judged by too:

```sh
python3 scripts/check_ciq_tests.py --monkeydo-log <log> \
    --expected-file scripts/expected_tests.txt
```

It requires exactly one summary line starting `PASSED`, no `FAILED (passed=`
anywhere, `passed` equal to the pin, `failed == errors == 0`, `Ran N` agreeing,
and a RESULTS table listing exactly the pinned names all `PASS`. Its hermetic
RED/GREEN suite (`scripts/test_check_ciq_tests.py`) runs in the required
`test-tooling` job and is built on two real captures of `ciq-test`'s own output
under `scripts/fixtures/`. **It is runner-free: a green `test-tooling` proves
the parser, never that the simulator ran.**

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
  the suite. `Tests.mc:485-502` (`testWriteFieldNullSafe`, re-pinned on PR #105
  — line numbers shift, this citation has moved twice) exercises the static
  `writeField` seam with a `null` handle; it cannot create a field. **The v0.6
  load crash (#96) was invisible to every test and to CI** for this reason: it
  fired inside `initialize()` on the device, on every target, deterministically.
  Measured on PR #105: deleting the `if (mFitRecord)` gate around the two
  surviving `createField` calls leaves the suite at `PASSED (passed=17,
  failed=0, errors=0)` — the gate is invisible to every test there is.
* **No `(:test)` can obtain a graphics `Dc`.** Layout selection and rendering
  (`onUpdate`, `drawVertical`, `drawFull`) are field-only.
* **A comment cannot be red by any test.** Comments are stripped from the
  build. The two surviving copies of the false claim that `createField()`
  "returns null when the FIT field budget/memory is exhausted" — above
  `writeField` in `DualTankView.mc` and above `testWriteFieldNullSafe` in
  `Tests.mc` — were **corrected on PR #105** (#98 item 5's remaining two sites);
  #96 established that the SDK raises an **uncatchable** `Out Of Memory Error`
  instead. Nothing enforces that they stay corrected.
* **Nothing CI runs decodes a file this app wrote, but one decoded file is now
  committed as a text fixture.** `tools/calibrate/R/model.R`'s
  `read_power_raw()` **skips** developer-field definitions by size
  (`test-read_power_raw.R` pins it); `tools/crosscheck/` reads only R-generated
  CSV fixtures. Since #117 item A,
  `tools/fielddata/fixtures/ride-2026-09-20-edge1050.*` holds text fixtures of a
  saved Edge 1050 file this app wrote (v0.8, 2026-09-20). They were extracted by
  `tools/fielddata/extract_ride_fixture.py`, which runs **outside** CI because CI
  has no `.fit`. `tools/fielddata/ride_evidence.py` regenerates every figure
  published from the fixtures, and the required `test-tooling` job checks those
  figures against the pinned `RIDEFACT` lines in
  `docs/fielddata/ride-2026-09-20-edge1050.md`. **Still one ride**: one device,
  one firmware, `fitRecord` ON only, and the extraction itself is not re-run by
  anything. The #100 lag table for the **2026-07-26** ride was made with a
  decoder outside the repository, and nothing committed can regenerate it (§6).
  The same one-record offset on the 2026-09-20 ride is regenerable:
  `RIDEFACT threshold +1 255 255 13 11858` against
  `RIDEFACT threshold +0 257 257 488 11879`.
* **On-device load is field-only.** CI compiled v0.6 green on both devices and
  the shipped build could not load. A `[Local]` record-and-save gate on the
  Edge 1050 is the release gate (#98 item 1).

### 3.3 Record-scope FitContributor fields LATCH

Skipping a `setData` **re-emits the previous value** on every subsequent
record. It never produces a gap. This repository writes every record field on
every tick, including the held and skipped paths. Re-pinned on PR #105 after
#102 cut the seven fields to two: `DualTankView.mc:823-824`, `:844-845`,
`:881-882`, `:916-917`, live at `:931-932` (and the `initialize()` seed at
`:278-279`). Keep it that way: a gate on a FIT
write fails **open**, and "stop writing during X" fabricates a timeline rather
than omitting one. #102's `fitRecord` gate is therefore on **creation**
(`initialize()`), not on the writes — with the setting off the handles are null
and `writeField` skips, so no partial timeline can be produced. #76 extends the
same creation gate to CP/W′ being configured at load (§5.3).

**The latch has now been seen in a decoded file** (the 2026-09-20 ride,
`docs/fielddata/ride-2026-09-20-edge1050.md`). At all 23 pause boundaries:

* the first record after the resume repeats the last pre-pause record exactly,
  for both reserves (`RIDEFACT boundary_latch PCr_J 23 GLY_J 23 both 23 23`);
* that record carries no power (`RIDEFACT boundary_power_absent_at_resume 23 23`);
* the reserves move at the next record (`RIDEFACT boundary_change_at_next 23 23`).

So the rest-recovery refill arrives one record **after** the resume, not at the
first post-resume record. This is consistent with each record carrying the value
latched by the previous `compute()`, which is #100's one-record offset. The file
cannot say whether the resume record was written before the app's first
post-resume `compute()` or by the offset itself; it shows only the repeated value.
It is also not evidence that a *skipped* `setData` re-emits. This app never skips
a write, so that half of the rule is still read off the SDK, not measured.

### 3.4 A comment may state what the code CALLS, never what a decoder SEES

Until a `[Local]` simulator or decoder session has measured it. `[Local]`
issues carry: the `[Local]` title prefix, an opening ⚠️ blockquote, the
`local-test` label, and byte-exact pass criteria. (This paragraph said the
`local-test` label **did not exist** — 13 labels at `30b2b99`, none of them.
Re-measured 2026-09-05: there are now **14** labels and `local-test` is one
of them, so it no longer has to be created first. #109 is the first issue
filed under it.)

### 3.5 Clocks

`nowSec()` is `Time.now().value()` (unix seconds) — wall clock, not
`System.getTimer()`. The one `System.getTimer()` use is `mPauseAtMono`, the
#41 monotonic pause stamp: stamped in `enterPause()`, read in `exitPause()`
through the pure seam `DualTankView.pauseElapsedSec(wallNow, wallStamp,
monoNow, monoStamp, maxPause)`. `System.getTimer()` is a **signed 32-bit**
millisecond counter and is **negative from 24.9 to 49.7 days of device
uptime**, so **no sign test may mean "not set"**: since #104 an unset stamp is
`null` and presence is `monoStamp != null`.

Until #104 the sentinel was `-1` and the test `mPauseAtMono >= 0`, so a stamp
taken in the negative half read as "not set" and the resume path fell back to
the wall-clock branch — a degradation (loss of #41's clock-jump immunity), not
a corruption. `testPauseStampNegativeClock` calls the seam with injected
negative clocks; with the old guard it reds (`ciq-test` run 36138410601,
`FAILED (passed=17, failed=0, errors=1)`), with the fix it passes (run
36138693070, `PASSED (passed=18, failed=0, errors=0)`). **What that pins is the
seam, not the device**: no device has been run through the negative half, and
a pause whose two readings straddle the counter's `+2^31−1 → −2^31` wrap is not
claimed either way (the seam's range check falls back to the wall clock if the delta
comes out out of range). Neither is measured.

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
`test_check_mc_literals` 8/8, `test_check_agent_facts` 32/32,
`test_check_fit_budget` 30/30) are green on both. (This line read
`test_check_agent_facts` **21/21** when it landed; the suite in the tree at
`cea95c8` has 25 cases, so the figure was stale on arrival. Re-measured
2026-09-05 — the tree wins. #111 took it from 25/25 to **32/32**, measured 2026-09-25 on
a Windows checkout, where the other figures on this line re-measured
unchanged, `test_list_tests` included at 34/35.)

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
**Re-measured 2026-09-25** by bisection on a clean archive of `2630503` (PR #124's
c3 for #76, whose c2 adds `testShouldCreateFitFields`), SDK 9.2.0, §2.7 recipe, on
the maintainer's machine: 400 stubs reported `Found 430 members` (430 − 400 = 30
used); 223 stubs `BUILD SUCCESSFUL`; 224 stubs `Found 254 members in module
'globals', exceeding the limit of 253`. The single copy in source,
`connectiq/source/Tests.mc`, reads:

    CEILING config-gate-76 fenix6pro: 30 used of 253, 223 free -- the 224th file-scope (:test) added reds

**Superseded** figures: 29 used / 224 free at `482d790` (#104, 2026-09-25), 28 / 225
on the #102 c2 tree (2026-09-05), and 27 / 226 at `30b2b99`. Each step since has added exactly one file-scope
`(:test)`, and each re-measurement moved the count by exactly that one.

`scripts/check_ceiling_notes.py` enforces the arithmetic and that this
quotation is byte-identical to the source copy; `scripts/check_agent_facts.py`
enforces that §9 quotes the same numbers. Neither can tell you the note is
still current — re-measure when file-scope declarations are added. `edge1050`
does not bind; a green `edge1050` build says nothing about this.

### 5.2 Pinned test count

**19** `(:test)` functions, all file-scope in `connectiq/source/Tests.mc`,
matching `scripts/expected_tests.txt` exactly (on the #76 c2 tree,
`python3 scripts/list_tests.py` lists 19 names and a sorted diff against the
pin's non-comment lines is empty; `bash scripts/check_expected_tests.sh` runs
the same comparison in the required `test-tooling` job). It was **16** at `30b2b99`; #102 c2 added
`testFitRecordSettingCoerces` (17), which is also the one file-scope declaration
behind the §5.1 ceiling re-measurement; #104 c2 added
`testPauseStampNegativeClock` (18), also file-scope, so it spends one more
`fenix6pro` `globals` slot; §5.1's re-measurement on `482d790` reflects it; #76 c2 added
`testShouldCreateFitFields` (19), file-scope as well, so it spends one more slot; §5.1's
re-measurement on `2630503` (the #76 fix commit) reflects it. Measured with
`scripts/list_tests.py`, never added up.

Any `(:test)` addition, removal or rename edits `scripts/expected_tests.txt`
**in the same commit**. The check closes drift, not coordinated shrink.

### 5.3 The developer-field id map and the byte budget

**2** live developer fields since #102 (PR #105), parsed from the literal
`createField` calls in `connectiq/source/DualTankView.mc`. It was **7** at
`30b2b99`:

| id | name | type | message | bytes |
|---:|---|---|---|---:|
| 0 | `PCr_J` | FLOAT | RECORD | 4 |
| 1 | `GLY_J` | FLOAT | RECORD | 4 |

**RECORD = 8 B, SESSION = 0 B, against 32 B per message type** — the data-field
quota confirmed on hardware in #96 (a full app gets 256 B). It was RECORD 16 B /
SESSION 8 B at `30b2b99`. Both calls are gated on
`DualTankView.shouldCreateFitFields(mFitRecord, mConfigured)`: the `fitRecord`
setting (boolean, **default true**) **and** CP/W′ configured (#76, PR #124), both
read once per load in `reloadSettings()` before the `createField` block. With
either false neither call runs and this app defines **zero** developer fields for
that load; a rider who sets CP/W′ mid-ride records nothing until the next load, and
one who clears them mid-ride keeps the fields that load created.
`testShouldCreateFitFields` pins the decision (red on the pre-#76 seam, ciq-test run
36149549904), not the file. **That the OFF or unconfigured build defines zero fields
in a saved file is NOT measured** — no `(:test)` can obtain a `Session` (§3.2) — and
is owed to the `[Local]` record-and-save gate.

Ids **2, 3, 4, 5, 18** (`PCr_cons`, `GLY_cons`, `PCr_depleted_kJ`,
`GLY_depleted_kJ`, `Deficit_kJ`) are **retired and must never be reused**: all
five shipped in released builds, so files in the wild carry their
`field_description`s. **This is decoded evidence, not inference** — #98's
2026-07-26 comment reports a saved Edge 1050 FIT in which "All seven developer
fields are declared and populated" (875 RECORD samples each, both SESSION
totals present). Ids **6–17** were the `FID_CFG_*` config session fields;
they are **deleted from source and available for reuse**, because #98 item 4
establishes that `b5198e1` added the twelve creates and took SESSION to 56 B in
the same commit, so config-in-FIT never ran on any device and no saved file
carries config *values*. Caveat, stated because it is not established: #96's
arithmetic says `createField` for ids **6–11** succeeded before `lt1Frac`
(id 12) overflowed, so whether a partial `developer_data_index` /
`field_description` set for 6–11 was ever flushed into a v0.6 file is unknown
and cannot be checked from this repository. The source-of-truth copy of this
table is the comment beside `FID_PCR_J`/`FID_GLY_J` in `DualTankView.mc`.

A developer field id is unique per `field_description`; re-using one silently
re-labels every file recorded with it. The budget is **per app**, not shared
across co-installed data fields (#96, from a saved FIT with four apps writing
53 B to RECORD) — but the maintainer reports memory failures with several data
fields installed, and that observation is field data this repository cannot yet
regenerate. #102 cuts this app's contribution unconditionally, which helps under
either mechanism; which mechanism is right is still open.

**One more file, and this one is committed** (the 2026-09-20 ride, v0.8, Edge 1050,
`docs/fielddata/ride-2026-09-20-edge1050.md`):

* **Four developer data indexes declare fields** (`RIDEFACT apps 4 ours 3`).
* **Declared `record` bytes are 13 / 4 / 24 / 8 = 49 B**, and the largest single
  app declares 24 B (`RIDEFACT devbytes record total 49 max_app 24`). One element
  per declared field; array counts are not in the fixtures.
* **This app's index declares exactly `PCr_J` and `GLY_J`** (`RIDEFACT ours_fields`),
  8 B on `record` and 0 B on `session` (`RIDEFACT devbytes record 3 8`,
  `RIDEFACT devbytes session 3 0`).
* **Both fields are populated on every record and still moving at the last one**
  (`RIDEFACT populated PCr_J 11903 11903`, `RIDEFACT last_change PCr_J 15140 15140`).

The file holds 49 B of `record` declarations while every app's declared elements
stay ≤ 32 B, and it saved. That is consistent with #96's per-app finding. It is one more file, not a
settlement. The fixtures keep only what the other three apps *declared*, not their
values. So "all four apps' fields populated to the end" is an observation from
the out-of-tree decode, not a committed figure.

**The application id in the file differs from the manifest id**
(`RIDEFACT app_id file 24ec02815a2643ac8e47d1f1bc7bceb4 manifest fc13e61e7ca54c998c7a7c64f0ef4434 differ`).
Why is not established. Anything that finds this app's fields by application id
rather than by field name will miss them in this file.
`extract_ride_fixture.py` matches by name for that reason.

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

Re-pinned **2026-09-25 at `d6be663`** (the `v0.8` tag, #113), read with
`gh release list`, `gh release view <tag> --json name,isPrerelease,assets,body`
and `git ls-remote --tags origin`:

| tag | commit | GitHub release | flag | assets |
|---|---|---|---|---|
| `0.1` | `8e9fc00` | **none** — a tag only | — | — |
| `v0.6` | `ee93fed` | "DualTank v0.6 — SUPERSEDED by v0.7 (crashes at load on every target, #96)" | release, **`latest`** | `DualTank.iq` 541,690 B |
| `v0.7` | `30b2b99` | "DualTank v0.7 (pre-release) — fixes the v0.6 load crash; superseded by v0.8" | prerelease | `DualTank-0.7.iq` 538,913 B |
| `v0.8` | `d6be663` | "v0.8" | prerelease | `DualTank-v0.8.iq` 549,096 B; `DualTank-v0.8-edge1050.prg` 28,188 B |

**v0.6 is the build that crashes at load** (#96) and it still carries GitHub's
`latest`: it is the newest release not flagged prerelease, and under the
owner's beta flag policy (`rituals/RELEASE.md` §8) flags stay as cut until 1.0,
so it is not re-flagged. Its title and an opening ⚠️ blockquote say so instead;
`v0.7`'s body opens with a blockquote pointing at `v0.8`. The version belongs
in the asset filename (release ritual §5); `v0.8` is the first release whose
assets follow the `DualTank-v<X.Y>` form.

`v0.8` provenance, **as its release body states it** — not re-derived here: built
from `d6be663` with the account-bound DualTank key, **28 of 28** device parts
across the 15 manifest products (the export log is not attached to the release
or committed, so `N OUT OF M` cannot be re-read after the fact — §1.4), suite
`PASSED (passed=17, failed=0, errors=0)`. The body carries a dated
**retraction (2026-09-06)**: the first pair of assets was signed with a
different key and both were replaced with exports signed by the DualTank key.
The assets attached now were uploaded **2026-09-06T09:09Z** (their `createdAt`);
the API reports their digests as

    DualTank-v0.8.iq            sha256:904faaa65a10e4d4ae5046374b990b630af34dca083f80c2a3ee3c3a3cf9ec4b
    DualTank-v0.8-edge1050.prg  sha256:e40ef4e1da5f50dd8c041b501fbd911c5c3372de0acee3111db5c9d2d4e3002c

Store-Version 6 is the crashing build (not re-verified here: nothing in this
repository reads the Store); the store resubmission is #96's remaining blocker
(#96 open on 2026-09-25), and the Store description correction rides with it.
`connectiq/store/description.txt:25` advertised "live consumption" and
end-of-ride kilojoules, fields whose `createField` calls #102 deleted; the file
was rewritten to the two `PCr_J` / `GLY_J` record streams in the PR for #114
(2026-09-25). The committed text is corrected; the listing on the Store is not
until the resubmission uploads it.

**Static image size is not the memory pressure.** Measured at **`d6be663`** on a
clean archive with `monkeyc -r -l 1` (release, debug stripped) and a throwaway
key — **by the maintainer's local session and reported in #113's body; not
re-measured for the re-pin**, which ran with no SDK. One row is
independently readable: the `v0.8` release asset `DualTank-v0.8-edge1050.prg`
is 28,188 B, equal to the `edge1050` row to the byte. The limit is each
device's `compiler.json` `datafield` `memoryLimit`, read at `30b2b99`; the
device files are not in this repository and were not re-read. Share is
computed from the two columns.

| device | release `.prg` | limit | share |
|---|---:|---:|---:|
| edge530 / edge830 | 24,812 B | 131,072 B | 18.9 % |
| edge540 / edge840 | 21,468 B | 131,072 B | 16.4 % |
| edge1030 / edge1030plus | 24,892 B | 131,072 B | 19.0 % |
| edge1040 | 22,140 B | 131,072 B | 16.9 % |
| edge1050 | 28,188 B | 131,072 B | 21.5 % |
| fenix6pro | 23,900 B | 131,072 B | 18.2 % |
| fr255 / fr255m | 20,540 B | 262,144 B | 7.8 % |
| fr955 / fenix7 / fenix7x | 20,860 B | 262,144 B | 8.0 % |
| fr965 | 29,340 B | 262,144 B | 11.2 % |

The **superseded** table, measured 2026-09-05 at `30b2b99` (v0.7, seven
fields), was larger on every row by 1,328 B (edge530/830, edge1030/1030plus,
fenix6pro) or 848 B (every other row); it is in this file's history.

A build **without** `-r` is 124–132 KB on the same devices — that is debug
information, not loaded code, and it is why a first survey read "100.3 % on
edge1050" for a build that loads fine. Runtime **peak heap** is not measured
by anything here; the simulator's memory view is the only instrument, and it
has not been read for this app. The `(:test)` helpers in `Tests.mc` do not
ship in the `-r` image (verified: `tmMake` absent from the release `.prg`).
The 124–132 KB figure and the `tmMake` check were measured at `30b2b99` and
were not repeated at `d6be663`.

---

## 6. Defect classes this repository keeps re-learning

* **A claim stronger than its evidence.** #96 shipped three of them in its
  first body (device memory, "throws", #32's 18→19 fields) and one in #34
  ("returns null on exhaustion" — an inference no SDK page documents).
* **A number nothing committed can regenerate.** #100's cross-correlation
  table and threshold fit came from a saved FIT decoded outside the tree.
* **A documentation claim about the environment that is false.** `README.md`
  said "Not compiled in CI" for eight weeks after PR #48 made it compile.
  Corrected at its source in #103 / PR #107; the bullet now at `README.md:223` (`:219` before #76's README addition)
  says "Compiled in CI, but no required check executes it". Kept as the worked
  example (§1.1), stated in the past tense because the line no longer says it.
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
    AGENTFACT pinned-tests 19
    AGENTFACT ceiling config-gate-76 30 253 223
    AGENTFACT devfield 0 PCr_J
    AGENTFACT devfield 1 GLY_J

The ceiling line in §5.1 is additionally checked by
`scripts/check_ceiling_notes.py`, which requires it to be byte-identical to
its copy in `connectiq/source/Tests.mc`.

The `devfield` lines are derived from **every `.mc` file under
`connectiq/source/`**, found by the same walk `check_fit_budget.py` uses
(`list_tests.mc_files`, imported), so the id map and the byte totals are read
from one scope (#111; the map used to be read from `DualTankView.mc` alone).
Each file is read raw and comment-stripped and the two id sets must agree; a
`const` id resolves only against a `const` in the **same file** as the call,
and an id created in two files is refused. The per-file rule is **stricter
than Monkey C**: a file-scope const does resolve across files (`Tests.mc`
uses `DROPOUT_USE` from `DualTankView.mc`), but the checker's const map is a
regex that cannot tell a file-scope const from a class const, and a class
const from an unrelated class could bind the wrong id — so a cross-file name
is refused, loudly, rather than guessed. No filename is pinned. The checker's
module docstring is the full contract.

**What is NOT machine-checked**, so nobody reads more into a green run: every
prose claim in §1–§4, §6 and §7, the byte and type columns of §5.3 (a
`check_fit_budget.py` run re-derives those numbers from source and enforces the
32 B quota, but it never compares them with the table above), the
backlog and release figures in §5.4–§5.5, and every `file:line` citation.
Those carry a commit pin and nothing more. Line numbers shift — re-verify
before quoting one.
