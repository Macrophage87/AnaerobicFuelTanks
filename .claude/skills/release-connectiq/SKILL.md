---
name: release-connectiq
description: Cut a Garmin Connect IQ release from a clean archive, signed with the account key, with every figure in the release body read off a log rather than remembered. Use when asked to cut, publish, tag, or supersede a release of a Connect IQ (Monkey C) app.
---

# Cut a Connect IQ release

> Project copy for AnaerobicFuelTanks: the Connect IQ project lives in `connectiq/` (run `monkeyc` there), `APP` is `DualTank`, `TEST_DEVICE` is `edge1050`, the required CI job set is in `docs/agents/FACTS.md` §1.2, and the landing/release rituals in `docs/agents/rituals/` govern what this skill does not say. The canonical kit copy lives in the maintainer's `~/.claude/skills/`; keep the two identical apart from this note and the `KEY` row.

Publishing a release asset is the highest-reversibility-cost action in a Connect IQ repository:
a downloaded `.iq` cannot be recalled, only superseded. Every step below exists because skipping
it once shipped a wrong figure or a crash. Do the steps in order. Where a step says STOP, stop
and report; do not improvise past it.

## 0. Fill these in before starting

| name | value for this project |
|---|---|
| `REPO` | absolute path of the checkout (a worktree is fine; you will not build from it) |
| `REMOTE_MAIN` | `origin/main` unless the project says otherwise |
| `SDK_BIN` | the SDK Manager's SDK `bin` dir, e.g. `%APPDATA%/Garmin/ConnectIQ/Sdks/<sdk>/bin` |
| `KEY` | absolute path to the account-bound developer key (`.der`, PKCS8), **outside the repository**. Keys are per app, not one file per account: DualTank signs with the same key as CarbBurn, and a different app's key (FatigueMeter's) once put wrongly-signed assets on v0.8 for an hour. The path is machine-specific and is NOT recorded here (this repository is public): read it from the maintainer's per-machine note (Claude memory `ciq-account-key`) or `$CIQ_KEY`; if neither names this app's key, STOP and ask. |
| `APP` | app name used in asset filenames, e.g. `StrongRow` |
| `VERSION` | `vX.Y[.Z]`, the tag to create |
| `TEST_DEVICE` | the device CI runs the suite on, e.g. `fr965` |
| `PRERELEASE` | owner's policy: while the store listing is in **beta** (pre-1.0) only the owner sees builds, so leave flags as cut and do not re-flag older releases; from **1.0** on, every test/gate build is `--prerelease` and a plain release is cut only when the owner says "official" |
| `NOTES` | scratch path for the release body, outside the repository |

If `KEY` is not set, does not exist, or is not the key named for this app: STOP. A release signed
with a throwaway key — or with another app's key — is not the deliverable, and a key must never be
generated with a workspace-relative path. Refer to a key by path only: never hash, print or copy it.

## 1. Choose the commit and prove it is green

```bash
git -C "$REPO" fetch origin
SHA=$(git -C "$REPO" rev-parse --short "$REMOTE_MAIN")
gh run list --branch main --limit 3 --json databaseId,headSha,status,conclusion
```

- The commit you tag is the commit CI ran on. If the newest main run is `in_progress`, wait for
  it; do not tag ahead of it.
- Read the suite total off that run's log, not from memory or a docs file:
  ```bash
  gh run view <run-id> --log | grep -oE "PASSED \(passed=[0-9]+, failed=0, errors=0\)" | tail -1
  ```
  If the project pins the expected test count (`scripts/expected_tests.txt` or similar), the two
  must agree. If they do not, one is stale: STOP.
- If the project has a fact-check script (`check_agent_facts.py`, `check_ceiling_notes.py`), run
  it on a clean archive of `SHA` and require rc=0.
- Read every open PR that touches shipping source before proceeding. A release was once cut with
  an unread open PR that contained the fix for an unbounded recursion; the release crashed.

## 2. Build from a clean archive, never the working tree

```bash
CLEAN=$(mktemp -d)   # outside the repository
git -C "$REPO" -c core.autocrlf=false archive --format=tar "$SHA" | tar -x -C "$CLEAN"
```

Three reasons: the working tree is `autocrlf=true` on Windows and `monkeyc` accepts a raw CR
inside a string literal with no diagnostic; the working tree carries build output and nested
worktrees; and the release body names a commit, which must be what was built.

## 3. Export the store package and read the part count off the log

```bash
cd "$CLEAN"
"$SDK_BIN/monkeyc" -e -f monkey.jungle -o "$OUT/$APP-$VERSION.iq" -y "$KEY" -w > export.log 2>&1
echo "exit=$?"
grep -E "OUT OF [0-9]+ DEVICES BUILT" export.log | tail -1
grep -ci error export.log
```

