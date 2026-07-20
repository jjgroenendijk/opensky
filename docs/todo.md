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
* M7 — world/render fidelity (planned 2026-07-20, pulled ahead by user priority):
  M7.1 sun shadows, M7.2 data-driven weather, M7.3 grass, M7.4 particles,
  M7.5 dynamic physics. Gates: 7.1.2 / 7.2.3 / 7.3.2 / 7.4.2 / 7.5.3.
* M8 — Papyrus scripting, quest-capable (planned 2026-07-20): M8.1 VM core, M8.2 scripts
  in world, M8.3 quest engine. Gates: 8.1.4 / 8.2.4 / 8.3.4.
* M9 — audio incl. voice + lip sync (planned 2026-07-20): M9.1 decode + playback
  (ffmpeg LGPL), M9.2 game wiring, M9.3 voice + lips. Gates: 9.1.3 / 9.2.3 / 9.3.3.
* M10 — game UI, native-first hybrid (planned 2026-07-20): M10.1 HUD, M10.2 menus, M10.3
  vanilla fonts via SWF extraction. Gates: 10.1.3 / 10.2.3 / 10.3.2.
* M11+ — toward playable (direction, decided 2026-07-20): gameplay-first order,
  behavior-graph locomotion, native saves + read-only .ess import. Numbered re-scope
  at the M10 gate.

## Milestone 6 — actors animate (idle playback)

Goal: streamed actors leave bind pose — race idle animation plays on placed actors. No
AI/behavior graphs (no `behaviors/*.hkx` evaluation); direct clip playback only. One
branch/PR per numbered item; format items follow `format-parser` discipline.

Format caveat: Havok HKX has no official public spec. Container layout verified by
probe (6.1, [hkx-container](/formats/hkx-container.md)): hk_2010.2.0-r1, fileVersion 8,
64-bit LE. Object internals (hkaSkeleton/hkaAnimation members) still unverified —
leads: hkxparse/HKX2Library open parsers, ZeldaMods Havok wiki; confirm by probe at
impl, flag deviations.

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

## Milestone 7 — world/render fidelity (starts after M6)

Goal: world looks alive — shadows, data-driven weather, grass, particles, dynamic
physics debris. Pulled ahead of scripting/audio/UI + gameplay (user priority
2026-07-20); M6 idle playback finishes first. Five sub-milestones, each with own
gate. Specs: UESP + xEdit defs (WTHR/CLMT/REGN/GRAS), NifTools nif.xml (particle +
effect-shader blocks, bhk constraints). Format items follow `format-parser`
discipline; render items verified offscreen per `probe` skill.

### M7.1 — sun shadows

Biggest visual-fidelity gap; renderer currently has none.

* [ ] 7.1.1 Cascaded shadow maps: depth-only pass over static + terrain + skinned
      actors, cascade split over view frustum, PCF filtering in the mesh/terrain
      fragment paths. Gate: offscreen A/B (shadows on/off) differs where expected;
      cascade-selection math unit-tested.
* [ ] 7.1.2 Streaming + budget + acceptance: per-cascade caster culling limited to
      resident cells, explicit per-frame shadow budget in the fly bench, quality
      setting (off/low/high). Gate: Whiterun fly bench within budget; shadowed
      screenshots under `docs/img/`; docs (`rendering/shadows.md`) + log updated.
      Interior point-light shadows deliberately out of scope — noted for later.

### M7.2 — data-driven weather

Replaces the procedural-only sky palette from M3.

* [ ] 7.2.1 Weather records: WTHR (colors per time-of-day layer, fog distances,
      wind, precipitation type/intensity), CLMT (timing, weather chances), REGN
      weather lists. Gate: vanilla sweep decodes; synthetic fixtures.
* [ ] 7.2.2 Weather runtime: region/climate weather selection, timed transitions
      blending sky palette + fog + directional ambient, hooked to the existing
      time-of-day input. Gate: forced-weather dev command shows distinct clear/
      cloudy/foggy looks offscreen.
