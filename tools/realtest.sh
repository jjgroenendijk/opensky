#!/bin/sh
# Run one env-gated real-data test under the physical-footprint watchdog.
#
# xcodebuild `test` does NOT forward OPENSKY_DATA_ROOT to the unit-test host
# (proven: the host sees <nil>), so gated real-data tests silently skip. This
# script does it the reliable way: build-for-testing, inject the data root into
# the generated .xctestrun EnvironmentVariables, then test-without-building --
# with tools/memguard.sh running alongside so a memory runaway is killed before
# it can lock the machine. See docs/engine/cell-streaming.md (memory budget).
#
# Usage: tools/realtest.sh <only-testing-selector> [CAP_MB]
#   e.g. tools/realtest.sh \
#          'openskyTests/CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
# Env: OPENSKY_DATA_ROOT overrides the install path.
set -eu

if [ "$#" -lt 1 ]; then
    echo "[ERROR] usage: tools/realtest.sh <only-testing-selector> [CAP_MB]" >&2
    exit 2
fi

selector="$1"
cap_mb="${2:-4096}"
data_root="${OPENSKY_DATA_ROOT:-/Volumes/data/steam/steamapps/common/Skyrim Special Edition}"
dd="$HOME/Library/Developer/Xcode/DerivedData/opensky-realtest"
result_bundle="logs/realtest-$$.xcresult"
output_log="logs/realtest-$$.log"
enumeration_json="logs/realtest-enumeration-$$.json"

mkdir -p logs
cleanup() {
    kill "${guard_pid:-}" 2>/dev/null || true
    rm -rf "$result_bundle"
    rm -f "$enumeration_json"
}
trap cleanup EXIT INT TERM

if [ ! -e "$data_root/Data/Skyrim.esm" ] && [ ! -e "$data_root/Skyrim.esm" ]; then
    echo "[ERROR] no Skyrim install at $data_root (set OPENSKY_DATA_ROOT)" >&2
    exit 1
fi

echo "[INFO] build-for-testing -> $dd"
xcodebuild build-for-testing -project opensky.xcodeproj -scheme opensky \
    -derivedDataPath "$dd" -destination 'platform=macOS' >/dev/null

xctestrun=$(find "$dd/Build/Products" -maxdepth 1 -name '*.xctestrun' | head -1)
if [ -z "$xctestrun" ]; then
    echo "[ERROR] no .xctestrun produced" >&2
    exit 1
fi

echo "[INFO] injecting OPENSKY_DATA_ROOT into $xctestrun"
OPENSKY_DATA_ROOT="$data_root" python3 - "$xctestrun" <<'PY'
import os, plistlib, sys
path = sys.argv[1]
root = os.environ["OPENSKY_DATA_ROOT"]
data = plistlib.load(open(path, "rb"))
def walk(node):
    if isinstance(node, dict):
        env = node.get("EnvironmentVariables")
        if isinstance(env, dict):
            env["OPENSKY_DATA_ROOT"] = root
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
walk(data)
plistlib.dump(data, open(path, "wb"))
PY

echo "[INFO] validating exact selector: $selector"
xcodebuild test-without-building -xctestrun "$xctestrun" -derivedDataPath "$dd" \
    -destination 'platform=macOS' -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 -only-testing:"$selector" \
    -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
    -test-enumeration-output-path "$enumeration_json" >/dev/null
SELECTOR="$selector" python3 - "$enumeration_json" <<'PY'
import json, os, sys
with open(sys.argv[1], "rb") as stream:
    data = json.load(stream)
enabled = [
    test.get("identifier")
    for value in data.get("values", [])
    for test in value.get("enabledTests", [])
]
expected = os.environ["SELECTOR"]
if data.get("errors") or enabled != [expected]:
    print(
        f"[ERROR] selector must resolve to exactly one test: {expected}; got {enabled}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY

echo "[INFO] starting watchdog (cap ${cap_mb} MB)"
sh tools/memguard.sh "$cap_mb" 900 &
guard_pid=$!

echo "[INFO] test-without-building: $selector"
status=0
xcodebuild test-without-building -xctestrun "$xctestrun" -derivedDataPath "$dd" \
    -only-testing:"$selector" -destination 'platform=macOS' \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    -resultBundlePath "$result_bundle" >"$output_log" 2>&1 || status=$?
cat "$output_log"

kill "$guard_pid" 2>/dev/null || true
guard_pid=""
if [ "$status" -ne 0 ]; then
    exit "$status"
fi

# `-only-testing` accepts a misspelled Swift Testing method and exits 0 after
# running zero tests. Trust the result bundle, not xcodebuild's status.
summary=$(xcrun xcresulttool get test-results summary \
    --path "$result_bundle" --format json | python3 -c '
import json, sys
summary = json.load(sys.stdin)
keys = ("totalTestCount", "passedTests", "skippedTests", "failedTests")
print(" ".join(str(summary.get(key, -1)) for key in keys))
')
if [ "$summary" != "1 1 0 0" ]; then
    echo "[ERROR] exact test did not pass once ($summary): $selector" >&2
    exit 1
fi
echo "[INFO] selector executed exactly one test"
