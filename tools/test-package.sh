#!/bin/sh
# Run one package test target, or part of it, without Xcode and without the app
# host (issue #582). `make test-fast T='<Module>Tests/...'` lands here when the
# selector's first component is a test target of Package.swift rather than one of
# the Xcode test bundles. `swift test` builds only the package, so a module's
# tests run without compiling the app, the CLI, or OpenSkyTests.
#
# Usage: tools/test-package.sh SELECTOR
#   SELECTOR  Target, Target/Suite, or Target/Suite/test() -- the same shape
#             xcodebuild's -only-testing takes.
#
# The package keeps its own build tree in .build/, apart from DerivedData/.
set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "[ERROR] usage: tools/test-package.sh Target[/Suite[/test()]]" >&2
    exit 2
fi
selector="$1"
target="${selector%%/*}"

root="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$root/Tests/$target" ]; then
    echo "[ERROR] no package test target $target (no Tests/$target/)" >&2
    exit 2
fi

# swift test names a test Target.Suite/test(), where -only-testing writes
# Target/Suite/test(). The filter is a regular expression, so the parentheses of
# a test function are escaped.
if [ "$selector" = "$target" ]; then
    filter="^$target\\."
else
    rest="${selector#*/}"
    filter="^$target\\.$(printf '%s' "$rest" | sed 's/[()]/\\&/g')"
fi

run_dir="$("$root/tools/run-dir.sh" test-package)"
printf '[INFO] run directory: %s\n' "$run_dir"
printf '[INFO] swift test --filter %s\n' "$filter"

status=0
(cd "$root" && swift test --filter "$filter") >"$run_dir/transcript.log" 2>&1 || status=$?
grep -E '(error|warning): |^✘|Test run with|Executed [0-9]+ tests?' "$run_dir/transcript.log" || true
if [ "$status" -ne 0 ]; then
    echo "[ERROR] swift test failed; transcript: $run_dir/transcript.log" >&2
    exit "$status"
fi

# A filter that matches nothing still exits 0, so count what ran.
ran="$(sed -n 's/.*Test run with \([0-9][0-9]*\) tests\{0,1\}.*/\1/p' "$run_dir/transcript.log" | tail -n 1)"
if [ -z "$ran" ] || [ "$ran" -lt 1 ]; then
    echo "[ERROR] selector matched no test: $selector" >&2
    exit 1
fi
echo "[ OK ] $target green ($ran tests)"
