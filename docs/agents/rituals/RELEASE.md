# Ritual: cutting a release

Read this **when you are cutting a release**. Publishing a release asset is the
highest-reversibility-cost action in this repository (`DISPATCH.md`, R=3): a
downloaded `.iq` cannot be recalled, only superseded — and the Connect IQ
Store-Version is a second irreversible surface on top of the GitHub asset.

Facts and canonical command forms: `docs/agents/FACTS.md`.

---

## 1. What CI does NOT do

CI **compiles** the app on two devices with a throwaway key and never exports
an `.iq` (`FACTS.md` §1.2). There is no release-build job. **A real release is
built locally from a clean archive, exported for all 15 manifest products, and
signed with the account-bound developer key.** Every release body records that
provenance.

## 2. Build from a clean archive, never the working tree

```sh
git -c core.autocrlf=false archive --format=tar <tag-or-sha> | tar -x -C CLEANDIR
cd CLEANDIR/connectiq
```

* **`core.autocrlf=false`.** The working tree holds CRLF while the index and
  CI hold LF (`FACTS.md` §4.1); `monkeyc` accepts a raw newline inside a
  literal with no diagnostic.
* **The working tree is not the commit.** `connectiq/bin/` holds build output,
  and `.claude/worktrees/` holds other checkouts inside the repository root.
* **Archive the tag, not `HEAD`.** The release body names a commit; that commit
  must be what was built.

## 3. Sign with the account-bound key, and never near the workspace

**Never run `openssl genrsa -out developer_key.pem` with a workspace-relative
path.** It would silently destroy a real account-bound key. Refer to the real
key by absolute path (`CIQ_KEY=`), and to throwaway keys by scratch path.

## 4. Export and read the device count off the export

```sh
<sdk>/bin/monkeyc.bat -e -f monkey.jungle -o "bin/DualTank-v<X.Y>.iq" -y <account-key>.der -w
```

`monkeyc -e` prints **`N OUT OF M DEVICES BUILT`**. **Read N and M from this
export's own output; do not copy them forward.** The `.iq` is not a zip archive
and cannot be enumerated afterwards. M is 15 at `30b2b99` (`FACTS.md` §1.4);
`N < M` is a **failed** export, not a partial success. Stop.

## 5. Asset naming carries the version in the filename

```
DualTank-v0.8.iq
DualTank-v0.8-edge1050.prg
```

`v0.6` shipped `DualTank.iq` and `v0.7` shipped `DualTank-0.7.iq`
(`FACTS.md` §5.5). A downloaded asset must say what it is without its
surrounding page; pass the versioned name to `monkeyc -o` so the build log and
the asset agree.

## 6. The on-device gate is record-AND-save, before the tag

#96 established that CI cannot see a load crash. The gate that stands in for
it, from #98 item 1: on the reporting device (Edge 1050, `006-B4440-00`) with
the release build sideloaded, **start an activity, let it record, and save** —
then decode the saved FIT and confirm every developer field in `FACTS.md`
§5.3 is declared and populated. Byte-exact criteria go in a `[Local]` issue;
the decode output goes in the release body. A build that loads but has not
saved a file has not passed this gate.

## 7. The suite total in the release body is a measurement, not a memory

The `(:test)` suite runs only locally (`FACTS.md` §1.2). Quote the
`PASSED (passed=N, failed=0, errors=0)` line from a `monkeydo` run **on the
exact commit being tagged**, with N equal to `scripts/expected_tests.txt`'s
count; and quote the CI check-runs for that commit (all required checks
`success`). If any two of these disagree, one of them is stale and the release
stops until you know which.

## 8. Tag, publish, and label honestly

* Tag the exact commit the body names.
* Flags follow the owner's policy (2026-09-06): while the store listing is in
  **beta** (pre-1.0) only the owner sees these builds, so flags stay as cut and
  older releases are not re-flagged — `v0.6` keeps `latest` with its superseded
  title and warning. From **1.0** on, every test or gate build is flagged
  **prerelease** and a plain release is cut only when the owner says "official".
* The body opens with the provenance sentence — commit, key, `N of M` devices,
  product count, suite line — before any feature prose.
* A section headed **"Stated plainly: what this release does NOT establish"**,
  every time: which devices were not loaded, which fields were not decoded,
  which settings paths were not exercised.

---

## Superseding a bad release

The form, verified on `v0.7`'s body (which opens with a blockquote telling
v0.6 users to replace it):

1. **Do not delete the release and do not move the tag.**
2. **Prepend a ⚠️ blockquote to the superseded release body**, linking the
   replacement, in the imperative.
3. **Edit the release title** to carry it too — `v0.6 — SUPERSEDED by v0.7
   (crashes at load on every target)` — so `gh release list` shows it. **This
   has not been done for `v0.6`** at `30b2b99`: its title is still
   "DualTank v0.6" and it still carries `latest`.
4. **Say what has to happen for it to fire, and what it costs when it does.**
5. **Cut the replacement from a fresh archive.**

---

## Mid-work hazards that fire during a release

* **Never `git add .` / `-A` / `commit -a`** (`FACTS.md` §4.2).
* **Never write a key into the workspace** (§3 above, `FACTS.md` §4.4).
* **`set -o pipefail`** — a `monkeyc` failure piped through `grep` reports the
  grep's success (`FACTS.md` §2.6).
* **Never kill a shared simulator** (`FACTS.md` §4.5).
