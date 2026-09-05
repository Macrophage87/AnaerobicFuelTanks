> **Provenance.** This file is the StrongRow orchestration kit's `LESSONS.md`,
> imported verbatim on 2026-09-05 (kit exported from StrongRow `origin/main`
> at `3c85eaf`, post v0.9.1). Every number, issue reference (`#70`, `#46`,
> ...), file name and release tag below is **StrongRow's**, not this
> repository's. The rules transfer; the figures do not. This repository's own
> measurements live in [`FACTS.md`](FACTS.md), and its own anchors in
> [`DISPATCH.md`](DISPATCH.md). Two rowing-specific product rules (colour-only
> cues, glance priorities) are recorded as the maintainer's stated preferences
> from that project, not as rules adopted here.

# Orchestrating agents on a Connect IQ app: lessons from StrongRow

Written 2026-09-05 after eleven releases (v0.4 to v0.9.1), roughly two hundred issues, and one
release that shipped a crash. Everything below was paid for at least once. Copy it into a new
app's `docs/` and edit the project-specific numbers; the rules transfer as they are.

The short version: **an agent's report is a claim, not a measurement.** Every process rule here
exists to turn a claim into something a second agent, a script, or a real device can refute.

---

## Part 1. Connect IQ facts that will bite a new app

These are platform behaviours, verified at source or measured on hardware. None of them is in
the SDK documentation in a form you would notice before it fails.

### Time
- `System.getTimer()` is a **signed 32-bit** millisecond counter since boot. It is **negative from
  24.9 to 49.7 days of uptime**, which is about half of all wall-clock time on a watch nobody
  reboots. Any presence test written as `stamp > 0` reads live data as absent for the whole of
  that half. Use `!= 0` for "ever stamped" (0 is never-seen), and only ever subtract two stamps.
  This blanked HR, CORE temperature and R-R recording on one row after two releases had
  "left it as-is on purpose".
- Monkey C `Number` **addition wraps two's-complement** in the simulator (measured: `2147483647 + 1`
  gives `-2147483648`, no promotion, no throw). Subtraction across the seam is unmeasured.
  Do not build a wrap-safe age on either until you have measured it yourself.
- The single 2^31-1 to -2^31 crossing is one minute in 49.7 days. Say it is out of scope; do not
  claim to have handled it.

### FIT recording
- **Record-scope `FitContributor` fields latch.** A skipped `setData` re-emits the previous value.
  "Stop writing during a dropout" therefore *fabricates* a timeline (62.7% of one row was
  republished beats). Write every tick: the value when fresh, the FIT invalid sentinel when not.
- An **all-invalid array** (`[0xFFFF ×4]` for UINT16) written explicitly is not distinguishable in
  the saved file from never-written; decoders honouring FIT invalids drop it. That is the
  rendering you want for absence. A `0` sentinel is in-band and decodes as a real value.
- A never-written **session-scope** field keeps its `field_description` and contributes no value.
  "Declared, never written" in a decoder means exactly that, not a create failure.
- Developer field ids are a namespace separate from native field numbers. Key on
  `(developer_data_index, field_definition_number)`. Twelve developer fields was the previous
  measured high; 22 with a non-contiguous id set has now been decoded from a real fenix 6.
- `Activity.Info.currentCadence` is not what the record's native `cadence` column holds on a
  rowing profile. The native `cadence` field and per-lap `total_cycles` are a **second detector**
  the app reads but never writes, which makes them an unbiased witness for anything your own
  estimator publishes. This settled a design question the app's own harness could not.

### Sensors
- `Sensor.SensorData.heartRateData.heartBeatIntervals` can be an empty array on 70% of callbacks
  with the strap connected. Count "batch arrived", "beat accepted" and "difference accepted"
  separately; they answer different questions, and one 5-second constant serving all three hides
  whichever one is failing.
- A **session-scope diagnostic array** (20 to 25 UINT16 slots, version in slot 0) is the cheapest
  instrument you will ever add. Two rows into the project it answered questions no FIT record
  could. Give it a **session reset** from the start: a counter that runs from `onLayout` cannot
  tell a frame that arrived before START from one during the row, and that distinction is the
  one a dropout diagnosis turns on.