* [ ] 7.2.3 Precipitation + acceptance: rain/snow as camera-following particle
      volume, simple roof occlusion (upward ray), storm sky darkening. Gate:
      rain storm plays + transitions back to clear in-app; screenshots; docs
      (`engine/weather.md`) + log updated.

### M7.3 — grass + flora

* [ ] 7.3.1 GRAS records + placement: procedural distribution driven by LAND
      texture layers (density, slope/height limits, position/color variance),
      deterministic per-cell seeding. Placement algorithm not fully documented ->
      probe against observed in-game density, document deviations.
* [ ] 7.3.2 Instanced rendering + acceptance: batched instancing, wind sway,
      distance fade, per-frame budget; streaming lifetime with cells. Gate:
      Whiterun tundra grass within fly-bench budget; screenshot; docs
      (`engine/grass.md`) + log updated.

### M7.4 — particles + effect shaders

* [ ] 7.4.1 NIF particle + effect blocks: NiParticleSystem emitters/modifiers,
      BSEffectShaderProperty (additive/soft alpha), decode into engine types
      (nif.xml). Gate: vanilla sweep over Whiterun-referenced NIFs decodes; synthetic
      fixtures.
* [ ] 7.4.2 Playback + acceptance: CPU-simulated emitters, billboarded particle
      draw path, effect-shader blend states. Gate: torch flames + brazier smoke
      animate in Whiterun offscreen frames (frame-delta evidence); screenshot; docs
      (`rendering/particles.md`) + log updated.

### M7.5 — dynamic physics (ragdolls + projectiles)

Extends the static collision world (M4) with motion; combat consumes this later.

* [ ] 7.5.1 Dynamic rigid bodies: integrate non-fixed bhkRigidBody motion
      (gravity, impulses, sleep), broadphase updates, pushable clutter in walk
      mode. Gate: dropped/pushed clutter settles plausibly, no NaN/tunneling in
      stress test.
* [ ] 7.5.2 Ragdoll: bhkConstraint chain decode (ragdoll/hinge/limited-hinge),
      constraint solve on the actor skeleton, blend from animated pose (dev-tool
      trigger — no death system yet). Gate: triggered ragdoll collapses without
      explosion/NaN across repeated runs; skeleton stays bounded.
* [ ] 7.5.3 Projectiles + acceptance: PROJ record decode, arrow flight (gravity +
      drag), impact vs collision world, stick-on-hit (dev-tool spawn — no bow
      gameplay yet). Gate: spawned arrows land where aimed within tolerance,
      ragdoll + clutter + projectiles together hold frame budget in bench;
      screenshots; docs (`engine/dynamic-physics.md`) + log updated; M8 plan
      reviewed.

## Milestone 8 — Papyrus scripting (quest-capable; starts after M7)

Goal: vanilla Papyrus scripts drive world + quest state. Big -> three sub-milestones,
each with own acceptance gate (last item). One branch/PR per numbered item; format
items follow `format-parser` discipline. Specs: UESP "Compiled script file" (PEX
layout), Creation Kit wiki Papyrus reference (VM semantics), xEdit VMAD/QUST defs.
VM runtime semantics only partly documented -> confirm by observed behavior, flag
deviations.

### M8.1 — VM core (headless)

* [ ] 8.1.1 PEX container decode: header, string table, objects/states/functions,
      instruction stream. Gate: vanilla `.pex` sweep decodes clean; synthetic
      in-code fixtures cover every opcode encoding.
* [ ] 8.1.2 Interpreter: value model (bool/int/float/string/object/array), call
      frames, opcode execution, state switching. Fixtures = hand-assembled synthetic
      PEX (no compiler dep). Gate: per-opcode unit suite green.
* [ ] 8.1.3 VMAD decode + script binding: ESM VMAD subrecord (attached scripts,
      typed properties, fragment payloads), property -> form resolution. Gate:
      vanilla plugin VMAD sweep decodes; sampled script properties resolve.
