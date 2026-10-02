#!/bin/sh
# Coverage floor for the parsers: fail when an OpenSkyFormats* module's line
# coverage in the last test run drops below FLOOR percent. Parsers read
# untrusted files, so an untested branch there can crash the app
# (docs/decisions/code-health-automation.md). Each test run rewrites the
# profile, so run this right after `make test-unit`: a filtered run reads too low.
#
# It reads the profile with llvm-cov, because `xccov` reports no package files
# from a bundle built with the compilation cache's prefix mapping.
#
# Usage: tools/lint/coverage-floor.sh FLOOR DERIVED_DATA
set -eu

[ "$#" -eq 2 ] || { echo "[ERROR] usage: coverage-floor.sh FLOOR DERIVED_DATA" >&2; exit 2; }
floor="$1"
build="$2/Build"

# shellcheck disable=SC2012  # newest-by-mtime of a few fixed-name files
profile="$(ls -t "$build"/ProfileData/*/Coverage.profdata 2>/dev/null | head -1)"
if [ -z "$profile" ]; then
  printf '[FAIL] no coverage profile under %s/ProfileData. Run: make test-unit\n' "$build" >&2
  exit 1
fi

frameworks="$(find "$build/Products/Debug/PackageFrameworks" -maxdepth 1 \
  -name 'OpenSkyFormats*.framework' 2>/dev/null | sort)"
if [ -z "$frameworks" ]; then
  printf '[FAIL] no OpenSkyFormats frameworks under %s. Run: make test-unit\n' "$build" >&2
  exit 1
fi

low=0
for framework in $frameworks; do
  name="$(basename "$framework" .framework)"
  percent="$(xcrun llvm-cov export -summary-only -instr-profile "$profile" \
    "$framework/$name" | jq '.data[0].totals.lines.percent')"
  if awk -v p="$percent" -v f="$floor" 'BEGIN { exit !(p >= f) }'; then
    printf '[ OK ] %-24s %6.2f%%\n' "$name" "$percent"
  else
    printf '[FAIL] %-24s %6.2f%%\n' "$name" "$percent"
    low=1
  fi
done

if [ "$low" -ne 0 ]; then
  printf '[FAIL] parser coverage under %s%%. Add tests for the untested branches.\n' "$floor" >&2
  exit 1
fi
printf '[ OK ] every parser module at or above %s%% line coverage\n' "$floor"
