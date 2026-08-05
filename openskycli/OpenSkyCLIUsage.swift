// The `openskycli` usage text. Split out of OpenSkyCLI.swift (issue #179): the
// command list is most of that enum's body and had reached the strict-lint
// type-length cap, so a new subcommand could not document itself there.
//
// A new or changed subcommand updates this text, `docs/tools/cli.md` and probe
// coverage in the same commit.

import Foundation

extension OpenSkyCLI {
    static let usage = """
    usage: openskycli [--data-root <path>] <command> [options]

    commands:
      vfs ls [pattern]            List archive entries (fnmatch wildcards or
                                  substring); prints "path<TAB>archive"
      vfs cat <key> --out <file>  Extract one resource to a file
      record <formid-or-editorid> Dump one Skyrim.esm record (decoded + fields)
      gmst movement              Print resolved gait/step/jump values + sources
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
                                  one PNG per movie (use a logs/ path: the
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
      swf info <key>               Parse one movie; print header + tag list
      audio info <key>            Frame one .xwm file; print WAVEFORMATEX codec
                                  parameters, dpds packet table and payload
                                  stats (framing only — no decode yet)
      audio sweep                 Frame every .xwm the archives provide;
                                  report per-file summaries plus a
                                  files/framed/decoded/failed tally
      screenshot --out <file> [--worldspace <edid>] [--x <n>] [--y <n>]
             [--size WxH] [--zoom <f>] [--time-of-day <0-24>] [--neighbors]
             [--ui-sample]
                                  Save an offscreen World frame as PNG; zoom
                                  moves the eye toward the framed center;
                                  time-of-day defaults to 13:00;
                                  --neighbors adds the 8 surrounding cells,
                                  camera frames the combined bounds;
                                  --ui-sample overlays the screen-space UI
                                  sample scene + prints its draw stats
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
      help                        Show this text

    defaults: cell/screenshot/render target the first-render cell (Tamriel (6,-2)).

    options:
      --data-root <path>          Skyrim SE install (or Data/) folder. Default:
                                  OPENSKY_DATA_ROOT env var, OpenSkyDataRoot
                                  user default, then the Steam install path.
    """
}