* [ ] 8.1.4 Native dispatch + acceptance: native-function table, latent calls
      (`Utility.Wait`) via scheduler, unimplemented natives -> logged no-op + tally.
      Gate: synthetic script calling natives runs deterministically under test;
      coverage tally of natives referenced by vanilla scripts documented; docs
      (`formats/pex.md`, `formats/vmad.md`) + log updated.

### M8.2 — scripts run in world

* [ ] 8.2.1 VM in engine loop: per-frame scheduler budget, script-instance lifecycle
      tied to cell streaming, OnInit/OnLoad/OnCellAttach dispatch.
* [ ] 8.2.2 Activate input + OnActivate: use-key raycast target from walk mode,
      activator scripts fire; core ObjectReference natives (Enable/Disable/
      GetPosition/Translate minimal set).
* [ ] 8.2.3 Triggers + timers: OnTriggerEnter/Leave volumes, RegisterForUpdate /
      RegisterForSingleUpdate.
* [ ] 8.2.4 Acceptance: real Whiterun activator (lever/button/pull chain) visibly
      runs its vanilla script in-app; no-crash sweep over scripts attached across
      the streamed grid; per-frame VM budget in bench; docs updated.

### M8.3 — quest engine

* [ ] 8.3.1 QUST record decode: stages, log entries, objectives, alias definitions
      (xEdit defs); DIAL/INFO decoded only as far as quests need.
* [ ] 8.3.2 Quest runtime: start/stop, SetStage/GetStage/GetStageDone, stage
      fragments, objective state; journal state dumpable via dev tool.
* [ ] 8.3.3 Alias resolution: reference/location aliases, fill types used by the
      target quest; forced refs first, conditions as needed.
* [ ] 8.3.4 Acceptance: one simple vanilla quest progresses end-to-end through its
      real scripts (stage/objective evidence via journal dump); docs updated; M9
      plan reviewed.

## Milestone 9 — audio

Goal: Whiterun sounds alive — SFX, music, voice, lip sync. Decode route decided
2026-07-20: ffmpeg (LGPL) wrapped behind a Swift interface, dynamically linked;
license + justification documented per AGENTS.md dependency rule (no
redistribution-incompatible linkage). Specs: RIFF XWMA chunk docs, .fuz community
docs (header + lip size + xwm payload), UESP SNDR/SOUN/MUSC/MUST/INFO records,
NifTools TRI docs, .lip community notes (thin — probe + document uncertainty).

### M9.1 — decode + playback foundation

* [ ] 9.1.1 ffmpeg dependency: SwiftPM/C wrapper target, dynamic link, xwm (WMA2)
      payload -> PCM. Decision doc (`decisions/ffmpeg-audio.md`): license, scope
      (decode only), alternatives rejected. Gate: real + synthetic xwm decode to
      sane duration/format.
* [ ] 9.1.2 .fuz + .xwm containers: own parsers for framing (format-parser
      discipline), payload decode via 9.1.1. Gate: vanilla .fuz/.xwm sweep splits +
      decodes clean; synthetic fixtures for malformed input.
* [ ] 9.1.3 Playback engine + acceptance: AVAudioEngine graph, 3D positional sources
      bound to world transforms, streaming buffers, category volumes. Gate:
      deterministic buffer-tap tests + audible positional playback of a real SFX
      (manual confirm); docs (`engine/audio.md`) + log updated.

### M9.2 — game audio wiring

* [ ] 9.2.1 Sound records: SNDR/SOUN/SDSC decode, descriptor -> file resolution,
      attenuation/looping params.
* [ ] 9.2.2 World SFX: door open/close + activator sounds from M8.2 events, per-cell
      ambience loops where resolution is cheap.
