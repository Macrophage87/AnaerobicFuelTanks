#!/usr/bin/env bash
# Fail if the Connect IQ manifest application id is missing, not 32 hex chars, or a
# placeholder (all-zero / all-same). A bad id compiles and passes tests but is
# rejected by the store, so this is a packaging gate the compile job can't cover.
#
# Usage: check_manifest_appid.sh [path/to/manifest.xml]   (default: manifest.xml)
set -euo pipefail

f="${1:-manifest.xml}"
[ -f "$f" ] || { echo "::error::manifest not found: $f"; exit 1; }

id="$(grep -oiE 'id="[0-9a-f]{32}"' "$f" | head -1 | sed -E 's/.*"([0-9a-fA-F]{32})".*/\1/')"
[ -n "$id" ] || { echo "::error::application id missing or not 32-hex in $f"; exit 1; }

case "$id" in
  00000000000000000000000000000000) echo "::error::placeholder (all-zero) app id"; exit 1;;
esac
printf '%s' "$id" | grep -qiE '^(.)\1{31}$' && { echo "::error::placeholder-like (all-same) app id"; exit 1; }

echo "manifest app id OK: $id"
