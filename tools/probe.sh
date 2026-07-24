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

# M7.2 distant LOD gate: every terrain/object and tree LOD file in Tamriel
# parses, and tree-list indices resolve. No game data leaves the install.
run "distant LOD sweep" lod
grep 'LOD sweep:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "distant terrain/object LOD sweep reported failures"
grep 'tree LOD:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "tree LOD sweep reported failures"

# M8.2.1 SWF container gate: every vanilla Interface/*.swf movie parses (or,
# for ZWS/LZMA bodies, is accounted as unsupported) with zero unexpected
# failures. Vanilla install: 53 files, 0 unsupported, 0 failed, 0 unknown tags.
run "swf sweep (vanilla Interface movies)" swf sweep
grep 'swf sweep:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported unexpected parse failures"

# M8.2.2 SWF shape/bitmap gate: every DefineShape-DefineShape4 body decodes
# and tessellates, and every bitmap tag decodes to RGBA. Vanilla install:
# 2677 shapes, 453 bitmaps, 0 failed each.
grep 'swf sweep shapes:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported shape decode/tessellation failures"
grep 'swf sweep bitmaps:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported bitmap decode failures"

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

# M6.1 HKX container gate: dump the packfile inventory for a skeleton and a
# human idle animation. Both are hk_2010.2.0-r1 64-bit packfiles with the
# standard __classnames__/__data__ sections; skeleton carries an hkaSkeleton
# object, the idle an hkaSplineCompressedAnimation. Keys are single-quoted so
# backslashes + spaces reach the CLI verbatim (VFS keys, not shell paths).
run "hkx skeleton" hkx 'meshes\actors\character\character assets\skeleton.hkx'
skeleton_hkx="$(awk '/^--- hkx skeleton/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$skeleton_hkx" | grep -q 'hk_2010.2.0-r1' \
  || fail "hkx skeleton missing version string"
printf '%s\n' "$skeleton_hkx" | grep -q '__classnames__' \
  || fail "hkx skeleton missing __classnames__ section"
printf '%s\n' "$skeleton_hkx" | grep -q '__data__' \
  || fail "hkx skeleton missing __data__ section"
printf '%s\n' "$skeleton_hkx" | grep -q 'hkaSkeleton' \
  || fail "hkx skeleton missing hkaSkeleton class"

run "hkx idle" hkx 'meshes\actors\character\animations\male\mt_idle.hkx'
awk '/^--- hkx idle/{f=1;next} /^--- /{f=0} f' "$log" \
  | grep -q 'hkaSplineCompressedAnimation' \
  || fail "hkx idle missing hkaSplineCompressedAnimation class"

# M6.3 idle decode gate: shared hkaSplineCompressedAnimation decoder samples
# every stored frame over full mt_idle duration. Parser rejects unknown codec
# variants, malformed blocks, non-finite transforms, and values outside its
# defensive bound before this summary can print.
run "animation idle" animation \
  'meshes\actors\character\animations\male\mt_idle.hkx'
idle_animation="$(awk '/^--- animation idle/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$idle_animation" | grep -q '275 frames x 99 tracks, 2 blocks' \
  || fail "idle animation metadata differs from verified vanilla clip"
printf '%s\n' "$idle_animation" | grep -q 'bone mapping identity: 99 samples' \
  || fail "idle animation binding is not verified 99-track identity mapping"
printf '%s\n' "$idle_animation" | grep -q 'full duration finite + bounded' \
  || fail "idle animation did not pass full-duration transform gate"

# M6.2 hkaSkeleton gate: decode the human rig skeleton.hkx (bone names, parent
# chain, roots) + name-map it onto skeleton.nif. The rig must report 99 bones;
# the map must match 93 of 99 (6 HKX-only control/attach bones, 6 NIF-only
# nodes); every unmatched line must carry a reason tag (" -> "). Keys
# single-quoted so backslashes + spaces reach the CLI verbatim (VFS keys).
run "skeleton rig name-map" skeleton \
  'meshes\actors\character\character assets\skeleton.hkx' \
  --nif 'meshes\actors\character\character assets\skeleton.nif'
skeleton_map="$(awk '/^--- skeleton rig name-map/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$skeleton_map" | grep -q 'skeleton 0 "NPC Root \[Root\]": 99 bones' \
  || fail "skeleton rig not 99 bones"
printf '%s\n' "$skeleton_map" | grep -q '93 of 99 matched' \
  || fail "skeleton name-map not 93 of 99 matched"
unmatched="$(printf '%s\n' "$skeleton_map" | grep 'unmatched ' || true)"
[ -n "$unmatched" ] || fail "skeleton name-map reported no mismatches"
missing_reason="$(printf '%s\n' "$unmatched" | grep -vc ' -> ' || true)"
[ "$missing_reason" -eq 0 ] \
  || fail "skeleton name-map has $missing_reason mismatch lines without a reason tag"
echo "[ OK ] skeleton name-map (99-bone rig, 93/99 matched, all mismatches reason-tagged)"

# Offscreen screenshot of the first-render cell -> logs/probe-screenshot.png.
png="$log_dir/probe-screenshot.png"
run "offscreen screenshot" screenshot --out "$png"
[ -s "$png" ] || fail "screenshot wrote no PNG"
echo "[ OK ] screenshot output: $png"

