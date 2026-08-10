#!/bin/sh
# Env-gated smoke probe: drive openskycli against the local Skyrim SE
# install (docs/tools/cli.md). Self-skips with [INFO] when no install is
# present (CI has no game data). Install is read-only external input;
# outputs go to logs/ only (AGENTS.md Legal & IP + Code scripts).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
# Same build cache and products layout the Makefile uses (Makefile DERIVED_DATA
# and PRODUCTS): the boot volume is too small to hold this project's
# DerivedData, so it lives beside the checkout.
# shellcheck source=/dev/null
. "$root/tools/xcodebuild-lib.sh"
derived_data="$OPENSKY_DERIVED_DATA"
data_root="${OPENSKY_DATA_ROOT:-/Volumes/data/steam/steamapps/common/Skyrim Special Edition}"

if [ ! -f "$data_root/Data/Skyrim.esm" ] && [ ! -f "$data_root/Skyrim.esm" ]; then
  echo "[INFO] no Skyrim SE install at $data_root — skipping probe"
  exit 0
fi

# One run, one directory (issue #347): the transcript and every capture this
# probe renders land here, and `logs/probe/latest` points at the newest run.
log_dir="$("$root/tools/run-dir.sh" probe)"
log="$log_dir/probe.log"
echo "[INFO] run directory: $log_dir"

echo "[INFO] building openskycli (log: $log)"
xcodebuild -project "$root/opensky.xcodeproj" -scheme openskycli -configuration Debug \
  -derivedDataPath "$derived_data" build >"$log" 2>&1
cli="$(xcodebuild_products_dir Debug)/openskycli"
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

expect_usage() {
  step="$1"
  expected="$2"
  shift 2
  if output="$("$cli" --data-root "$data_root" "$@" 2>&1)"; then
    {
      printf -- '--- %s\n' "$step"
      printf '%s\n' "$output"
    } >>"$log"
    fail "$step accepted an invalid option combination"
  else
    exit_status="$?"
  fi
  {
    printf -- '--- %s\n' "$step"
    printf '%s\n' "$output"
  } >>"$log"
  [ "$exit_status" -eq 2 ] || fail "$step exited $exit_status instead of 2"
  printf '%s\n' "$output" | grep -Fq -- "$expected" \
    || fail "$step did not report the expected usage error"
  printf '[ OK ] %s\n' "$step"
}

# Path-specific benchmark flags must fail during option parsing, before the CLI
# opens or renders game data.
expect_usage "walk path rejects sustained frame count" \
  "--frames is not supported with --walk-path" \
  bench --walk-path --frames 1
expect_usage "walk path rejects fly footprint cap" \
  "--footprint-cap-mb is not supported with --walk-path" \
  bench --walk-path --footprint-cap-mb 1
expect_usage "walk path rejects fly collision budget" \
  "--collision-build-budget-ms is not supported with --walk-path" \
  bench --walk-path --collision-build-budget-ms 1

# vfs ls resolves archives and finds meshes.
mesh_count="$("$cli" --data-root "$data_root" vfs ls 'meshes\*.nif' 2>>"$log" | wc -l)"
[ "$mesh_count" -gt 0 ] || fail "vfs ls found no meshes"
echo "[ OK ] vfs ls ($mesh_count mesh entries)"

# Record probe: Tamriel WRLD is FormID 0x3C (UESP "Skyrim Mod:FormIDs").
"$cli" --data-root "$data_root" record 0x0000003C 2>>"$log" | grep -q Tamriel \
  || fail "record 0x3C did not decode as Tamriel"
echo "[ OK ] record 0x0000003C (Tamriel)"

# Movement tuning resolves active GMST overrides and reports an explicit source
# for every value. Do not pin numeric values here: an active user plugin may
# intentionally override them.
run "movement GMST resolution" gmst movement
movement="$(awk '/^--- movement GMST resolution/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$movement" | grep -q '^fMoveCharWalkBase = .* units/s \[.*\]$' \
  || fail "movement probe did not report walk value and source"
printf '%s\n' "$movement" | grep -q '^fMoveCharRunBase = .* units/s \[.*\]$' \
  || fail "movement probe did not report run value and source"
printf '%s\n' "$movement" | grep -q '^stepHeight = .* units \[.*\]$' \
  || fail "movement probe did not report step value and source"

# Archery chain (issue #196): the AMMO -> PROJ walk has to reach a flyable
# record and report the flight numbers a shot inherits. Numbers are not pinned —
# an active user plugin may intentionally override them — but the shape is, and
# the census line is what the `gravity` reading rests on.
run "archery chain (iron arrow)" archery --census --ammo IronArrow
archery="$(awk '/^--- archery chain/{f=1;next} /^--- / {f=0} f' "$log")"
printf '%s\n' "$archery" | grep -q '^fVisibleNavmeshMoveDist = .* \[.*\]$' \
  || fail "archery probe did not report the visible-move distance and source"
