#!/bin/sh
# The fakes in OpenSkySessionTesting match their ports: a fresh copy from tools/fakes.sh
# must equal the checked-in one, so a changed port fails here until `make fakes` runs.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkySessionInterface" "$tree/src/Tests/OpenSkySessionTesting"
    printf 'public protocol ProbePort: AnyObject {\n    func run()\n}\n' \
        >"$tree/src/Sources/OpenSkySessionInterface/ProbePort.swift"
    printf 'public final class FakeProbePort {}\n' \
        >"$tree/src/Tests/OpenSkySessionTesting/FakeProbePort.swift"
    expect_failure "$0" "$tree" "FakeProbePort.swift" "make fakes"
fi

cd "$(git rev-parse --show-toplevel)"
library=src/Tests/OpenSkySessionTesting
fresh="$(mktemp -d -t opensky-fakes)"
trap 'rm -rf "$fresh"' EXIT
sh "$OPENSKY_TOOLS/fakes.sh" "$fresh" >/dev/null
if ! diff -r -x '*.md' "$library" "$fresh" >"$fresh.diff" 2>&1; then
    echo "[ERROR] the fakes in $library do not match their ports:" >&2
    sed 's/^/  /' "$fresh.diff" | head -40 >&2
    echo "  Fix: run make fakes" >&2
    rm -f "$fresh.diff"
    exit 1
fi
rm -f "$fresh.diff"
echo "[ OK ] the fakes match their ports"
