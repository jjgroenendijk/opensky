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
run "collision grid (5x5 around first-render cell)" collision --radius 2

# M5.1/5.2 actor gate: every discovered ACHR around the first-render cell
# must resolve its template chain AND its visuals (skeleton, skin/outfit
# parts, FaceGen) — the summary line reports "N failed".
run "actor probe (3x3 around first-render cell)" actor
grep 'ACHRs discovered' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "actor probe reported unresolved ACHRs"

# M5.2 named-NPC gate: a named Whiterun resident resolves skeleton, worn
# parts, and FaceGen paths without a placed ACHR.
run "actor visual (Heimskr)" actor --npc Heimskr
heimskr="$(sed -n '/^--- actor visual (Heimskr)/,$p' "$log")"
printf '%s\n' "$heimskr" | grep -q '^  skeleton ' \
  || fail "named NPC probe reported no skeleton"
printf '%s\n' "$heimskr" | grep -q '^  part ' \
  || fail "named NPC probe reported no body parts"
printf '%s\n' "$heimskr" | grep -q '^  facegen meshes' \
  || fail "named NPC probe reported no FaceGen path"

# Inspect the first mesh + texture the archives provide.
mesh_key="$("$cli" --data-root "$data_root" vfs ls 'meshes\*.nif' 2>/dev/null \
  | head -1 | cut -f1)"
run "nif inspect ($mesh_key)" nif "$mesh_key"
dds_key="$("$cli" --data-root "$data_root" vfs ls 'textures\*.dds' 2>/dev/null \
  | head -1 | cut -f1)"
run "dds inspect ($dds_key)" dds "$dds_key"

# Offscreen screenshot of the first-render cell -> logs/probe-screenshot.png.
png="$log_dir/probe-screenshot.png"
run "offscreen screenshot" screenshot --out "$png"
[ -s "$png" ] || fail "screenshot wrote no PNG"
echo "[ OK ] screenshot output: $png"

# M3.6 interior gate: find one teleport door near Whiterun, follow XTEL in,
# render exact arrival pose, follow paired door back to exterior.
interior_png="$log_dir/probe-interior.png"
run "interior door round trip" interior --out "$interior_png"
[ -s "$interior_png" ] || fail "interior probe wrote no PNG"
echo "[ OK ] interior output: $interior_png"

# Sustained fps gate (todo 2.11): 360 frames at 720p via frame stats; the
# command exits 1 when avg/p95 frame time misses the 33.3 ms (30 fps) budget.
run "sustained bench (360 frames @ 1280x720)" bench
grep 'frames @' "$log" | tail -1

# M3.2 streaming gate: deterministic east + north crossings. Shared engine
# verifier requires three settled 5x5 grids, eviction, 35 unique builds with
# no duplicates, physical-footprint plateau, and avg/p95 under 30 fps budget.
run "cross-cell streaming bench (640x360)" bench --fly-path --size 640x360
grep 'unique builds' "$log" | tail -1
grep 'collision build:' "$log" | tail -1

# M4.5 route gate: fixed-step production physics from first-render cell to
# Chillfurrow Farm, interior floor crossing, then paired exterior return.
walk_png="$log_dir/probe-walk-path.png"
run "walk/collision route bench (640x360)" bench --walk-path --size 640x360 \
  --out "$walk_png"
[ -s "$walk_png" ] || fail "walk-path bench wrote no PNG"
grep 'active physics frames @' "$log" | tail -1
echo "[INFO] probe passed — full output in $log"
