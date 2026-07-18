#!/bin/sh
# Env-gated smoke probe: drive openskycli against the local Skyrim SE
# install (docs/tools/cli.md). Self-skips with [INFO] when no install is
# present (CI has no game data). Install is read-only external input;
# outputs go to logs/ only (AGENTS.md Legal & IP + Code scripts).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
data_root="${OPENSKY_DATA_ROOT:-/Volumes/data/steam/steamapps/common/Skyrim Special Edition}"
log_dir="$root/logs"
log="$log_dir/probe.log"
mkdir -p "$log_dir"

if [ ! -f "$data_root/Data/Skyrim.esm" ] && [ ! -f "$data_root/Skyrim.esm" ]; then
  echo "[INFO] no Skyrim SE install at $data_root — skipping probe"
  exit 0
fi

echo "[INFO] building openskycli (log: $log)"
xcodebuild -project "$root/opensky.xcodeproj" -scheme openskycli -configuration Debug \
  build >"$log" 2>&1
products_dir="$(xcodebuild -project "$root/opensky.xcodeproj" -scheme openskycli \
  -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/ { print $2; exit }')"
cli="$products_dir/openskycli"
[ -x "$cli" ] || { echo "[ERROR] openskycli binary not found at $cli"; exit 1; }

fail() {
  echo "[ERROR] probe failed: $1 (see $log)"
  exit 1
}

# printf, not echo: resource keys carry backslashes echo may interpret.
run() {
  step="$1"
  shift
  {
    printf -- '--- %s\n' "$step"
    "$cli" --data-root "$data_root" "$@"
  } >>"$log" 2>&1 || fail "$step"
  printf '[ OK ] %s\n' "$step"
}

# vfs ls resolves archives and finds meshes.
mesh_count="$("$cli" --data-root "$data_root" vfs ls 'meshes\*.nif' 2>>"$log" | wc -l)"
[ "$mesh_count" -gt 0 ] || fail "vfs ls found no meshes"
echo "[ OK ] vfs ls ($mesh_count mesh entries)"

# Record probe: Tamriel WRLD is FormID 0x3C (UESP "Skyrim Mod:FormIDs").
"$cli" --data-root "$data_root" record 0x0000003C 2>>"$log" | grep -q Tamriel \
  || fail "record 0x3C did not decode as Tamriel"
echo "[ OK ] record 0x0000003C (Tamriel)"

run "cell summary (first-render cell)" cell

# Inspect the first mesh + texture the archives provide.
mesh_key="$("$cli" --data-root "$data_root" vfs ls 'meshes\*.nif' 2>/dev/null \
  | head -1 | cut -f1)"
run "nif inspect ($mesh_key)" nif "$mesh_key"
dds_key="$("$cli" --data-root "$data_root" vfs ls 'textures\*.dds' 2>/dev/null \
  | head -1 | cut -f1)"
run "dds inspect ($dds_key)" dds "$dds_key"

# Offscreen render of the first-render cell -> logs/probe-render.png.
png="$log_dir/probe-render.png"
run "offscreen render" render --out "$png"
[ -s "$png" ] || fail "render wrote no PNG"
echo "[ OK ] render output: $png"

# Sustained fps gate (todo 2.11): 360 frames at 720p via frame stats; the
# command exits 1 when avg/p95 frame time misses the 33.3 ms (30 fps) budget.
run "sustained bench (360 frames @ 1280x720)" bench
grep 'frames @' "$log" | tail -1
echo "[INFO] probe passed — full output in $log"