- The last `N OUT OF M DEVICES BUILT` line is the part count. **Copy it from this log.** The `.iq`
  is not a zip and cannot be enumerated afterwards; nothing else regenerates the figure.
- `N < M` is a failed export, not a partial success: STOP.
- Count the manifest products separately (`grep -c 'iq:product id' manifest.xml`); parts and
  products are different numbers and the body states both.

Then build a sideload `.prg` for the test device and for any newly added device family:

```bash
"$SDK_BIN/monkeyc" -f monkey.jungle -d "$TEST_DEVICE" -o "$OUT/$APP-$VERSION-$TEST_DEVICE.prg" -y "$KEY" -r -w
```

Record the `.prg` byte size; it is the memory-headroom figure against the device's `watchApp`
limit in its `compiler.json`.

## 4. Write the body

The first sentence is provenance, with every number from steps 1 and 3:

> Prerelease for private dashboard distribution. Built from `<SHA>` with the account-bound
> developer key, **N of M device parts** across the **P** manifest products, `run-tests` green at
> **T/T** in the Connect IQ <sdk version> simulator.

Then, in this order:

1. **What changed and why**, one section per user-facing change, each with the measurement that
   justifies it and the issue or PR number. A number in the body must be regenerable from a
   committed tool over a committed fixture; if it is not, delete the number and keep the claim in
   words, or do not make the claim.
2. **Not fixed, and said so.** Anything the change explicitly leaves out (the wrap crossing, the
   3:1 band, a device family) with its open issue.
3. A section headed exactly **"Stated plainly: what this release does NOT establish"**, listing
   what has never run on hardware, what is inferred rather than measured, and what a field test
   would have to confirm. Write this section every time; the release whose only change was the
   one nobody had decoded from a real file needed it most.
4. A footer line with the `globals` ceiling headroom on the binding device family, and a
   "Known and tracked" list of issue numbers.

Style: sentences a domain reader can check, no adjectives doing the work of numbers, old figures
quoted beside corrected ones rather than deleted.

## 5. Tag the exact commit and publish

```bash
git -C "$REPO" fetch origin
[ "$(git -C "$REPO" rev-parse "$REMOTE_MAIN")" = "$(git -C "$REPO" rev-parse "$SHA")" ] || echo "STOP: main moved"
git -C "$REPO" tag -a "$VERSION" "$SHA" -m "<one line naming the headline change and PR numbers>"
git -C "$REPO" push origin "$VERSION"
gh release create "$VERSION" --prerelease --title "$VERSION" --notes-file "$NOTES" \
  "$OUT/$APP-$VERSION.iq" "$OUT/$APP-$VERSION-$TEST_DEVICE.prg"
gh release view "$VERSION" --json tagName,isPrerelease,url,assets
```

- Asset filenames carry the version. `StrongRow-v0.9.2.iq`, never `StrongRow.iq`.
- Flag per the `PRERELEASE` row's policy; the `latest` flag is allowed to sit on an older
  release (even a superseded one, while in beta), and that is the owner's call, not something to "fix".
- Re-read the asset list from the `gh release view` output and put the sizes in your report.

## 6. Superseding a bad release (only when the new release replaces a defective one)

Do not delete the release and do not move the tag; people have downloaded it. Prepend to the old
body, in this form, and edit the title so a list view shows it:

```
## ⚠️ Superseded by [vX.Y.Z](<url>) — do not upload this build.

> **What has to happen for it to fire:** <the precondition, concretely>.
> **What it costs when it does:** <what the user loses, concretely; the recording? the screen?>.
> Issue #N; fixed in #M.
```

```bash
gh release edit vOLD --title "vOLD — SUPERSEDED by vNEW (<the defect in a phrase>)" --notes-file "$OLDBODY"
```

State the firing condition and the cost plainly. A notice that overstates the risk trains readers
to ignore the next one; one that understates it is why they upload the bad build. A release that
merely lacks a feature (a new device family) is not superseded; the new release just says so.

## 7. Report

Report in this shape, nothing else first:

- the release URL, tag, prerelease flag
- the provenance figures as measured: commit, `N of M`, products, suite total, `.prg` size
- what changed, in the body's own words
- the "does NOT establish" list, verbatim from the body
- what was not verified in this run (Docker down, no hardware, a decoder not checked)

## Mid-work hazards that fire during a release

- Never `git add .`, `-A`, or `commit -a` (nested worktrees under the repo root).
- Never write a key into the workspace; never `openssl genrsa -out developer_key.pem` with a
  workspace-relative path.
- `set -o pipefail` for anything whose result you quote; a `monkeyc` failure piped through `grep`
  reports the grep's success.
- Never kill a shared simulator.
- `monkeydo` exits non-zero on success; read the `PASSED` line, not the exit code.
- Do not tag from a working tree that is behind `origin/main`; four "unfixed" P1s were once three
  fixed ones read from a stale checkout.