printf '%s\n' "$archery" | grep -q '^arrow: n [0-9]*, gravity min' \
  || fail "archery probe did not census the arrow-type PROJ band"
printf '%s\n' "$archery" | grep -q '^IronArrow: damage .* speed .* gravity .* range ' \
  || fail "archery probe did not walk IronArrow to its PROJ"

# Footstep chain (issue #352): the default set's walking list must reach a real
# sound file, which is the end-to-end evidence that FSTS/FSTP/IPDS/IPCT decode
# and that the tag the behavior graph raises resolves to something playable.
run "footstep chain (DefaultFootstepSet)" footstep
footstep="$(awk '/^--- footstep chain/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$footstep" | grep -q '^set: DefaultFootstepSet ' \
  || fail "footstep probe did not resolve the default set"
printf '%s\n' "$footstep" | grep -q '^  FootLeft: .* -> .* -> sound' \
  || fail "footstep probe did not resolve FootLeft to a sound file"
printf '%s\n' "$footstep" | grep -q '^materials: [0-9]* MATT, [0-9]* reachable' \
  || fail "footstep probe did not report the MATT index"

# Surface material (issue #358): naming a real MATT must take the same tag down
# a different branch of the IPDS table, which is the end-to-end evidence that
# the material half of the chain is wired rather than always falling back.
run "footstep chain on snow" footstep --material MaterialSnow
snow="$(awk '/^--- footstep chain on snow/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$snow" | grep -q '^material: MaterialSnow$' \
  || fail "footstep probe did not resolve the snow material"
snow_step="$(printf '%s\n' "$snow" | grep -m1 '^  FootLeft: ')"
stone_step="$(printf '%s\n' "$footstep" | grep -m1 '^  FootLeft: ')"
[ -n "$snow_step" ] && [ "$snow_step" != "$stone_step" ] \
  || fail "footstep probe resolved the same sound with and without a material"

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

# M8.2.3 SWF font/text gate: every DefineFont2/3 and DefineText/2/EditText body
# decodes. Vanilla install: 97 fonts, 665 DefineEditText, 0 failed each; the
# fontconfig report resolves all 20 aliases against the fontlib movies.
grep 'swf sweep fonts:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported font decode failures"
grep 'swf sweep text:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported text decode failures"

# M8.2.4 SWF display-list gate: every movie's frame-1 display list assembles
# and flattens into draw commands, and every edit text with content resolves a
# font. Vanilla install: 53 movies, 130 frame-1 placements, 0 failed.
grep 'swf sweep display:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf sweep reported display-list decode failures"
grep 'swf sweep display text:' "$log" | tail -1 | grep -q '0 edit texts without a font' \
  || fail "swf sweep found edit texts with content but no resolvable font"

# M8.2.4 SWF render gate: every movie's frame-1 display list renders through
# the production Metal layer over an offscreen frame. Vanilla install: 53
# rendered, 0 failed (frames stay in memory — no --out, they embed game art).
run "swf render-sweep (vanilla frame-1 display lists)" swf render-sweep --size 480x320
grep 'swf render-sweep:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf render-sweep reported movies that did not render"

# M12.2.3 container + barter menu gate: both vanilla movies come up through
# ContainerMenuMovieBridge, take a published two-pane inventory, and answer
# every engine call they make. Vanilla install: 0 faults and 0 unhandled
# invokes each, and the barter movie's own vendor-gold field carries the
# merchant purse.
run "swf container-menu (containermenu.swf)" swf container-menu --mode container --down 1
grep 'swf container-menu diagnostics:' "$log" | tail -1 | grep -q ' 0 faults' \
  || fail "containermenu.swf faulted during bring-up"
run "swf container-menu (bartermenu.swf)" swf container-menu --mode barter --transfer 1
grep 'swf container-menu diagnostics:' "$log" | tail -1 | grep -q ' 0 unhandled of ' \
  || fail "bartermenu.swf made unanswered engine calls"

# M17.3 dialogue menu gate: the vanilla movie comes up through
# DialogueMenuMovieBridge, publishes every entry point the bridge drives, takes
# a published topic list and says a line. Vanilla install: 0 faults, 0 unhandled
# invokes, 0 missing entry points.
run "swf dialogue-menu (dialoguemenu.swf)" swf dialogue-menu --rows 4 --down 1 --speak
grep 'swf dialogue-menu entry points:' "$log" | tail -1 | grep -q ' 0 missing' \
  || fail "dialoguemenu.swf is missing an entry point the bridge drives"
