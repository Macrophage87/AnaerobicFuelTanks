#!/usr/bin/env bash
# #42 regression fence: the "SET CP/W'" guard (DualTankView.onUpdate) is only reachable when
# CP and W' carry the SENTINEL 0 default in properties.xml. A non-zero default (e.g. the former
# 250 / 20000) makes Application.Properties.getValue() never look "unset", so mConfigured is
# always true and the guard is dead — the exact PR #74 round-1 root cause.
#
# The (:test) that also asserts this (testCpWprimeDefaultUnconfigured) cannot gate CI: the
# headless simulator segfaults under Xvfb and SKIPS the whole (:test) suite (the ciq-test job is
# best-effort/green-on-skip). So this script is the ENFORCEABLE gate — it runs in the required
# manifest-lint job and fails a properties-only revert of the defaults.
#
# Usage: check_settings_defaults.sh [path/to/properties.xml]
set -euo pipefail

f="${1:-connectiq/resources/settings/properties.xml}"
[ -f "$f" ] || { echo "::error::properties.xml not found: $f"; exit 1; }

check() {
  key="$1"
  val="$(sed -n "s/.*<property[[:space:]]\{1,\}id=\"${key}\"[^>]*>\([^<]*\)<\/property>.*/\1/p" "$f" | tr -d '[:space:]')"
  [ -n "$val" ] || { echo "::error::property '${key}' missing or has no default in $f"; exit 1; }
  if [ "$val" != "0" ]; then
    echo "::error::property '${key}' default is '${val}', expected sentinel '0'. A non-zero default re-inerts the #42 SET CP/W' guard (mConfigured always true)."
    exit 1
  fi
  echo "ok: ${key} defaults to sentinel 0"
}

check CP
check Wprime
echo "settings defaults OK: $f"
