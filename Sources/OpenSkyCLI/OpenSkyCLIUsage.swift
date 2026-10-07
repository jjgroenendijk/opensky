// The `openskycli` usage text, split out of OpenSkyCLI.swift to stay under the
// type-length cap. A changed subcommand updates this, `docs/tools/cli.md`, and
// probe coverage in the same commit.

import Foundation

extension OpenSkyCLI {
    static let usage = """
    usage: openskycli [--data-root <path>] <command> [options]

    commands:
      vfs ls [pattern]            List archive entries (fnmatch wildcards or
                                  substring); prints "path<TAB>archive"
      vfs cat <key> --out <file>  Extract one resource to a file
      record <formid-or-editorid> Dump one Skyrim.esm record (decoded + fields)
      plugins                     Print the resolved plugin load order and the
                                  plugins.txt it came from; OPENSKY_PLUGINS_TXT
                                  overrides the search
      ess <save.ess> [--offline]  Inspect a Skyrim save read-only and run its
                                  import against the load order; --offline
                                  skips the load order
      ess list <folder>           List the .ess saves in a folder
      gmst movement              Print resolved gait/step/jump values + sources
      gmst combat                Print resolved melee reach and block settings
                                  + sources
      gmst archery               Print resolved arrow tilt-up angles and the
                                  visible-move distance + sources
      gmst detection             Print resolved detection ranges, noise
                                  weights and thresholds + sources
      gmst list --prefix <s>     Print every resolved GMST whose editor ID
                                  starts with <s>, with its value and source
      render/screenshot --detection-overlay
                                  Add the perception view cones and investigate
                                  lines for every ACHR in the built cells,
                                  against a stand-in target at the framed centre
      archery [--census] [--ammo <substring>]
                                  Walk the AMMO -> PROJ flight chain: the
                                  archery GMSTs, then one row per arrow with
                                  its PROJ speed, gravity and range and the
                                  drop each reading of `gravity` predicts.
                                  --census adds the PROJ-wide distribution
                                  that settles which reading is right
      footstep [--set <edid>] [--armature <formid-or-edid>]
               [--material <edid-or-formid>]
                                  Walk the footstep chain: per gait, every
                                  FSTP tag in the set and the IPCT + sound
                                  file it resolves to. Defaults to
                                  DefaultFootstepSet; --armature reads the
                                  set off an ARMA's SNDD; --material names
                                  the MATT surface under the foot
      cell [--worldspace <edid>] [--x <n>] [--y <n>] [--refs]
                                  Summarize an exterior cell's references
      actor [--worldspace <edid>] [--x <n>] [--y <n>] [--radius <n>]
            [--npc <formid-or-edid>]
                                  List placed actors (ACHR) around a cell;
                                  resolve each base NPC_ through its TPLT
                                  template chain, then visuals: skeleton,
                                  skin/outfit body parts with slot masking,
                                  FaceGen paths, reason-tagged skips.
                                  --npc resolves one base NPC_ directly
                                  (no ACHR needed)
      actor-values (--npc <formid-or-edid> | --race <formid-or-edid>)
                   [--player-level <n>]
                                  Derive base health/magicka/stamina for one
                                  NPC_ through its template chain, or report
                                  one RACE's starting attributes and regen
                                  rates. --player-level scales PC-level-mult
                                  actors
      collision [--worldspace <edid>] [--x <n>] [--y <n>] [--radius <n>]
                                  Sweep embedded NIF collision for every unique
                                  model used by center cell; report placed
                                  shapes/triangles for target grid
      interior --out <file> [--worldspace <edid>] [--x <n>] [--y <n>]
               [--radius <n>]    Find a nearby exterior door, enter its interior,
                                  render the arrival pose, verify the return door
      nif <key>                   Inspect a mesh: container stats, model summary
      dds <key>                   Inspect a texture: header + mip chain
      hkx <key>                   Inspect a Havok packfile: header, section table,
                                  class-name + object inventory
      hkt <key> | hkt sweep       Decode a Havok binary tagfile: classes with
                                  versions, objects, cloth classes, bones
      effects census | effects imad <edid> [--at <seconds>]
                                  Census the IMAD, IMGS, SPGD, SOPM, and REVB
                                  records, or sample one IMAD at a time
      skeleton <hkx-key> [--nif <nif-key>]
                                  Decode each hkaSkeleton (bone names, parent
                                  chain, roots); --nif name-maps the rig onto
                                  the NIF skeleton nodes, reason-tagging
                                  mismatches both directions
      animation <hkx-key>         Decode spline-compressed transform tracks;
                                  sample every frame over full clip duration
      lod [--worldspace <edid>]   Parse settings + sweep .btr/.bto/.lst/.btt
      swf sweep                   Parse every interface\\*.swf movie; report
                                  per-file header summary + known/unknown
                                  tag-code tally (ZWS counted as
                                  accounted-but-unsupported), shape/bitmap,
                                  font/text, and frame-1 display-list tallies
      swf render-sweep [--size WxH] [--out <dir>]
                                  Render every movie's frame-1 display list
                                  over an offscreen frame; report per-movie
                                  draw stats + changed pixels. --out writes
                                  one PNG per movie (use a .logs/ path: the
                                  frames embed game art)
      swf action-sweep [--movie <substring>] [--limit <n>]
                                  Decode every movie's action side (DoAction,
                                  DoInitAction, CLIPACTIONS) and print an
                                  opcode-frequency table, unknown-opcode
                                  report, structurally-resolved host/GFx API
                                  name surface (--limit caps the printed
                                  names, default 120), clip-event usage,
                                  function/structure stats, and a
                                  most-action-records movie ranking
      swf action-list --movie <substring>
                                  Print one movie's action records with names
                                  resolved; redirect the output into .logs/
      swf action-run [--movie <substring>] [--ticks <n>] [--limit <n>]
                     [--tree-depth <n>] [--dump <paths>] [--call <names>]
                                  Bring one movie up through SWFMovieRuntime and
                                  tick it; print faults, unresolved placements
                                  and import-merge diagnostics, the missing-API
                                  tally, registered classes, GameDelegate
                                  callbacks, the invoke log and the display
                                  tree. --dump prints one node's own AS2
                                  properties; --call invokes callbacks first
      swf inventory-menu [--ticks <n>] [--down <n>] [--right <n>]
                                  Drive inventorymenu.swf through its bridge
                                  with a seeded player inventory; print the
                                  rows and categories the movie built, both
                                  selections, and the bring-up diagnostics
      swf container-menu [--mode container|barter] [--side container|player]
                         [--ticks <n>] [--down <n>] [--transfer <n>]
                                  Drive containermenu.swf or bartermenu.swf
                                  through its bridge against a seeded container
                                  and player; print the movie's rows, both
                                  purses, the resolved barter pricing, the
                                  selected row's price and the diagnostics
      swf system-menu [--state <name>] [--focus <path>] [--row <n>] [--ticks <n>]
                      [--dump <paths>]
                                  Open quest_journal.swf on its System page,
                                  start one SystemPage state by its constant
                                  name, focus a page-relative list,
                                  optionally accept a list row, and print
                                  every GameDelegate call the movie made
      swf movie-probe --movie <path> [--ticks <n>] [--capture <names>]
                      [--then <steps>] [--dump <paths>]
                                  Start any movie; steps (split by ;) are
                                  call:<path>:<method>[:<JSON args>],
                                  focus:<path>, or key:<code>; print host
                                  calls and nodes
      swf dialogue-menu [--ticks <n>] [--down <n>] [--rows <n>] [--speak]
                        [--text] [--probe-rows <n>]
                                  Drive dialoguemenu.swf through its bridge
                                  against real DIAL/INFO records; print the
                                  movie's state constants, the entry points it
                                  publishes, the rows it built, both
                                  selections, the speaker and subtitle fields
                                  and the diagnostics. --text resolves every
                                  field out of all three string tables;
                                  --probe-rows measures the row field names
      swf info <key>               Parse one movie; print header + tag list
      audio info <key>            Frame one .xwm or .fuz file; print the FUZE
                                  header when there is one, then WAVEFORMATEX
                                  codec parameters, the dpds packet table and
                                  payload stats (framing only — no decode)
      audio sweep                 Frame every .xwm the archives provide;
                                  report per-file summaries plus a
                                  files/framed/decoded/failed tally
      audio voice-sweep [--limit <n>] [--names-only]
                                  Re-derive every voice file name from the
                                  DIAL/INFO/QUST records and measure it against
                                  the archive listing, then frame every .fuz
                                  through FUZFile + XWMFile. --limit bounds the
                                  framing walk (the report states how many
                                  entries it skipped); --names-only stops after
                                  the naming check
      audio aac-check [--per-category <n>] [--out <file>]
                                  Encode a fixed sample of each cached sound
                                  category as AAC and measure its band
                                  spectral distortion against the original;
                                  print the AAC or ALAC verdict per category.
                                  --out writes one row per sound
      screenshot --out <file> [--worldspace <edid>] [--x <n>] [--y <n>]
             [--size WxH] [--zoom <f>] [--time-of-day <0-24>] [--neighbors]
             [--ui-sample] [--image-space-off] [--imgs <edid>]
             [--imad <edid> [--imad-at <s>]] [--membrane <efsh>]
             [--weather <edid>] [--frames <n>]
                                  Save an offscreen World frame as PNG; zoom
                                  moves the eye toward the framed center;
                                  time-of-day defaults to 13:00;
                                  --neighbors adds the 8 surrounding cells,
                                  camera frames the combined bounds;
                                  --ui-sample overlays the screen-space UI
                                  sample scene + prints its draw stats;
                                  the effect flags force image space,
                                  a modifier, a membrane on the first
                                  actor, or a weather; --frames warms up
      render <screenshot options> Compatibility alias for screenshot
      bench [--worldspace <edid>] [--x <n>] [--y <n>] [--size WxH]
            [--frames <n>] [--budget-ms <f>]
                                  Sustained offscreen render; report frame
                                  stats, fail when avg/p95 miss the budget
      bench --fly-path [--worldspace <edid>] [--x <n>] [--y <n>]
            [--size WxH] [--budget-ms <f>] [--max-frames <n>]
            [--footprint-cap-mb <f>]
            [--collision-build-budget-ms <f>]
            [--actor-build-budget-ms <f>]
            [--animation-budget-ms <f>] [--shadow-budget-ms <f>]
            [--audio-budget-ms <f>] [--script-budget-ms <f>]
                                  Script east + north cell crossings; require
                                  settlement, unload, one build/cell, bounded
                                  physical footprint, collision-build p95,
                                  actor-build p95, exact per-cell actor/animation
                                  accounting, animation + shadow + audio +
                                  script + frame budgets; require selected rain, live world
                                  particles, precipitation, shadows, and grass;
                                  report peaks
      bench --walk-path [--size WxH] [--budget-ms <f>]
            [--max-frames <n>] [--audio-budget-ms <f>] [--out <file>]
                                  Fixed-step M4 route: terrain + farm stairs,
                                  paired interior crossing, exterior return;
                                  fail route/collision/stream/physics/audio gates
      launch-bench                Time each stage of the world data load the
                                  app runs before its game window opens
      asset-cache build|check|clear|status [--preset best|balanced|highest]
            [--folder <dir>] [--limit-gib <n>] [--kinds <list>] [--width <n>]
            [--paths <file>]
                                  Build, check, clear, or show the asset
                                  cache; settings come from the app unless an
                                  option overrides them; --paths limits a
                                  build or check to the listed files
      asset-cache extract --paths <file> --out <dir>
                                  Write loose copies of the listed files, the
                                  baseline the cache is measured against
      asset-cache io-bench --paths <file>
                                  Load the listed cached textures as one batch:
                                  archive, cache on the CPU, and Metal fast
                                  resource loading raw and LZ4, cold and warm
      asset-cache measure [--per-kind <n>]
                                  Per asset kind, load a sample from the
                                  archives and from the cache, cold and warm
      asset-cache compare <reference.png> <candidate.png>
                                  PSNR and largest channel error of two
                                  captures of the same view
      benchmark [--out <file>] [--frame <png>] [--asset-cache] [--evict]
                [--fast-load] [--fast-mesh-load] [--preset best|balanced|highest]
                [--folder <dir>] [--loose <dir>] [--record-paths <file>] [--size WxH]
                [--launch] [--launch-seconds <s>] [--route] [--cold-pipelines]
                [--cpu-culling] [--render-scale <percent>]
                [--upscaler temporal|spatial] [--frame-interpolation]
                [--mesh-shader-grass]
                                  Shared benchmark: cold + warm load of fixed
                                  cells split into asset phases, then frame
                                  time on a fixed view; --out writes stable
                                  JSON, --frame a PNG of the measured view;
                                  --asset-cache loads through the cache,
                                  --evict drops the files from the page cache,
                                  --fast-load reads cached textures with
                                  Metal fast resource loading,
                                  --fast-mesh-load reads cached meshes so,
                                  --loose reads extracted copies first,
                                  --record-paths lists the assets it read,
                                  --size sets the frame (default 2560x1600),
                                  --launch times the process start and its
                                  first 60 s, --route walks the shared
                                  route with live streaming,
                                  --cold-pipelines deletes the saved
                                  pipeline archive first, --cpu-culling
                                  culls static groups on the CPU,
                                  --render-scale renders at 50 to 100
                                  percent and upscales with MetalFX,
                                  --upscaler picks the MetalFX scaler,
                                  --frame-interpolation also builds a
                                  MetalFX frame between real frames,
                                  --mesh-shader-grass draws grass with
                                  object and mesh shaders
      game <command> [--text] [--socket <path>] [--reply-timeout <s>]
           [--record <file>]
                                  Drive the running app over its agent control
                                  socket; prints one JSON object per call.
                                  Commands: launch [--mode play|developer] [--title]
                                  [--app <path>] [--wait <s>], attach, status,
                                  quit, screenshot [--out <png>] [--offscreen]
                                  [--size WxH] [--world-only], input
                                  press|release|hold <action> [--frames <n>|
                                  --seconds <s>],
                                  input look --dx <deg> --dy <deg>, input
                                  select <label>, time pause|resume|step [n]
                                  |scale <x>, state player|target|actors|menu|
                                  quest <id>|av <name>|global <id>|time|frame,
                                  debug teleport|time|weather|av|item|quest|
                                  kill|resurrect|overlay, events [--follow]
                                  [--filter <kinds>] [--until <kind>]
                                  [--timeout <s>], run <script.jsonl>.
                                  See docs/tools/agent-control.md
      help                        Show this text

    defaults: cell/screenshot/render target the first-render cell (Tamriel (6,-2)).

    options:
      --data-root <path>          Skyrim SE install (or Data/) folder. Default:
                                  OPENSKY_DATA_ROOT env var, OpenSkyDataRoot
                                  user default, then the Steam install path.
    """
}
