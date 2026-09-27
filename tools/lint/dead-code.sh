#!/bin/sh
# Dead-code gate: fail when Periphery finds an unused declaration, an assigned but
# never read property, an unused import, or a redundant conformance that is not
# in the baseline.
#
# Periphery reads the index store the compiler writes while building, so the scan
# itself does not build. `make dead-code`, which the pre-push hook runs, builds
# every target first through `make verify-build`. A stale index store shows stale
# results, which is why the index must come from builds of the current tree.
#
# The baseline holds findings keyed by declaration (USR), so edits elsewhere in a
# file do not disturb it. The open cleanup lives in a GitHub issue, not here.
#
# Usage: tools/lint/dead-code.sh      check (make dead-code)
#        tools/lint/dead-code.sh -u   rewrite the baseline after a cleanup
#                                     (make dead-code-baseline)
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
# The Makefile exports the derived-data root; this is the fallback for a direct
# run. tools/xcodebuild-lib.sh derives its own fallback from a tools/ script path,
# which this one is not.
: "${OPENSKY_DERIVED_DATA:=$root/DerivedData}"

config="tools/lint/.periphery.yml"
baseline="tools/lint/periphery-baseline.json"
index_store="$OPENSKY_DERIVED_DATA/Index.noindex/DataStore"

if ! command -v periphery >/dev/null 2>&1; then
  printf '[FAIL] periphery not found. Run: make bootstrap\n' >&2
  exit 1
fi
if [ ! -d "$index_store" ]; then
  printf '[FAIL] no index store at %s. Build first: make dead-code\n' "$index_store" >&2
  exit 1
fi

if [ "${1:-}" = "-u" ]; then
  periphery scan --config "$config" --index-store-path "$index_store" \
    --write-baseline "$baseline" --quiet >/dev/null
  echo "[ OK ] rewrote $baseline"
  exit 0
fi

if periphery scan --config "$config" --index-store-path "$index_store" \
  --baseline "$baseline" --strict --quiet; then
  echo "[ OK ] no new unused code"
  exit 0
fi
printf '[FAIL] New unused code. Delete it, use it, or mark it with a reasoned\n' >&2
printf '       "// periphery:ignore - <why>" comment.\n' >&2
exit 1
