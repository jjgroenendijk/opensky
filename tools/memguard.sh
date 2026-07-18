#!/bin/sh
# Physical-footprint watchdog for heavy real-data runs (streaming test, app).
# `ps` RSS misses Metal/IOSurface allocations; `footprint` reads Darwin's
# task_vm_info.phys_footprint ledger, matching Activity Monitor + jetsam.
# Polls every 2s and kills an OpenSky test host/app before system pressure.
#
# Usage: tools/memguard.sh [CAP_MB] [MAX_SECONDS]
#   CAP_MB       kill threshold, physical-footprint MB (default 4096 = 4 GB)
#   MAX_SECONDS  self-exit after this long (default 900)
set -eu

cap_mb="${1:-4096}"
max_seconds="${2:-900}"
cap_bytes=$((cap_mb * 1024 * 1024))

# Match unit-test hosts, app, and CLI benchmark; never this script or grep.
pattern='opensky\.app/Contents/MacOS/opensky|Debug/openskycli( |$)|openskyTests\.xctest|openskyUITests|xctest'

echo "[MEMGUARD] cap ${cap_mb} MB, timeout ${max_seconds}s, pattern ${pattern}"

start=$(date +%s)
peak_bytes=0
while :; do
    now=$(date +%s)
    if [ $((now - start)) -ge "$max_seconds" ]; then
        peak_mb=$((peak_bytes / 1024 / 1024))
        echo "[MEMGUARD] timeout reached, exiting (peak ${peak_mb} MB)"
        exit 0
    fi

    # shellcheck disable=SC2009
    targets=$(ps -axo pid=,rss=,command= 2>/dev/null \
        | grep -E "$pattern" \
        | grep -v -E 'memguard|grep' || true)
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