# M8.1.1 screen-space UI gate: same frame with the sample overlay must draw
# UI quads + glyphs without exhausting the hard quad budget.
ui_png="$log_dir/probe-ui-overlay.png"
run "offscreen screenshot (UI sample overlay)" screenshot --out "$ui_png" --ui-sample
[ -s "$ui_png" ] || fail "UI overlay screenshot wrote no PNG"
ui_line="$(grep 'ui overlay:' "$log" | tail -1)"
printf '%s\n' "$ui_line" | grep -q '[1-9][0-9]* quads, [1-9][0-9]* glyphs' \
  || fail "UI overlay reported no quads/glyphs"
printf '%s\n' "$ui_line" | grep -q ' 0 dropped' \
  || fail "UI overlay exceeded quad budget"
echo "[ OK ] UI sample overlay: $ui_png"

# M3.6 interior gate: find one teleport door near Whiterun, follow XTEL in,
# render exact arrival pose, follow paired door back to exterior.
interior_png="$log_dir/probe-interior.png"
run "interior door round trip" interior --out "$interior_png"
[ -s "$interior_png" ] || fail "interior probe wrote no PNG"
echo "[ OK ] interior output: $interior_png"

# M5.6/M6.6 interior actor gate: visited interior must report at least one
# drawn actor and at least one live animation.
awk '/^--- interior door round trip/{f=1;next} /^--- /{f=0} f' "$log" \
  | grep -q ' actors ([1-9][0-9]* drawn' \
  || fail "interior probe reported no drawn actors"
awk '/^--- interior door round trip/{f=1;next} /^--- /{f=0} f' "$log" \
  | grep -q ', [1-9][0-9]* animated' \
  || fail "interior probe reported no animated actors"
echo "[ OK ] interior actors drawn + animated"

# Sustained fps gate (todo 2.11): 360 frames at 720p via frame stats; the
# command exits 1 when avg/p95 frame time misses the 33.3 ms (30 fps) budget.
run "sustained bench (360 frames @ 1280x720)" bench
grep 'frames @' "$log" | tail -1

# M3.2/M7.6 streaming gate: deterministic east + north crossings. Shared engine
# verifier requires three settled 5x5 grids, eviction, 35 unique builds with
# no duplicates, physical-footprint plateau, and avg/p95 under 30 fps budget.
# M5.5 adds actor-enabled gates: actor-build p95 budget + exact per-cell
# accounting (discovered = rendered + disabled + failed). M7.6 requires selected
# rainy weather plus live animation, world particles, precipitation, shadows, and grass.
run "cross-cell streaming bench (640x360)" bench --fly-path --size 640x360
grep 'unique builds' "$log" | tail -1
grep 'collision build:' "$log" | tail -1
grep 'actor build:' "$log" | tail -1
grep '^\[INFO\] actors:' "$log" | tail -1 | grep -q 'discovered' \
  || fail "fly bench reported no actor accounting"
grep 'animation update:' "$log" | tail -1
grep 'rendered actors:' "$log" | tail -1 | grep -q '[1-9][0-9]* animated' \
  || fail "fly bench reported no animated actors"
living_line="$(grep 'living environment:' "$log" | tail -1)"
printf '%s\n' "$living_line" | grep -q 'weather .*; [1-9][0-9]* animated bones' \
  || fail "fly bench reported no selected weather or animated bones"
printf '%s\n' "$living_line" | grep -q '[1-9][0-9]* live particles in [1-9][0-9]* systems' \
  || fail "fly bench reported no live world particles"
printf '%s\n' "$living_line" | grep -q '[1-9][0-9]* live rain' \
  || fail "fly bench reported no live precipitation"

# M7.1.2 sun-shadow gate: per-frame shadow-update budget line + per-cascade
# caster-culling accounting (some casters culled during the flight).
grep 'shadow update:' "$log" | tail -1
grep 'shadow culling:' "$log" | tail -1 | grep -q '[1-9][0-9]* culled' \
  || fail "fly bench reported no shadow caster culling"

# M7.5.2 grass gate: fly path must render batched grass without exhausting
# the hard per-frame instance budget.
grass_line="$(grep 'grass instancing:' "$log" | tail -1)"
printf '%s\n' "$grass_line" | grep -q '[1-9][0-9]*/[1-9][0-9]* drawn' \
  || fail "fly bench rendered no grass"
printf '%s\n' "$grass_line" | grep -q '0 budget-dropped' \
  || fail "fly bench exceeded grass instance budget"

# M5.6 acceptance: one accounting line per touched cell (35 = three settled
# 5x5 grids). The engine gate already throws on inexact accounting or a
# reason-less failure; this proves the per-cell report surfaced. Failure
# lines carry their reasons -> echo them for the acceptance record.
fly_cells="$(sed -n '/^--- cross-cell streaming bench/,$p' "$log" \
  | grep -c ') actors: ' || true)"
[ "$fly_cells" -eq 35 ] \
  || fail "fly bench reported $fly_cells per-cell actor lines, expected 35"
echo "[ OK ] per-cell actor accounting (35 cells)"
explained="$(sed -n '/^--- cross-cell streaming bench/,$p' "$log" \
  | grep ') actors: ' | grep -v ' 0 failed' || true)"
if [ -n "$explained" ]; then
  echo "[INFO] explained actor failures:"
  printf '%s\n' "$explained"
fi

# M4.5 route gate: fixed-step production physics from first-render cell to
# Chillfurrow Farm, interior floor crossing, then paired exterior return.
walk_png="$log_dir/probe-walk-path.png"
run "walk/collision route bench (640x360)" bench --walk-path --size 640x360 \
  --out "$walk_png"
[ -s "$walk_png" ] || fail "walk-path bench wrote no PNG"
grep 'active physics frames @' "$log" | tail -1
echo "[INFO] probe passed — full output in $log"