- An ANT+ channel's `open()` returning `false` and its `open()` throwing are different paths;
  count both, or a quiet failure reads as a healthy channel. Never call `openChannel()` from the
  reopen scheduler's catch: that recursion stack-overflowed and killed the app mid-row.
- Third-party sensor page layouts (CORE body temperature page 0x00) come from vendor examples,
  not authoritative profiles. Say so beside every offset. Reading a repository with no licence
  file is fine for facts; copying code from it is not.

### Language and compiler
- `0 == false` evaluates **true**. Clamp settings with `instanceof Lang.Boolean`, never with `==`.
- The **fenix 6 family caps a module's `globals` at 253 members**, inclusive, and `monkeyc` reds at
  the 254th. A file-scope `(:test)` costs one member; a `(:test)` inside a `module { }` block
  costs none. Bisect the headroom with throwaway stubs, pin the figure in one place, and have a
  script check the copies (`check_ceiling_notes.py`); two copies of a correct number drift.
- `monkeydo` **exits non-zero even on success**. Read the `PASSED (passed=N, failed=0, errors=0)`
  line and run a checker that reds when the simulator died before any test ran.
- No `(:test)` can obtain a `Session` or a graphics `Dc`. `createField`, `stopAndSave` session
  writes, and anything gated on a real draw are structurally unreachable by the suite. Write
  that down as a verifiability fact so scorers stop crediting tests that cannot exist.
- The repository is `core.autocrlf=true` with no `.gitattributes`; `monkeyc` accepts a raw CR
  inside a string literal with no diagnostic. Build releases from
  `git -c core.autocrlf=false archive <tag>`, never the working tree.

### Devices, SDK, CI
- Device definitions are downloaded by the **SDK Manager GUI only**. A new watch family (fenix 9,
  published 2026-08-25) is invisible to `monkeyc` until someone clicks. Your CI container has its
  own copy: the `ghcr.io/matco/connectiq-tester` image bundles device files from a dated
  resources image, and a digest pinned in June cannot compile a device published in August.
  Resolve tags to digests with the registry API when Docker is down:
  `curl https://ghcr.io/token?scope=repository:<img>:pull`, then `HEAD /v2/<img>/manifests/<tag>`.
- **Pin the container by digest**, keep the digest in one machine-checked fact line, and bump it
  as its own commit with its own CI run before the change that needs it.
- A manifest product's memory limit (`compiler.json` `appTypes`) and resolution
  (`simulator.json`) are the only two things that decide whether an existing build fits a new
  device. A 72 KB `.prg` against a 786 KB limit needs no work; a new resolution does, if any
  layout table is keyed by width.
- `monkeyc -e` prints `N OUT OF M DEVICES BUILT`. **Read N and M off the log for every release.**
  The `.iq` is not a zip and cannot be enumerated afterwards; a copied-forward figure is a number
  nothing can regenerate.
- The release `.iq` for a private dashboard must be signed with the **account-bound key**; CI's
  throwaway key proves the export path only. Never write a key into the workspace and never run
  `openssl genrsa -out developer_key.pem` with a workspace-relative path.

---

## Part 2. The orchestration pipeline that worked

### Shape
```
diagnose (parallel read-only lenses, one per hypothesis)
  -> implement (one agent per branch, isolated worktree, c0-c3 partition)
  -> review (two lenses per PR: behaviour/measurement, tests/claims)
  -> refute survivors (default refuted=true unless evidence is clear)
  -> fix round (verdict FILE handed by path; one reply per verdict)
  -> re-gate (fresh lens for prose; mechanical for pure deletions)
  -> merge on approval and green CI
  -> release from a clean archive; supersede the bad one in title and body
```
Median dispatch after calibration: **two agents** per issue. The first rubric asked for five on
61% of the backlog; a "fix" that shifted every score by a constant changed nothing, and was caught
by doing the arithmetic (identical histograms) before dispatching it.

### Diagnosis before implementation, always
- Give each diagnostic agent **one hypothesis space** and the pinned facts, and forbid edits.
  Three parallel lenses (R-R/HR, CORE channel, rate/colour) took 20 minutes and found a single
  root cause the implementer would have patched three times.
- **Forward new facts between running agents.** The CORE lens concluded "all 33 frames arrived
  before START" because it did not know the clock was negative; the R-R lens found the clock. One
  message to the rate lens turned "does the rate path share the bug?" into a verified "no, it
  uses a synthetic sample clock" in the same run.
