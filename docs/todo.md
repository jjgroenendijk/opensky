---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-23T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-23. Ordered by mission priority (AGENTS.md): render static world
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
5. Every milestone adds or extends a discoverable main-app sidebar verification surface.
   Record exact sidebar path at acceptance. Parser/math-only work may surface with its
   first visible consumer; CLI/probe evidence remains required where specified.

Machine quirks: repo on case-insensitive external APFS volume (case-only rename needs
`git mv`; AppleDouble `._*` files ignored). Xcode 26 ships without Metal Toolchain
(bootstrap handles the download). CI is suspended (Actions quota) — git hooks are the
only gate; `ci.yml` is manual-dispatch and self-skips below Xcode 26.

## Milestones at a glance

Each milestone = one goal + one final measurable acceptance gate. Sub-milestones may add
earlier integration gates. Done milestone leaves this file; history lives in
`docs/log.md` + git.

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
* M6 — actors animate. Done 2026-07-20: skeleton-driven idle playback on streamed actors,
  exact lifecycle accounting, deterministic frame-delta gate, exterior/interior probes.
* M7 — living environment. Done 2026-07-22: shadows, weather/sky/wind, shared particles,
  precipitation, grass, app A/B controls + integrated exterior/interior/fly gates.
* M8 — interaction + UI shell (active): vanilla SWF UI (SWF parse, static render,
  AS2 subset — issue #99), menu mode, interaction targeting, HUD, settings. Gate: 8.5.3.
* M9 — world audio: decode/playback, sound records, positional SFX, ambience, music.
  Voice + lip sync moved to dialogue. Gate: 9.2.4.
* M10 — mutable world foundation: runtime identity/state, change tracking, native saves,
  CTDA conditions, game clock/calendar, GLOB globals. Gate: 10.2.4.
* M11 — Papyrus world interaction: PEX/VMAD VM core, scheduler, activators, triggers.
  Quest runtime moved to M13. Gates: 11.1.4 / 11.2.4.
* M12 — inventory + equipment: pickup, containers, equipping, inventory UI, weight,
  gold, barter basics. Gate: 12.6.
* M13 — quests + journal: QUST runtime, aliases, stages/objectives, journal UI.
  Gate: 13.5.
* M14 — player locomotion: Havok Behavior graph evaluation, player movement parity,
  first-person camera + arms. Gate: 14.6.
* M15 — combat + dynamic physics: actor values, melee/archery, projectiles, death,
  ragdolls, dynamic clutter. Gate: 15.7.
* M16 — AI: NAVM pathfinding, packages/schedules, detection, combat AI. Gate: 16.5.
* M17 — dialogue + voice: DIAL/INFO, scenes, dialogue UI/camera, `.fuz`, TRI, `.lip`.
  Gate: 17.6.
* M18+ — broader gameplay: magic/perks/leveling, crime/factions/services, locks/traps,
  chargen/map, read-only `.ess` import.

## Milestone 8 — interaction + UI shell

Goal: user can inspect and operate the world without CLI knowledge, through the
vanilla game UI. Direction 2026-07-23 (issue #99): port the original Scaleform
interface — parse + render vanilla `Interface/*.swf` movies via Metal. Earlier
native-UI decision scrapped (log 2026-07-23); the M8.1.1 screen-space pass
(glyph atlas, premultiplied alpha, final draws over 3D frame) stays as the
compositing foundation.

Legal: Adobe SWF File Format Spec is public — reimplement SWF/GFx behavior from
spec + observation under `format-parser` discipline (synthetic fixtures only).
No Scaleform SDK code; `.swf` files load from the user's install at runtime like
all game data. Downstream menu items (M12.5 inventory, M13.4 journal, M17.2
dialogue) target their vanilla SWF menus; depth follows 8.3.1 feasibility
findings.

### M8.1 — UI shell foundation

* [ ] 8.1.2 Menu mode: input capture switch, world-sim pause, menu stack push/pop.
* [ ] 8.1.3 Strings: `Interface/Translations/*_english.txt` parser (UTF-16LE
      key/value), reusable provider resolving `$`-prefixed keys for HUD + SWF
      text fields.
* [ ] 8.1.4 Foundation acceptance: `World > UI Lab` previews menu-mode pause
      behavior + localized strings (long-string/scale cases). Gate: deterministic
      layout/UI-state + pixel-delta tests; docs + log updated.

### M8.2 — SWF format + static rendering

* [ ] 8.2.1 SWF container decode: signature/compression (FWS/CWS), header rect/
      frame fields, tag framing. Cite Adobe SWF spec; synthetic fixtures. Gate:
      vanilla `Interface/*.swf` sweep accounted (known/unknown tag tally).
* [ ] 8.2.2 Shapes + bitmaps: DefineShape-DefineShape4 fill/line styles + edge
      records, tessellation cached per `DefineShape`; DefineBitsLossless/2 +
      JPEG-variant bitmap decode. Gate: synthetic shape fixtures + vanilla sweep.
* [ ] 8.2.3 Fonts + text: DefineFont2/3 glyph extraction (incl. `fonts_en.swf`
      + `fontconfig.txt` mapping — absorbs old M18.F), DefineText/DefineEditText
      static content through the M8.1.1 glyph-atlas path; system-font fallback kept.
* [ ] 8.2.4 Display list render: PlaceObject2/3 depth/matrix/color transform ->
      per-draw uniforms, stencil for clip layers, drawn through the M8.1.1
      screen-space pass over the 3D frame.
* [ ] 8.2.5 Static-render acceptance: frame-1 display list of selected vanilla
      menus (e.g. cursor, book, loading) renders correctly offscreen + in-app;
      `World > UI Lab` selects a movie + shows tag/draw stats. Gate: pixel-delta
      evidence + sweep accounting; docs (`formats/swf.md`, `rendering/ui.md`) +
      log updated.

### M8.3 — AS2 runtime subset

* [ ] 8.3.1 Feasibility investigation: inventory DoAction/DoInitAction opcodes +
      GFx extensions vanilla menus actually use; phased-subset plan + decision
      doc (`decisions/swf-as2-scope.md`). Gate: opcode/API coverage tally
      documented; scrapped decision's "full second VM project" risk answered
      with phasing.
* [ ] 8.3.2 Minimal AS2 interpreter: opcode subset from 8.3.1 sufficient to
      init + drive selected menus; engine<->movie invoke bridge (GFx-style);
      unimplemented ops/APIs -> logged no-op + tally.
* [ ] 8.3.3 Runtime acceptance: one vanilla menu runs interactively (open,
      navigate, close) on the AS2 subset; `World > UI Lab` exposes movie state,
      invoke log, op tally. Gate: deterministic UI-state + pixel evidence;
      docs/log updated.

### M8.4 — interaction + HUD

* [ ] 8.4.1 Interaction targeting: use-key raycast target from walk mode,
      engine-owned interaction action/event, record name + action-label resolution.
      Existing doors use the same path. Papyrus OnActivate subscribes later in M11.
* [ ] 8.4.2 HUD via vanilla `hudmenu.swf`: crosshair, health/magicka/stamina
      bars (static values before combat), compass + markers, activation prompt
      ("Open <door name>") driven through the engine->movie bridge.
* [ ] 8.4.3 HUD acceptance: `World > HUD & Interaction` exposes target debug,
      prompt preview, compass markers, scale, and element toggles. Gate: walk-mode
      numeric pixel delta with live door prompt; targeting tests + local visual check;
      docs/log updated.

### M8.5 — system menu + durable verification surface

* [ ] 8.5.1 System menu: resume/settings/quit; data root + audio-volume placeholders
      surfaced; vanilla menu movie where the AS2 subset suffices (per 8.3.1).
      Later M9 binds live audio categories.
* [ ] 8.5.2 Sidebar verification convention: framework + placement rules landed (issue #98,
      `docs/tools/app-ui.md` + `app-ui` skill — registry, panel base classes, control-state
      + accessibility-id conventions, scroll/layout tests). Remaining: each milestone records
      its exact main-app sidebar path + deterministic A/B evidence at acceptance.
* [ ] 8.5.3 Milestone acceptance: launch app -> select World -> enter walk mode ->
      inspect live vanilla-SWF interaction/HUD -> pause -> change a setting ->
      resume, without CLI. Gate: deterministic UI-state + pixel-delta evidence;
      docs/log/todo updated; review M9.

## Milestone 9 — world audio

Goal: Whiterun sounds alive — positional SFX, ambience, music. Voice + lip sync move
to M17 dialogue, their first real consumer.

Decode route decided 2026-07-20: ffmpeg (LGPL) behind a Swift interface, dynamically
linked; license + justification documented per AGENTS.md dependency rule. Specs:
RIFF XWMA chunk docs + UESP SNDR/SOUN/SDSC/MUSC/MUST records.

### M9.1 — decode + playback foundation

* [ ] 9.1.1 ffmpeg dependency: SwiftPM/C wrapper target, dynamic link, xwm (WMA2)
      payload -> PCM. Decision doc (`decisions/ffmpeg-audio.md`): license, decode-only
      scope, alternatives rejected. Gate: real + synthetic xwm decode to sane
      duration/format.
* [ ] 9.1.2 `.xwm` framing: own parser under `format-parser` discipline; payload
      decode via 9.1.1. Gate: vanilla `.xwm` sweep splits + decodes clean; synthetic
      fixtures cover malformed input. `.fuz` framing moves to M17 voice.
* [ ] 9.1.3 Playback engine + acceptance: AVAudioEngine graph, 3D positional sources
      bound to world transforms, streaming buffers, category volumes. Gate:
      deterministic buffer-tap tests + audible positional real SFX; live source +
      volume controls under `World > Audio`; docs (`engine/audio.md`) + log updated.

### M9.2 — game audio wiring

* [ ] 9.2.1 Sound records: SNDR/SOUN/SDSC decode, descriptor -> file resolution,
      attenuation/looping params.
* [ ] 9.2.2 World SFX: door open/close from M8 interaction events + per-cell
      ambience loops where resolution is cheap. Generic interaction events accept
      activator sounds; M11 scripts can emit them later.
* [ ] 9.2.3 Music: MUSC/MUST playlists, exploration/town/interior selection with
      crossfade.
* [ ] 9.2.4 Milestone acceptance: `World > Audio` can mute/solo categories, inspect
      sources, force tracks, and trigger a selected sound. Gate: Whiterun walk has
      door SFX, ambience, music transitioning interior/exterior; frame budget kept;
      source/accounting tests + manual audible confirmation; docs/log/todo updated;
      review M10.

## Milestone 10 — mutable world foundation

Goal: define persistent runtime identity + state before Papyrus, inventory, quests,
AI, and dialogue mutate the world. Native saves land with first mutable state, not as
an engine-wide retrofit.

Primary format: OpenSky-native, versioned, documented, deterministic. Later read-only
`.ess` import supports migration; OpenSky never writes `.ess`.

### M10.1 — runtime state + native saves

* [ ] 10.1.1 Runtime identity: stable keys for forms, placed references, streamed
      instances, and generated objects; ownership rules independent of cell lifetime.
* [ ] 10.1.2 Mutable state store + change journal: typed component deltas, dirty
      tracking, reset-to-plugin-default, deterministic snapshot ordering.
* [ ] 10.1.3 Streaming integration: changed references evict/reload without losing
      state; unloaded state does not retain render/collision assets.
* [ ] 10.1.4 Native save container: versioned header, load-order fingerprint,
      component chunks, bounds/compatibility checks, atomic write + typed load errors.
      Document layout in `docs/formats/opensky-save.md`; synthetic fixtures only.
* [ ] 10.1.5 State acceptance: change a door/reference state, cross a streaming
      boundary, save, relaunch/load, observe identical state. `World > Runtime State`
      exposes inspect/change/reset/save/load. Gate: deterministic round-trip tests,
      corrupt-save tests + in-app inspector confirmation; docs/log updated.

### M10.2 — shared conditions + time

* [ ] 10.2.1 CTDA condition decode + evaluator: comparison/operator framing,
      subject/target/reference contexts, registry of implemented condition functions,
      unknown functions -> reason-tagged false + coverage tally.
* [ ] 10.2.2 Game clock/calendar: timescale, pause behavior, day/month/year state,
      deterministic advancement; drives existing time-of-day + later schedules.
* [ ] 10.2.3 GLOB records + runtime values: plugin defaults, typed mutation,
      save/change-journal integration, condition lookup.
* [ ] 10.2.4 Milestone acceptance: `World > Runtime State` can scrub time, inspect
      conditions/globals/change journal, and save/load them. Gate: weather/time stays
      synchronized, state round-trips, vanilla CTDA sweep is accounted, docs/log/todo
      updated; review M11.

## Milestone 11 — Papyrus world interaction

Goal: vanilla Papyrus scripts mutate persistent world state + respond to interaction.
Quest runtime waits for M13 so this milestone can close on a visible activator.

One branch/PR per numbered item; format items follow `format-parser`. Specs: UESP
"Compiled script file" (PEX layout), Creation Kit wiki Papyrus reference (VM
semantics), xEdit VMAD defs. VM semantics are partly documented -> confirm by
observed behavior, flag deviations.

### M11.1 — VM core (headless)

* [ ] 11.1.1 PEX container decode: header, string table, objects/states/functions,
      instruction stream. Gate: vanilla `.pex` sweep decodes clean; synthetic
      in-code fixtures cover every opcode encoding.
* [ ] 11.1.2 Interpreter: value model (bool/int/float/string/object/array), call
      frames, opcode execution, state switching. Fixtures = hand-assembled synthetic
      PEX (no compiler dependency). Gate: per-opcode unit suite green.
* [ ] 11.1.3 VMAD decode + script binding: ESM VMAD subrecord (attached scripts,
      typed properties, fragment payloads), property -> form resolution. Gate:
      vanilla plugin VMAD sweep decodes; sampled script properties resolve.
* [ ] 11.1.4 Native dispatch + acceptance: native-function table, latent calls
      (`Utility.Wait`) via scheduler, unimplemented natives -> logged no-op + tally.
      Gate: synthetic script calling natives runs deterministically under test;
      coverage tally of natives referenced by vanilla scripts documented; docs
      (`formats/pex.md`, `formats/vmad.md`) + log updated.

### M11.2 — scripts run in world

* [ ] 11.2.1 VM in engine loop: per-frame scheduler budget, script-instance
      lifecycle tied to persistent M10 identity + cell streaming; OnInit/OnLoad/
      OnCellAttach dispatch.
* [ ] 11.2.2 OnActivate: subscribe to M8 interaction events; activator scripts fire;
      core ObjectReference natives (Enable/Disable/GetPosition/Translate minimal
      set) write through M10 state + change journal.
* [ ] 11.2.3 Triggers + timers: OnTriggerEnter/Leave volumes, RegisterForUpdate /
      RegisterForSingleUpdate; pending state survives save/load where required.
* [ ] 11.2.4 Acceptance: real Whiterun lever/button/pull chain visibly runs its
      vanilla script in-app; `World > Scripts` exposes target instances, events,
      scheduler, native coverage, and pause/step controls. Gate: attached-script
      no-crash sweep across streamed grid; per-frame VM budget; save/load activated
      state; numeric state/pixel evidence; docs/log/todo updated; review M12.

## Milestone 12 — inventory + equipment

Goal: first repeatable gameplay loop — inspect object, pick it up, carry it, equip it,
drop it, trade a minimal subset. Persistent state comes from M10; interaction + UI
come from M8; actor visuals come from M5/M6.

Specs: UESP + xEdit record defs for CONT/MISC/BOOK/ALCH/INGR/WEAP/AMMO and existing
ARMO/ARMA types. Format work follows `format-parser` discipline.

* [ ] 12.1 Item + container records: decode common inventory forms, names/icons/
      models, value, weight, stackability, container entries, ownership. Gate:
      vanilla sweep accounted; synthetic fixtures.
* [ ] 12.2 Inventory runtime: persistent per-owner stacks, generated stack identity,
      add/remove/transfer, carry weight, gold, equipped slots; all changes journaled.
* [ ] 12.3 Pickup + containers: M8 target action selects loose refs/containers;
      take/take-all/put-back/drop update world visibility + collision through M10
      state.
* [ ] 12.4 Equipment: equip/unequip armor + weapon on player actor, slot masking +
      geometry reuse from M5, hand attachment, animation-safe palette updates.
* [ ] 12.5 Inventory + barter UI: vanilla SWF inventory/container/barter menus
      (depth per 8.3.1 feasibility), sort/filter/detail, weight + gold, minimal
      buy/sell against a dev-selected merchant inventory. Service/faction
      restrictions wait for M18+.
* [ ] 12.6 Milestone acceptance: walk to a loose item/container, pick up, equip,
      transfer, buy/sell, save/load, and see world + actor state preserved.
      `World > Inventory & Equipment` exposes inventory grants, selected merchant,
      ownership, and equip inspection. Gate: state/accounting + numeric pixel-delta
      tests, frame/build budgets, local visual check, docs/log/todo updated; review M13.

## Milestone 13 — quests + journal

Goal: one simple vanilla quest progresses end-to-end through real scripts, persistent
stage/objective state, conditions, aliases, and visible journal UI.

Specs: xEdit QUST defs + Creation Kit quest/Papyrus docs. Uses M10 CTDA/state/save,
M11 VM, and M8 UI. DIAL/INFO decode stays limited to fields a target quest needs;
full dialogue lands in M17.

* [ ] 13.1 QUST record decode: stages, log entries, objectives, alias definitions;
      DIAL/INFO decoded only as far as the selected quest requires. Gate: vanilla
      QUST sweep accounted; synthetic fixtures.
* [ ] 13.2 Quest runtime: start/stop, SetStage/GetStage/GetStageDone, stage
      fragments, objective state; every mutation change-journaled + saveable.
* [ ] 13.3 Alias resolution: reference/location aliases, fill types used by target
      quest; forced refs first, conditions via M10 as needed.
* [ ] 13.4 Journal UI: quest list, objective state, log entries, localized text;
      debug state + alias provenance under `World > Quests & Journal`.
* [ ] 13.5 Milestone acceptance: one simple vanilla quest progresses end-to-end
      through real scripts, journal shows title/objective/log text, save/load resumes
      same stage. Gate: journal state + numeric UI evidence, local visual check,
      docs/log/todo updated; review M14.

## Milestone 14 — player locomotion

Goal: replace M4 capsule-only translation with behavior-graph-driven player movement:
walk/run/jump/sneak/swim, animation/root-motion coordination, first-person camera + arms.

Decision 2026-07-20: reimplement Havok Behavior graphs (`hkbBehaviorGraph` over
vanilla `behaviors/*.hkx`) for vanilla movement feel + animation-mod compatibility.
Massive clean-room RE task, thin public docs (hkxparse/HKX2Library lineage,
ZeldaMods Havok wiki); probe-driven like M6, deviations flagged.

* [ ] 14.1 Behavior object decode: inventory target graph classes + bindings from
      real player behavior files, confirm layouts by open parser + probe, synthetic
      fixtures for implemented objects.
* [ ] 14.2 Graph evaluator core: variables, events, state machines, transitions,
      clip generators, blends, sync + graph update ordering. Deterministic headless
      tests cover each implemented node.
* [ ] 14.3 Character-controller bridge: graph inputs from controls/ground state,
      root motion through M4 collision, collision result back into graph variables;
      no double integration.
* [ ] 14.4 Locomotion states: idle/walk/run/sprint/jump/land/sneak/swim with
      direction/speed blends and actor palette playback.
* [ ] 14.5 First-person camera + arms: camera modes, body/arm visibility, weapon
      attachment from M12, FOV + near-clip handling.
* [ ] 14.6 Milestone acceptance: exterior/interior route exercises every state,
      door round trip still works, movement persists across streaming, >30 fps route
      gate. `World > Player & Locomotion` exposes graph/state/variables/events,
      camera mode, forced state, root-motion traces. Gate: numeric motion/frame-delta
      evidence + local visual check; docs/log/todo updated; review M15.

## Milestone 15 — combat + dynamic physics

Goal: player can fight one actor with melee + archery; damage, blocking, death,
projectiles, ragdolls, and clutter share one bounded physics/runtime path.

Specs: UESP + xEdit actor-value/WEAP/PROJ defs; NifTools nif.xml for bhk constraints.
Format work follows `format-parser`; render/physics acceptance follows `probe`.

* [ ] 15.1 Dynamic rigid bodies: integrate non-fixed bhkRigidBody motion (gravity,
      impulses, sleep), broadphase updates, pushable clutter in walk mode. Gate:
      dropped/pushed clutter settles plausibly, no NaN/tunneling in stress test.
* [ ] 15.2 Actor values: health/magicka/stamina, regen, damage/heal, persistent
      current/base values; M8 HUD bars become live.
* [ ] 15.3 Melee: attack/block input + behavior events, weapon/unarmed hit volumes,
      target filtering, damage, stagger hooks, impact feedback.
* [ ] 15.4 Archery + projectiles: PROJ record decode, aim/fire, arrow flight
      (gravity + drag), impact vs collision/actors, stick-on-hit, ammo from M12.
      Gate: arrows land where aimed within tolerance.
* [ ] 15.5 Death + ragdoll: bhkConstraint chain decode (ragdoll/hinge/
      limited-hinge), constraint solve on actor skeleton, blend from animated pose,
      persistent dead state. Gate: repeated collapse stays bounded without NaN.
* [ ] 15.6 Combat loop: hostility/dev target, hit reactions, death, loot via M12,
      combined clutter/projectile/ragdoll lifecycle + streaming cleanup.
* [ ] 15.7 Milestone acceptance: fight one actor with melee + bow, block, take
      damage, kill, loot, save/load result. `World > Combat & Physics` exposes
      actor values, hitboxes, projectile spawn/trace, ragdoll trigger, physics
      freeze/reset. Gate: combined stress + frame budget, deterministic damage/
      trajectory + pixel/motion-delta tests; local visual check; docs
      (`engine/dynamic-physics.md` + combat) and log/todo updated; review M16.

## Milestone 16 — AI

Goal: actors navigate, follow schedules, detect the player, and drive M15 combat.
Uses M10 time/conditions, M14 locomotion, M15 combat, M11 scripts.

* [ ] 16.1 NAVM navmesh decode: topology, triangles, adjacency, doors/links, cell
      ownership + streaming. Gate: vanilla target-area sweep; synthetic fixtures;
      app navmesh overlay.
* [ ] 16.2 Pathfinding: navmesh projection, A*, corridor/funnel, door transitions,
      bounded repath + streamed-cell lifetime.
* [ ] 16.3 Packages + schedules: decode package forms needed by target actors;
      evaluate CTDA/time; travel/wander/sandbox/sleep/eat subset first.
* [ ] 16.4 Detection + combat AI: sight/hearing/stealth inputs, target selection,
      pursue/attack/block/flee behavior events, loss/reacquire state.
* [ ] 16.5 Milestone acceptance: selected Whiterun actors follow schedule, navigate
      exterior/interior, detect player, fight, disengage, resume. `World > AI &
      Navigation` exposes navmesh/path/package/detection overlays + actor selection.
      Gate: deterministic path/condition tests, streamed route + frame budget,
      overlay pixel-delta evidence + local visual check; docs/log/todo updated;
      review M17.

## Milestone 17 — dialogue + voice

Goal: player conducts one real voiced dialogue/scene; topic conditions, camera/UI,
audio, and lip morphs stay synchronized.

Specs: UESP DIAL/INFO/QUST/VTYP records, `.fuz` community docs, NifTools TRI docs,
`.lip` community notes (thin -> probe + document uncertainty). Uses M9 audio, M10
conditions/state, M13 quests, M16 AI, M6 face skinning.

* [ ] 17.1 Dialogue records + runtime: DIAL/INFO topic trees, responses, conditions,
      speaker/quest links, choice/result flow, persistent said/branch state.
* [ ] 17.2 Dialogue UI + camera: interaction entry, topic/response text, subtitles,
      actor focus, input/menu mode, scene pause policy.
* [ ] 17.3 Voice playback + `.fuz`: own `.fuz` header/lip-size/xwm framing parser;
      INFO -> `sound/voice/<plugin>/<voicetype>/`; payload decode through M9 ffmpeg;
      positional actor playback. Gate: vanilla `.fuz` sweep + malformed fixtures.
* [ ] 17.4 TRI face morphs: TRI container decode (NifTools docs), morph targets
      applied in skinned face path. Gate: morph math tests + offscreen frame delta.
* [ ] 17.5 `.lip` decode: phoneme track -> morph weights over playback time,
      synchronized to audio clock + subtitle lifecycle.
* [ ] 17.6 Milestone acceptance: complete one real voiced conversation/scene that
      advances or reflects M13 quest state. `World > Dialogue & Voice` exposes
      speaker/topic selection, condition trace, audio timeline, subtitle + morph
      controls. Gate: mouth-region frame deltas, audible/manual confirmation,
      deterministic UI-state evidence, save/load dialogue state, docs/log/todo updated;
      review M18+.

## Milestone 18+ — broader gameplay + polish

Direction retained; split into numbered milestones with gates at M17 acceptance as
runtime evidence clarifies scope. Candidate order:

* Magic: MGEF/SPEL/ENCH, casting/projectiles, effects, resistances, AI use.
* Progression: skills, perks, leveling, race/class bonuses.
* Crime/factions/services: ownership response, bounty, guards, merchant rules.
* Locks/traps: lockpicking UI, keys, trap triggers + disarm.
* Meta: main menu/new-game/chargen, settings persistence, key rebinding, world +
  local map UI.
* Save migration: read-only `.ess` import after native-save state coverage is broad
  enough to map imported changes. Never `.ess` write.

M18.F vanilla fonts folded into M8.2.3 (SWF font decode is core UI work now,
not polish).

## Tooling / meta / open questions

Tracked as GitHub issues (`gh issue list`), not here: CI re-enable when Actions quota
returns (#70), commit-msg body-section enforcement (#71), engine-wide string decode
strategy (#72), plugins.txt load order (#73). Metal formatter/linter decided 2026-07-20:
[Metal shader tooling](/decisions/metal-tooling.md).
