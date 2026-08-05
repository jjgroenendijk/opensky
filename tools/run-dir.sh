#!/bin/sh
# Allocate the output directory for one run of one script (issue #347).
#
# Every script that writes output a human reads later — an xcodebuild
# transcript, a probe capture, an .xcresult bundle — puts it under
# <base>/<name>/<UTC timestamp>/ and points <base>/<name>/latest at the newest
# run. One run is then one directory: it can be linked whole from a PR body,
# a stale capture cannot be mistaken for the current one, and `make prune` can
# age a run out without guessing which loose file belonged to which run.
#
# Usage: tools/run-dir.sh [-b BASE] NAME
#   BASE  where the per-script tree lives, relative to the repo root. Default
#         "logs"; result bundles pass "build/test-results".
#   NAME  the script or make target the run belongs to (probe, test-ui, unit).
#
# Prints the absolute path of the created run directory. A script that calls
# another script exports OPENSKY_RUN_DIR instead, so both write into one run.
set -eu

base=logs
while [ "$#" -gt 0 ]; do
    case "$1" in
        -b)
            [ "$#" -ge 2 ] || { echo "[ERROR] -b needs a directory" >&2; exit 2; }
            base="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "[ERROR] unknown option: $1" >&2
            exit 2
            ;;
        *) break ;;
    esac
done

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "[ERROR] usage: tools/run-dir.sh [-b BASE] NAME" >&2
    exit 2
fi

name="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
parent="$root/$base/$name"

# Timestamps sort lexicographically, which is what `make prune` compares
# against its retention cutoff and how "newest run" is decided.
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
# Two runs can start inside the same second (a make target that chains
# scripts); the second one must not land on top of the first.
suffix=""
attempt=1
while [ -e "$parent/$stamp$suffix" ]; do
    suffix="-$attempt"
    attempt=$((attempt + 1))
done

mkdir -p "$parent/$stamp$suffix"
# Relative target, so the tree survives the checkout being moved.
ln -sfn "$stamp$suffix" "$parent/latest"
printf '%s\n' "$parent/$stamp$suffix"
