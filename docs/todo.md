---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-20T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-20. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## How to continue (agent handoff)

Fresh session picks up here:

1. Read AGENTS.md (the contract; lists the skills), then this file, then the newest
   2-3 entries of `docs/log.md`.
2. `make bootstrap` once per checkout. Live branch/PR state: `gh pr list` + `git log`
   — never trust a snapshot written into a doc.
3. Pick topmost unchecked item below, one branch per item. Workflows live in skills:
   `commit` (branch/commit/PR/merge), `format-parser` (format work), `probe`
   (real-data checks + render verification), `docs-wiki` (doc upkeep).
4. Game data root (read-only, never copied into repo/build):
   `/Volumes/data/steam/steamapps/common/Skyrim Special Edition/`.

Machine quirks: repo on case-insensitive external APFS volume (case-only rename needs
`git mv`; AppleDouble `._*` files ignored). Xcode 26 ships without Metal Toolchain
(bootstrap handles the download). CI is suspended (Actions quota) — git hooks are the
only gate; `ci.yml` is manual-dispatch and self-skips below Xcode 26.

## Milestones at a glance

Each milestone = one goal, one measurable acceptance gate (its last numbered item). Done
milestone leaves this file; history lives in `docs/log.md` + git.

* M1 — data foundation. Done 2026-07-10 (PRs #1-#8): BSA VFS, ESM/plugin record decoders.
* M2 — static world geometry. Done 2026-07-18 (PRs #9-#21): textured
  `WhiterunExterior06` on screen, free-fly camera, bench-gated fps (avg 0.39 ms/frame @
  720p on M1, Debug), `openskycli` + main-app asset browser dev tools.
* M3 — world streaming + environment. Done 2026-07-19 (PRs #22-#35): streamed 5x5
  exterior grid, terrain, textured distant LOD incl. 32-bit terrain/object diffuse atlases,
  sky/water, lit interiors + door round trips.
* M4 — walkable world. Done 2026-07-19: streamed terrain/static collision, fixed-step
  capsule response, walk-mode door round trip + >30 fps route gate.
* M5 — actors on screen. Done 2026-07-20 (PRs #52-#59): bind-pose clothed actors stream
  with cells in Whiterun exterior + interiors, reason-tagged exact accounting, actor-enabled
  fly bench within build/footprint/frame budgets.
* M6 — actors animate (active): skeleton-driven idle playback on streamed actors.
  Gate: 6.6.
* M7 — Papyrus scripting, quest-capable (planned 2026-07-20): M7.1 VM core, M7.2 scripts
  in world, M7.3 quest engine. Gates: 7.1.4 / 7.2.4 / 7.3.4.
* M8 — audio incl. voice + lip sync (planned 2026-07-20): M8.1 decode + playback
  (ffmpeg LGPL), M8.2 game wiring, M8.3 voice + lips. Gates: 8.1.3 / 8.2.3 / 8.3.3.
* M9 — game UI, native-first hybrid (planned 2026-07-20): M9.1 HUD, M9.2 menus, M9.3
  vanilla fonts via SWF extraction. Gates: 9.1.3 / 9.2.3 / 9.3.2.
* M10+ — toward playable (direction, decided 2026-07-20): gameplay-first order,
  behavior-graph locomotion, native saves + read-only .ess import. Numbered re-scope
  at the M9 gate.

## Milestone 6 — actors animate (idle playback)

Goal: streamed actors leave bind pose — race idle animation plays on placed actors. No
AI/behavior graphs (no `behaviors/*.hkx` evaluation); direct clip playback only. One
branch/PR per numbered item; format items follow `format-parser` discipline.

Format caveat: Havok HKX has no official public spec. Container layout verified by
probe (6.1, [hkx-container](/formats/hkx-container.md)): hk_2010.2.0-r1, fileVersion 8,
64-bit LE. Object internals (hkaSkeleton/hkaAnimation members) still unverified —
leads: hkxparse/HKX2Library open parsers, ZeldaMods Havok wiki; confirm by probe at
impl, flag deviations.

* [ ] 6.3 Idle clip decode: hkaAnimation track data for one idle clip
      (spline-compressed animation expected — probe + document actual class), output
      per-bone local-transform samples. Gate: real idle clip decodes to bounded,
      NaN-free transforms over full duration; synthetic decode tests.
* [ ] 6.4 Pose sampling + palette update: sample clip at frame time -> compose world
      bone matrices -> refresh skinning palette each frame, replacing the static bind
      palette. Gate: offscreen frames at two clip times differ for an animated actor,
      identical for a static prop; palette math unit-tested.
* [ ] 6.5 Streamed playback lifecycle: resident-cell actors play their race idle,
      clip state builds/evicts with the cell; actor accounting stays exact +
      reason-tagged. Gate: actor-enabled fly bench passes with animation on, explicit
      added per-frame animation budget.
* [ ] 6.6 Milestone acceptance: Whiterun exterior + one interior animate without crash
      across the streamed grid; frame-delta evidence + screenshot under `docs/img/`
      linked from docs; `docs/log.md` + this file updated; M7 plan below reviewed
      against M6 learnings.

## Milestone 7 — Papyrus scripting (quest-capable; starts after M6)

Goal: vanilla Papyrus scripts drive world + quest state. Big -> three sub-milestones,
each with own acceptance gate (last item). One branch/PR per numbered item; format
items follow `format-parser` discipline. Specs: UESP "Compiled script file" (PEX
layout), Creation Kit wiki Papyrus reference (VM semantics), xEdit VMAD/QUST defs.
VM runtime semantics only partly documented -> confirm by observed behavior, flag
deviations.

### M7.1 — VM core (headless)

* [ ] 7.1.1 PEX container decode: header, string table, objects/states/functions,
      instruction stream. Gate: vanilla `.pex` sweep decodes clean; synthetic
      in-code fixtures cover every opcode encoding.
* [ ] 7.1.2 Interpreter: value model (bool/int/float/string/object/array), call
      frames, opcode execution, state switching. Fixtures = hand-assembled synthetic
      PEX (no compiler dep). Gate: per-opcode unit suite green.
* [ ] 7.1.3 VMAD decode + script binding: ESM VMAD subrecord (attached scripts,
      typed properties, fragment payloads), property -> form resolution. Gate:
      vanilla plugin VMAD sweep decodes; sampled script properties resolve.
* [ ] 7.1.4 Native dispatch + acceptance: native-function table, latent calls
      (`Utility.Wait`) via scheduler, unimplemented natives -> logged no-op + tally.
      Gate: synthetic script calling natives runs deterministically under test;
      coverage tally of natives referenced by vanilla scripts documented; docs
      (`formats/pex.md`, `formats/vmad.md`) + log updated.

### M7.2 — scripts run in world

* [ ] 7.2.1 VM in engine loop: per-frame scheduler budget, script-instance lifecycle
      tied to cell streaming, OnInit/OnLoad/OnCellAttach dispatch.
* [ ] 7.2.2 Activate input + OnActivate: use-key raycast target from walk mode,
      activator scripts fire; core ObjectReference natives (Enable/Disable/
      GetPosition/Translate minimal set).
* [ ] 7.2.3 Triggers + timers: OnTriggerEnter/Leave volumes, RegisterForUpdate /
      RegisterForSingleUpdate.
* [ ] 7.2.4 Acceptance: real Whiterun activator (lever/button/pull chain) visibly
      runs its vanilla script in-app; no-crash sweep over scripts attached across
      the streamed grid; per-frame VM budget in bench; docs updated.

### M7.3 — quest engine

* [ ] 7.3.1 QUST record decode: stages, log entries, objectives, alias definitions
      (xEdit defs); DIAL/INFO decoded only as far as quests need.
* [ ] 7.3.2 Quest runtime: start/stop, SetStage/GetStage/GetStageDone, stage
      fragments, objective state; journal state dumpable via dev tool.
* [ ] 7.3.3 Alias resolution: reference/location aliases, fill types used by the
      target quest; forced refs first, conditions as needed.
* [ ] 7.3.4 Acceptance: one simple vanilla quest progresses end-to-end through its
      real scripts (stage/objective evidence via journal dump); docs updated; M8
      plan reviewed.

## Milestone 8 — audio

Goal: Whiterun sounds alive — SFX, music, voice, lip sync. Decode route decided
2026-07-20: ffmpeg (LGPL) wrapped behind a Swift interface, dynamically linked;
license + justification documented per AGENTS.md dependency rule (no
redistribution-incompatible linkage). Specs: RIFF XWMA chunk docs, .fuz community
docs (header + lip size + xwm payload), UESP SNDR/SOUN/MUSC/MUST/INFO records,
NifTools TRI docs, .lip community notes (thin — probe + document uncertainty).

### M8.1 — decode + playback foundation

* [ ] 8.1.1 ffmpeg dependency: SwiftPM/C wrapper target, dynamic link, xwm (WMA2)
      payload -> PCM. Decision doc (`decisions/ffmpeg-audio.md`): license, scope
      (decode only), alternatives rejected. Gate: real + synthetic xwm decode to
      sane duration/format.
* [ ] 8.1.2 .fuz + .xwm containers: own parsers for framing (format-parser
      discipline), payload decode via 8.1.1. Gate: vanilla .fuz/.xwm sweep splits +
      decodes clean; synthetic fixtures for malformed input.
* [ ] 8.1.3 Playback engine + acceptance: AVAudioEngine graph, 3D positional sources
      bound to world transforms, streaming buffers, category volumes. Gate:
      deterministic buffer-tap tests + audible positional playback of a real SFX
      (manual confirm); docs (`engine/audio.md`) + log updated.

### M8.2 — game audio wiring

* [ ] 8.2.1 Sound records: SNDR/SOUN/SDSC decode, descriptor -> file resolution,
      attenuation/looping params.
* [ ] 8.2.2 World SFX: door open/close + activator sounds from M7.2 events, per-cell
      ambience loops where resolution is cheap.
* [ ] 8.2.3 Music + acceptance: MUSC/MUST playlists, exploration/town/interior
      selection with crossfade. Gate: Whiterun walk has door SFX, ambience, music
      transitioning interior/exterior; frame budget kept; docs updated.

### M8.3 — voice + lip sync

* [ ] 8.3.1 Voice playback: INFO -> voice path convention
      (`sound/voice/<plugin>/<voicetype>/`), .fuz line plays positionally from an
      actor via dev-tool trigger (dialogue UI not required).
* [ ] 8.3.2 TRI face morphs: TRI container decode (NifTools docs), morph targets
      applied in the skinned face path (builds on M6 palette work). Gate: morph
      math unit-tested; offscreen frame delta on morph apply.
* [ ] 8.3.3 .lip decode + acceptance: phoneme track -> morph weights over playback
      time. Gate: voice line plays with moving lips — offscreen mouth-region frame
      deltas + screenshot under `docs/img/`; docs updated; M9 plan reviewed.

## Milestone 9 — game UI (native-first hybrid)

Decision 2026-07-20: vanilla UI is Scaleform SWF (Flash); full Flash runtime out of
scope. Native Metal/AppKit UI now; cheap SWF asset extraction (fonts) as M9.3; full
Scaleform playback not planned. Record as `decisions/ui-approach.md` at M9.1.1.

### M9.1 — HUD

* [ ] 9.1.1 Screen-space UI layer: 2D pass over the 3D frame, layout + text
      primitives, resolution/scale handling. System font initially. Decision doc
      lands here.
* [ ] 9.1.2 Strings: `Interface/Translations/*_english.txt` parser (UTF-16LE
      key/value), activation prompt text from records ("Open <door name>").
* [ ] 9.1.3 HUD elements + acceptance: crosshair, health/magicka/stamina bars
      (static values pre-combat), compass with markers, activate prompt wired to
      M7.2 targeting. Gate: walk-mode screenshot with live prompt text under
      `docs/img/`; docs updated.

### M9.2 — menus

* [ ] 9.2.1 Menu mode: input capture switch, world-sim pause, menu stack push/pop.
* [ ] 9.2.2 System menu: resume/settings/quit; data root + audio volumes surfaced.
* [ ] 9.2.3 Journal + acceptance: quest list + objectives from M7.3 state. Gate:
      journal shows real quest title/objective text from the played quest;
      screenshot; docs updated.

### M9.3 — vanilla fonts (SWF extraction)

* [ ] 9.3.1 SWF font parse: DefineFont2/3 glyph extraction from `fonts_en.swf`
      (Adobe SWF spec is public), `fontconfig.txt` mapping. Extraction only — no
      movie playback.
* [ ] 9.3.2 Acceptance: HUD + journal render with vanilla glyphs, system-font
      fallback kept; docs updated; next milestone scoped.

## Milestone 10+ — toward playable (direction only)

Gap analysis + decisions 2026-07-20; re-scope into numbered milestones with gates at
the M9 gate (9.3.2). Full decision docs land with first impl items.

Decisions made:

* Locomotion: reimplement Havok Behavior graphs (hkbBehaviorGraph evaluation of
  vanilla `behaviors/*.hkx`) over a native animation state machine -> exact vanilla
  movement feel + animation-mod compat. Massive RE effort, thin public docs
  (hkxparse/HKX2Library lineage, ZeldaMods Havok wiki); expect multiple
  sub-milestones, probe-driven like M6.
* Saves: OpenSky-native versioned save format (documented in `docs/`) as primary;
  later read-only `.ess` import for migration (UESP documents the save layout).
  Never `.ess` write — runtime state model stays ours.
* Order: gameplay-first — visible playability before the persistence core. Accepted
  cost: save/load change-tracking retrofit across systems built before it.

Candidate order (each line roughly one milestone; shared-runtime items scheduled
just-in-time before their first consumer):

* Inventory + items: pickup, containers, equipping on the actor model, weight,
  gold, barter.
* Locomotion: behavior-graph playback (walk/run/jump/sneak/swim), player movement
  parity over M4 walk mode, first-person camera + arms.
* Combat: actor values (health/magicka/stamina + regen), melee/archery hit
  detection, damage, blocking, death.
* Shared runtime (before AI/dialogue): CTDA condition evaluator (dialogue, perks,
  packages, leveled lists all consume it), game clock/calendar, GLOB globals.
* AI: NAVM navmesh decode, pathfinding, packages/schedules, detection/stealth,
  combat AI.
* Dialogue + scenes: DIAL/INFO topic trees, dialogue UI/camera, voice via M8.3.
* Save/load: native format + change tracking engine-wide; `.ess` import after.
* Magic (MGEF/SPEL/ENCH), perks/leveling, crime/factions/services, locks/traps.
* World/render track (parallel-friendly): shadows, data-driven weather (WTHR/CLMT),
  grass (GRAS) + flora, particles/decals, ragdolls + projectiles.
* Meta: main menu/new-game/chargen flow, settings persistence, key rebinding,
  map UI (world + local).

## Tooling / meta / open questions

Tracked as GitHub issues (`gh issue list`), not here: CI re-enable when Actions quota
returns (#70), commit-msg body-section enforcement (#71), engine-wide string decode
strategy (#72), plugins.txt load order (#73). Metal formatter/linter decided 2026-07-20:
[Metal shader tooling](/decisions/metal-tooling.md).
