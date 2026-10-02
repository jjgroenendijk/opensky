#!/bin/sh
# Unused-code gate: fail when Periphery finds an unused declaration, an assigned
# but never read property, an unused import, or a redundant conformance. No
# baseline: the tree starts at zero. Periphery reads the index store of the
# uncached build `make health` runs first, so a stale index gives stale results.
#
# Usage: tools/lint/unused-code.sh CONFIG INDEX_STORE
set -eu

[ "$#" -eq 2 ] || { echo "[ERROR] usage: unused-code.sh CONFIG INDEX_STORE" >&2; exit 2; }
config="$1"
index_store="$2"
cd "$(git rev-parse --show-toplevel)"

if ! command -v periphery >/dev/null 2>&1; then
  printf '[FAIL] periphery not found. Run: make bootstrap\n' >&2
  exit 1
fi
if [ ! -d "$index_store" ]; then
  printf '[FAIL] no index store at %s. Run: make health\n' "$index_store" >&2
  exit 1
fi

if periphery scan --config "$config" --index-store-path "$index_store" --strict --quiet; then
  echo "[ OK ] no unused code"
  exit 0
fi
printf '[FAIL] Unused code. Delete it or use it; do not add periphery:ignore.\n' >&2
exit 1