- Decode the FIT **yourself first** and put the numbers in the brief. `fitparse` takes a minute
  per file; dump records to CSV once and hand every agent the path.

### Commit partition and tests
- **c0** characterization pins on existing symbols (green) · **c1** refactor and new symbols
  (green) · **c2** red differentials only, every added test named in the red run's failure list ·
  **c3** the fix, touching no test, no pin, no `scripts/`, no `.github/`.
- **Open the PR at c1 and let each run finish before the next push.** `cancel-in-progress`
  deletes the red evidence otherwise.
- **The pin must call the thing it pins.** This repository has the receipt twice: a test that
  exercised a private copy of the comparison, deleting both real clamp lines, 308 cases green.
  Mutation-test every pin: "reverting X reds exactly case Y, N-1/N", and re-run the whole matrix
  after any later commit; a matrix measured at c4 was stale by c5.
- A behaviour reversal inside a fix round is still red-before-green: a new c2' that re-pins the
  opposite expectation, then c3'.
- Tests with only positive literal clocks exercised `stamp > 0` in its `== 0` direction 49 times
  and its negative direction never. **Every freshness helper gets a negative-clock case.**

### Verdicts, rounds, and the defect classes to name
- **Verdicts are files** at a scratch path outside the repo; the fixer gets the path, not a
  retelling. Every finding: claim, required fix as a verbatim substitution, verifying command,
  rationale, optional `file:line` pinned to the SHA. Mandatory sections, in these words:
  **WHAT WAS NOT VERIFIED**, items only field testing can answer, what holds up.
- **Re-measure every number in a substitution.** A reviewer's worked example
  (`hrHave(true, 2147483000, -2147483000, 5000)`) was applied verbatim and was wrong under both
  hypotheses; the next fresh lens caught it. The verdict's own rule had said so.
- **After the second wrong framing of a claim, delete the claim.** The clock PR took three prose
  rounds on one paragraph about subtraction across the seam. Round 3 deleted the topic; the
  re-gate passed. Rewording a third time is how the same claim goes wrong a third way.
- **Prose rounds go to a fresh lens; pure deletions can be re-gated mechanically** (zero
  non-comment diff lines, grep for the deleted terms in source and body, closing references
  empty). Log the mechanical check in the ledger so the record says who gated what.
- **GitHub closing keywords.** "Does not close #70" auto-closes #70. Prose *about* a closing
  keyword is a closing keyword. Check `gh pr view N --json closingIssuesReferences` after every
  body edit, and re-check once after the API's propagation delay; the first read after an edit
  returned the stale link.
- Named defect classes that recur: **a claim stronger than its evidence**; **a number nothing
  committed can regenerate**; **the wrong pair** (a figure compared against a quantity of a
  different definition: recorded vs replayed series, 12 products vs 26 parts vs 27 fields, a
  denominator of 2,818 beside a count over 3,385); **a pin that re-implements instead of
  calling**; **a test that cannot fail**; **absence rendered as a value**.

### Measurement over assertion
- **A fixture forces the falsification nobody can see.** "The baseline never fell below 22.68"
  passed a proposal, an implementation, a self-review and two independent reviews. It was false
  (minimum 15.3, binding on 148 of 181 seconds). It was caught only because a reviewer required
  the figure to come off a committed fixture, and building the fixture disproved it. Make
  "every published figure regenerates from a committed tool" a blocking rule, not advice.
- **A truth derived from the series under test is biased toward the change.** A 31-second median
  of the raw rate cannot see a raw error and rated the guard's refusals 4:1 favourable; Garmin's
  native counter rated the same refusals 1.6:1 at baseline, supported the 2:1 band (40:8) and
  killed the 3:1 band (10:16). The branch's headline example turned out to be a case where the
  thing it "fixed" had been right. Find the witness that does not share the estimator's inputs.
- **Two attempts of one CI run on the same runner pool is a flake check, not independent
  evidence.** Say so every time you cite it.
- Re-derive pinned counts **on the tree**, never by arithmetic across diffs. `385 + 11 + 4` was
  carried in a review thread for a different pair of branches; `list_tests.py` at each rebase
  step is the measurement. A union merge of a pin file silently resurrects a retired test.
