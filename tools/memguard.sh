#!/bin/sh
# Physical-footprint watchdog for heavy real-data runs (streaming test, app).
# `ps` RSS misses Metal/IOSurface allocations; `footprint` reads Darwin's
# task_vm_info.phys_footprint ledger, matching Activity Monitor + jetsam.
# Polls every 2s and kills an OpenSky test host/app before system pressure.
#
# Usage: tools/memguard.sh DERIVED_DATA [CAP_MB] [MAX_SECONDS]
#   DERIVED_DATA the derived-data folder of the guarded run; only processes
#                that run or load a test bundle from its Build/Products
#   CAP_MB       kill threshold, physical-footprint MB (default 4096 = 4 GB)
#   MAX_SECONDS  self-exit after this long (default 900)
set -eu

if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "[ERROR] usage: tools/memguard.sh DERIVED_DATA [CAP_MB] [MAX_SECONDS]" >&2
    exit 2
fi
# A name match would also catch other checkouts' test runs and the installed app.
products="${1%/}/Build/Products/"
cap_mb="${2:-4096}"
max_seconds="${3:-900}"
cap_bytes=$((cap_mb * 1024 * 1024))

echo "[MEMGUARD] cap ${cap_mb} MB, timeout ${max_seconds}s, products ${products}"

start=$(date +%s)
peak_bytes=0
while :; do
    now=$(date +%s)
    if [ $((now - start)) -ge "$max_seconds" ]; then
        peak_mb=$((peak_bytes / 1024 / 1024))
        echo "[MEMGUARD] timeout reached, exiting (peak ${peak_mb} MB)"
        exit 0
    fi

    # comm is the executable path without arguments, so a compiler that only
    # names the products folder in its arguments does not match. A package
    # test runs in Xcode's xctest agent; its environment names the bundle.
    targets=$({
        ps -axo pid=,rss=,comm= 2>/dev/null \
            | awk -v products="$products" \
                '{ path = $0; sub(/^ *[0-9]+ +[0-9]+ /, "", path) }
                 index(path, products) == 1 { print $1, $2 }'
        ps -axwwE -o pid=,rss=,command= 2>/dev/null \
            | awk -v products="$products" \
                'index($0, "XCTestBundlePath=" products) > 0 { print $1, $2 }'
    } | sort -u -k1,1 || true)
    old_ifs=$IFS
    IFS='
'
    for target in $targets; do
        IFS=$old_ifs
        pid=$(echo "$target" | awk '{print $1}')
        rss_kb=$(echo "$target" | awk '{print $2}')
        sample=$(footprint -p "$pid" -f bytes --noCategories 2>/dev/null \
            | awk '/phys_footprint:/ { print $2; exit }' || true)
        if [ -z "$sample" ]; then
            if kill -0 "$pid" 2>/dev/null; then
                echo "[MEMGUARD] KILL pid ${pid}: physical-footprint sample failed"
                kill -9 "$pid" 2>/dev/null || true
            fi
            IFS='
'
            continue
        fi
        if [ "$sample" -gt "$peak_bytes" ]; then
            peak_bytes=$sample
            peak_mb=$((peak_bytes / 1024 / 1024))
            echo "[MEMGUARD] peak ${peak_mb} MB (pid ${pid})"
        fi
        if [ "$sample" -gt "$cap_bytes" ]; then
            footprint_mb=$((sample / 1024 / 1024))
            rss_mb=$((rss_kb / 1024))
            echo "[MEMGUARD] KILL pid ${pid} footprint ${footprint_mb} MB, " \
                "rss ${rss_mb} MB > cap ${cap_mb} MB"
            kill -9 "$pid" 2>/dev/null || true
        fi
        IFS='
'
    done
    IFS=$old_ifs

    sleep 2
done
