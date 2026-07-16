#!/usr/bin/env bash
# Fail if tools/calibrate/manifest.json no longer describes the committed files:
#   (1) any listed file whose md5 != its recorded checksum,
#   (2) any listed file missing on disk,
#   (3) any deployable file on disk that the manifest omits.
#
# Why this matters: a git-backed Posit Connect deploy reads this committed manifest
# and restores the bundle from it, so a stale checksum means Connect ships a
# manifest describing a DIFFERENT app.R than the one actually served. It is a
# freshness gate the r-lint `parse()` step can't see — the files parse fine; the
# manifest simply lies about them.
#
# Package-free by design (jq + md5sum + coreutils only) so it stays fast and
# independent of the app's R dependency closure. It shares only the `::error::`
# annotation STYLE with scripts/check_manifest_appid.sh — that script greps/seds
# manifest.xml and uses neither jq nor md5sum; there is no shared tooling beyond
# the annotation convention.
#
# Line endings: the committed manifest was generated on Windows, but its checksums
# are the md5 of the bytes committed to git. Keep the repo's line endings stable
# (see .gitattributes) so a Linux CI checkout hashes the same bytes; a stray
# CRLF<->LF normalization would change the md5 and trip this gate spuriously.
#
# Scope: this verifies FILE integrity only, not the pinned packages{} closure. The
# canonical refresh is `rsconnect::writeManifest(".")` (see tools/calibrate/deploy.R).
# Hand-fixing a checksum makes this gate pass but does NOT update package versions.
#
# Usage: check_calibrate_manifest.sh [path/to/manifest.json]
#        (default: tools/calibrate/manifest.json)
set -euo pipefail

manifest="${1:-tools/calibrate/manifest.json}"
[ -f "$manifest" ] || { echo "::error::manifest not found: $manifest"; exit 1; }
dir="$(dirname "$manifest")"

command -v jq >/dev/null     || { echo "::error::jq not found on PATH"; exit 1; }
command -v md5sum >/dev/null || { echo "::error::md5sum not found on PATH"; exit 1; }

# Fail loudly on invalid JSON or a missing/empty .files object — otherwise the loop
# below iterates zero times and a broken manifest passes as a green "OK".
jq -e . "$manifest" >/dev/null 2>&1 \
  || { echo "::error file=$manifest::manifest is not valid JSON"; exit 1; }
n_files="$(jq -r '(.files // {}) | length' "$manifest")"
if [ "${n_files:-0}" -eq 0 ]; then
  echo "::error file=$manifest::manifest has no .files entries (expected the deploy file list)"
  exit 1
fi

rc=0

# (1)+(2) every listed file exists on disk and matches its recorded checksum.
while IFS=$'\t' read -r name recorded; do
  path="$dir/$name"
  if [ ! -f "$path" ]; then
    echo "::error file=$manifest::listed file missing on disk: $name"
    rc=1; continue
  fi
  actual="$(md5sum "$path" | cut -d' ' -f1)"
  if [ "$actual" != "$recorded" ]; then
    echo "::error file=$path::stale manifest checksum for $name (recorded=$recorded actual=$actual) — re-run rsconnect::writeManifest(\".\") in tools/calibrate and commit"
    rc=1
  fi
done < <(jq -r '.files | to_entries[] | "\(.key)\t\(.value.checksum)"' "$manifest")

# (3) every deployable file on disk is listed. A new file the manifest omits would
# ship a broken/incomplete bundle. Excludes the manifest itself and dotfiles; the
# calibrate app dir is flat, so a maxdepth-1 scan covers it.
while IFS= read -r f; do
  base="$(basename "$f")"
  case "$base" in manifest.json|.*) continue ;; esac
  if ! jq -e --arg k "$base" '.files | has($k)' "$manifest" >/dev/null; then
    echo "::error file=$f::file present in $dir but not listed in manifest .files: $base — re-run rsconnect::writeManifest(\".\") and commit"
    rc=1
  fi
done < <(find "$dir" -maxdepth 1 -type f)

[ "$rc" -eq 0 ] && echo "calibrate manifest OK: $n_files files match their recorded checksums"
exit "$rc"