- When Docker is down, say "the container suite did not run" in those words and let CI be the
  measurement. A `grep | tail` pipeline once swallowed a dead daemon and reported a run that
  never happened; `set -o pipefail` is the fix and it is not optional.

### Dispatch sizing (five axes, 0 to 3 each)
- **R**eversibility: name the revert, then what it does not restore (a recorded FIT value, a
  published asset, a field id consumers key on). Most bug fixes are one revert away: R=0 or 1.
- **V**erifiability: anchor to what the platform allows (no `(:test)` gets a `Session` or `Dc`;
  pod/erg/on-water is field-only).
- **S**urface: files and modules touched.
- **P**rose: name the second reader. A comment nobody quotes is not published prose; release notes,
  a field description a consumer decodes, and the CI contract are.
- **I**n-flight: name the open PR, pushed branch, or pinned budget it collides with. An open issue
  that names the same file is not in flight.
Bands Trivial/Routine/Standard/Heavy/Critical on the sum; validate any rubric change by
**re-scoring real issues and printing the histogram before and after**.

### Product rules that came from the athlete, not the code
- Colour and layout only; never vibration, tone or flashing.
- **A slow-changing status causes overcorrection.** Responsiveness outranks flicker suppression;
  a colour that lags the number is an instruction about a state that has passed. Measure lag
  from the number crossing the band to the colour following, and publish the flip cost.
- Glance priorities: rate in range, time left, HR, heat. There is a fraction of a second between
  strokes to read it.
- A displayed instruction must never point the opposite way from the number beside it.

### Releases
- Body opens with provenance: commit, key, `N of M` parts read off the export, product count,
  suite total read off the CI run at that commit. Version in the asset filename.
- A section headed **"Stated plainly: what this release does NOT establish"**, every time.
  Erg mode untouched by hardware, 27 fields beyond anything measured, a sentinel never decoded
  from a real file: each was true for two releases and each was written down.
- Supersede, never delete or move a tag: prepend a warning blockquote naming the replacement,
  what has to happen for the defect to fire, and what it costs; put SUPERSEDED in the title so a
  list view shows it. Cut the replacement from a fresh archive.
- Re-read the release with the last row's file in hand before publishing. v0.7 shipped a
  stack-overflow recursion because an open PR was not read first.

### Hygiene that avoided its own incident
- Never `git add .`, `-A` or `commit -a`; nested worktrees live inside the repository root.
- The stash is shared across worktrees and sessions; use a WIP commit instead.
- Verify source facts against `git show origin/main:<path>` or a clean archive, never a working
  tree; a local `main` was 78 commits behind and four "unfixed" P1s were three fixed ones.
- Track `.claude/` once you rely on the allowlist; a branch that made it tracked deleted it on
  checkout. The loop never widens its own permissions.
- Shared simulators are never killed; start your own instance and kill only that.
- `gh` reads are field-selected with `--limit` above the population and a saturation check;
  the default page is 30 rows against a backlog of 93.

---

## Part 3. Day-one checklist for the next app

1. `docs/agents/FACTS.md` with machine-checked lines: container digest, manifest device count,
   pinned test count, the `globals` ceiling, developer field id bindings. A script that reds when
   any drifts from the tree.
2. `scripts/check_ciq_tests.py` reading the `PASSED` line and the expected-tests file, in the
   digest-pinned container, with `set -o pipefail`.
3. A session-scope diagnostic array with a version slot and a session reset, from the first
   sensor you touch.
4. Freshness helpers written as `stamp != 0 && (now - stamp) < window`, each with a
   negative-clock test.
5. Every record-scope field written every tick, sentinel when stale.
6. A committed replay tool per estimator that reproduces the recorded output from recorded
   inputs, with a self-test, before any tuning claim is made; and an independent witness column
   (native cadence, speed, lap totals) beside it.
7. The rituals: `FIX_ROUND.md` (c0-c3, red before green, mutation, delete after the second wrong
   framing), `RELEASE.md` (clean archive, real key, read the part count, supersede form),
   `GATE_PROTOCOL.md` (verdict files, ledger, fresh lens for prose), `DISPATCH.md` (five axes with
   project anchors, validated on real issues).
8. The permission allowlist owned by the human: read-only git and `gh`, the `check_*` and
   `test_*` scripts, file inspection. Everything that changes state stays behind the prompt.