grep 'swf dialogue-menu diagnostics:' "$log" | tail -1 | grep -q ' 0 faults' \
  || fail "dialoguemenu.swf faulted during bring-up"
grep 'swf dialogue-menu diagnostics:' "$log" | tail -1 | grep -q ' 0 unhandled of ' \
  || fail "dialoguemenu.swf made unanswered engine calls"

# M8.3.1 SWF action-inventory gate: every movie's action side (DoAction,
# DoInitAction, CLIPACTIONS) decodes with zero unexpected failures and zero
# opcodes outside the Adobe action table. Vanilla install: 53 movies, ~3,414
# action blocks, ~533,562 action records, ~56 distinct opcodes, 0 unknown.
run "swf action-sweep (vanilla AS2 inventory)" swf action-sweep
grep 'swf action-sweep:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "swf action-sweep reported movies that did not decode"
grep 'swf action-sweep unknown:' "$log" | tail -1 | grep -q '^\[INFO\] swf action-sweep unknown: 0 ' \
  || fail "swf action-sweep reported unknown AS2 opcodes"

# M9.1.2 xWMA container gate: every vanilla .xwm frames through XWMFile with
# zero failures. Vanilla install: 269 files, 269 framed, 0 unsupported,
# 0 failed, all WAVE_FORMAT_WMAUDIO2. The "decoded" column stays 0 until the
# WMA decoder lands (M9.1.1); the grep below only gates framing.
run "xwm audio sweep (vanilla music)" audio sweep
grep 'audio sweep:' "$log" | tail -1 | grep -q ' 0 failed' \
  || fail "xwm audio sweep reported framing failures"

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

# M14.1 behavior census gate: the same `hkx` command reports role, graph name,
# root generator class, and the variable/event inventories for a behavior file.
# mt_behavior.hkx is the third-person movement graph; like every vanilla player
# graph it is rooted at an hkbStateMachine.
run "hkx behavior" hkx 'meshes\actors\character\behaviors\mt_behavior.hkx'
behavior_hkx="$(awk '/^--- hkx behavior/{f=1;next} /^--- /{f=0} f' "$log")"
printf '%s\n' "$behavior_hkx" | grep -q '^role: behavior' \
  || fail "hkx behavior did not report the behavior role"
printf '%s\n' "$behavior_hkx" | grep -q 'root generator hkbStateMachine' \
  || fail "hkx behavior root generator is not an hkbStateMachine"
printf '%s\n' "$behavior_hkx" | grep -q '^variables: 67' \
  || fail "hkx behavior variable count differs from verified vanilla graph"
printf '%s\n' "$behavior_hkx" | grep -q '^events: 931' \
  || fail "hkx behavior event count differs from verified vanilla graph"
if printf '%s\n' "$behavior_hkx" | grep -q '^unresolved fields:'; then
  fail "hkx behavior reported unresolved members"
fi

# M14.2 node decode gate: the same dump now decodes every registered object via
# the class registry and walks the node tree below the root generator. The
# full-graph rule means a class with no decoder is a failure, not a tally, so
# the "objects with no decoder" line must be absent entirely. The walk reaches
# five fewer nodes than the file has objects: the root container, the behavior
# graph, its data, its string data, and its variable value set sit above the
# node tree rather than inside it.
printf '%s\n' "$behavior_hkx" | grep -q '^decoded objects: 5115' \
  || fail "hkx behavior decoded object count differs from verified vanilla graph"
if printf '%s\n' "$behavior_hkx" | grep -q '^objects with no decoder:'; then
  fail "hkx behavior reported a class with no decoder"
fi
if printf '%s\n' "$behavior_hkx" | grep -q '^objects that failed to decode:'; then
  fail "hkx behavior reported an object that failed to decode"
fi
printf '%s\n' "$behavior_hkx" \
  | grep -q '^graph nodes reached from the root generator: 5110' \
  || fail "hkx behavior node-tree walk differs from verified vanilla graph"
printf '%s\n' "$behavior_hkx" | grep -q 'hkbStateMachine "MT_RootBehavior"' \
  || fail "hkx behavior did not name the root state machine"

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

# Offscreen screenshot of the first-render cell -> probe-screenshot.png.
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

# M9.2.4 audio gate: per-frame audio-update budget line. The engine gate throws
# when avg or p95 exceeds the budget, so reaching here means it held.
grep 'audio update:' "$log" | tail -1 \
  || fail "fly bench reported no audio update budget line"

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
grep 'audio update:' "$log" | tail -1 \
  || fail "walk bench reported no audio update budget line"
echo "[INFO] probe passed — full output in $log"