* [ ] 9.2.3 Music + acceptance: MUSC/MUST playlists, exploration/town/interior
      selection with crossfade. Gate: Whiterun walk has door SFX, ambience, music
      transitioning interior/exterior; frame budget kept; docs updated.

### M9.3 — voice + lip sync

* [ ] 9.3.1 Voice playback: INFO -> voice path convention
      (`sound/voice/<plugin>/<voicetype>/`), .fuz line plays positionally from an
      actor via dev-tool trigger (dialogue UI not required).
* [ ] 9.3.2 TRI face morphs: TRI container decode (NifTools docs), morph targets
      applied in the skinned face path (builds on M6 palette work). Gate: morph
      math unit-tested; offscreen frame delta on morph apply.
* [ ] 9.3.3 .lip decode + acceptance: phoneme track -> morph weights over playback
      time. Gate: voice line plays with moving lips — offscreen mouth-region frame
      deltas + screenshot under `docs/img/`; docs updated; M10 plan reviewed.

## Milestone 10 — game UI (native-first hybrid)

Decision 2026-07-20: vanilla UI is Scaleform SWF (Flash); full Flash runtime out of
scope. Native Metal/AppKit UI now; cheap SWF asset extraction (fonts) as M10.3; full
Scaleform playback not planned. Record as `decisions/ui-approach.md` at M10.1.1.

### M10.1 — HUD

* [ ] 10.1.1 Screen-space UI layer: 2D pass over the 3D frame, layout + text
      primitives, resolution/scale handling. System font initially. Decision doc
      lands here.
* [ ] 10.1.2 Strings: `Interface/Translations/*_english.txt` parser (UTF-16LE
      key/value), activation prompt text from records ("Open <door name>").
* [ ] 10.1.3 HUD elements + acceptance: crosshair, health/magicka/stamina bars
      (static values pre-combat), compass with markers, activate prompt wired to
      M8.2 targeting. Gate: walk-mode screenshot with live prompt text under
      `docs/img/`; docs updated.

### M10.2 — menus

* [ ] 10.2.1 Menu mode: input capture switch, world-sim pause, menu stack push/pop.
* [ ] 10.2.2 System menu: resume/settings/quit; data root + audio volumes surfaced.
* [ ] 10.2.3 Journal + acceptance: quest list + objectives from M8.3 state. Gate:
      journal shows real quest title/objective text from the played quest;
      screenshot; docs updated.

### M10.3 — vanilla fonts (SWF extraction)

* [ ] 10.3.1 SWF font parse: DefineFont2/3 glyph extraction from `fonts_en.swf`
      (Adobe SWF spec is public), `fontconfig.txt` mapping. Extraction only — no
      movie playback.
* [ ] 10.3.2 Acceptance: HUD + journal render with vanilla glyphs, system-font
      fallback kept; docs updated; M11+ re-scoped into numbered items with gates.

## Milestone 11+ — toward playable (direction only)

Gap analysis + decisions 2026-07-20; re-scope into numbered milestones with gates at
the M10 gate (10.3.2). Full decision docs land with first impl items.

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
* Dialogue + scenes: DIAL/INFO topic trees, dialogue UI/camera, voice via M9.3.
* Save/load: native format + change tracking engine-wide; `.ess` import after.
* Magic (MGEF/SPEL/ENCH), perks/leveling, crime/factions/services, locks/traps.
* Meta: main menu/new-game/chargen flow, settings persistence, key rebinding,
  map UI (world + local).

World/render track promoted to [Milestone 7](#milestone-7--worldrender-fidelity-starts-after-m6)
2026-07-20 (user priority); combat consumes its dynamic-physics output (7.5).

## Tooling / meta / open questions

Tracked as GitHub issues (`gh issue list`), not here: CI re-enable when Actions quota
returns (#70), commit-msg body-section enforcement (#71), engine-wide string decode
strategy (#72), plugins.txt load order (#73). Metal formatter/linter decided 2026-07-20:
[Metal shader tooling](/decisions/metal-tooling.md).
