# OpenSky knowledge base

Wiki in Open Knowledge Format (OKF v0.1). Reverse-engineered formats, subsystem design,
and decisions live here so knowledge survives across sessions. See AGENTS.md
"Documentation wiki".

## Formats

* [BSA Archive](/formats/bsa.md) - Skyrim SE v105 archive layout, LZ4 frames,
  system-accelerated independent blocks, and linked-block fallback.
* [Virtual file system](/formats/vfs.md) - resource path resolution: loose
  files over archives, archive load order, lazy open.
* [ESM/ESP plugin container](/formats/esm.md) - record/GRUP/field framing,
  zlib-compressed records, lazy traversal.
* [Game settings](/formats/gmst.md) - typed GMST DATA values, selected movement
  tuning, active-plugin precedence, and explicit fallback policy.
* [FormID + TES4 header](/formats/formid.md) - plugin header fields, master
  lists, raw FormID -> (plugin, objectID) resolution, and the cross-plugin
  `RecordIndex` with explicit dangling-reference handling.
* [Keywords and actions](/formats/keywords.md) - KYWD/AACT editor-id tags,
  cross-plugin lookup, and named resolution of object KWDA arrays.
* [Magic records](/formats/magic-records.md) - MGEF identity and 152-byte DATA layout,
  SPEL/SCRL casting headers and spell cost calculation, the ENCH enchantment header and its
  base chains, the SHOU/WOOP/LVSP/DUAL/EQUP small records, the EQUP graph that answers hand
  occupancy, load-order-wide effect, spell, shout and equip-slot lookup, and plugin-relative
  resolution of EFID, spell, item EITM and ETYP links.
* [Actor value information](/formats/actor-value-information.md) - AVIF identity fields, the
  AVSK skill-use parameters, the perk-tree node run and the CNAM ambiguity that makes it
  order-sensitive, the name join that numbers a record through the actor-value
  table, and load-order-wide lookup by FormID, editor id or actor-value index.
* [Perks](/formats/perks.md) - PERK header and effect sections, the quest, ability and
  entry-point payload union, the 92 entry points and the EPFD function-data union, the
  condition tabs, load-order-wide lookup with the flat entry-point index and NNAM rank
  chains, and the histogram measured on a vanilla install.
* [Locations](/formats/locations.md) - LCTN/LCRT layouts, cycle-safe parent and keyword
  traversal, CELL XLCN links, and direct quest-location alias fills.
* [Factions](/formats/factions.md) - FACT relations, flags, crime values, ranks and the
  vendor block, NPC_ SNAM membership with its template-flag inheritance, the
  load-order faction store, and the runtime membership component with its
  flattened interfaction relation index.
* [Relationships](/formats/relationships.md) - RELA parents, rank enum and secret flags,
  ASTP association titles, and the load-order relationship store with its order-free pair
  query.
* [plugins.txt load order](/formats/plugins-txt.md) - enable flags and file
  order, where the file hides on macOS, and the plugin order OpenSky builds
  from it.
* [Localized string tables](/formats/strings.md) - .strings/.dlstrings/
  .ilstrings layout, lenient encoding policy, lstring lookup wiring.
* [UI translation strings](/formats/translation-strings.md) - UTF-16
  Interface/Translations/*.txt files, $KEY token resolution, label provider.
* [Record decoders](/formats/records.md) - WRLD/CELL/ECZN/COLL/DOBJ/REFR/STAT/FLST/GLOB/MOVT field layouts
  and their engine types, including REFR XLKR linked references and the XPRM
  primitive volume, encounter-zone and collision-layer resolved links, entry-granular
  default-object overrides, cycle-safe cross-plugin form-list flattening and membership,
  and the GLOB float-on-disk typing trap. Also the inventory
  families MISC/BOOK/ALCH/INGR/WEAP/AMMO, CONT contents, REFR ownership, the
  `ItemDefinitionStore` index, and the order-dependent QUST record - stages, log
  entries, objectives, alias fill types, and the `QuestStore` index.
* [Dialogue records](/formats/dialogue.md) - DIAL topics, ordered INFO response runs,
  VTYP voice-directory identities, NPC_ VTCK inheritance, and the `DialogueStore` index.
* [Interior lighting records](/formats/lighting.md) - CELL XCLL/LTMP, LGTM DATA/DALC,
  LIGH DATA/FNAM, REFR XRDS/XEMI, inheritance + decode policy.
* [Exterior water records](/formats/water.md) - CELL XCLW/XCWT, WRLD defaults + parent
  inheritance, WATR DNAM color offsets and sentinel policy.
* [Terrain records](/formats/land.md) - LAND/LTEX/TXST layouts: VHGT gradient
  height field, VNML/VCLR, BTXT/ATXT/VTXT splat layers, texture sets.
* [Grass records](/formats/grass.md) - GRAS fixed DATA controls + repeated LTEX GNAM links.
* [Weather records](/formats/weather.md) - WTHR NAM0 color layers/FNAM fog/DATA
  wind + precipitation, CLMT weather lists + timing, REGN weather and sound areas.
* [Sound records](/formats/sound.md) - SNDR descriptor tracks, SNCT category hierarchy,
  SOUN SDSC links, attenuation, looping, and separator-led canonical VFS path resolution.
* [Acoustic space (ASPC)](/formats/acoustic-space.md) - interior-ambience bridge:
  ASPC fields, the `RDAT` FormID collision with REGN's area header, and the
  interior-only region borrow.
* [Navmesh records (NAVM, NAVI)](/formats/navmesh.md) - NVNM vertices, triangles, edge and
  door links, the null-worldspace parent-cell union, and the NAVI index map that says which
  navmeshes exist and which link to which.
* [Material types](/formats/material-type.md) - MATT fields, the CRC32 of the Creation Kit
  material name that a NIF collision shape stores, and the Havok-value and LTEX.MNAM lookups
  that turn any surface into the MATT an impact table is keyed by.
* [Footstep records](/formats/footstep.md) - FSTP tags + IPDS links, FSTS per-gait
  lists and the reversed XCNT/DATA ordering, IPDS material pairs, IPCT sound links,
  ARMA.SNDD, and the tag-to-sound chain the footstep director walks.
* [Music records (MUSC, MUST)](/formats/music.md) - MUSC playlist flags/priority/
  ducking plus MUST track type, loop and cue data, the CELL/WRLD/REGN music links,
  and the `music\` path rules.
* [Conditions (CTDA, CITC, CIS1, CIS2)](/formats/conditions.md) - the shared 32-byte
  condition payload: operator and flag bits, float or GLOB comparison value, raw
  function index and parameters, run-on types, and the skip-don't-throw decode policy;
  plus evaluation - the function registry, OR grouping, run-on resolution, the
  reason-tagged-false failure model, keyword/list/location data seam, the magic seam with
  its spell-knowledge, effect-presence and casting-state functions, and the coverage
  tally with its vanilla and active-load-order sweeps.
* [AI packages (PACK, PKID)](/formats/packages.md) - general data, calendar schedules,
  header conditions, public location/target inputs, template links, procedure names, and
  the Whiterun resident census.
* [Papyrus compiled scripts](/formats/pex.md) - big-endian Skyrim PEX 3.2
  framing, typed objects/functions/instructions, VFS loading, defensive error
  policy, opcode inventory, and typed native-call coverage census.
* [Papyrus attachment data](/formats/vmad.md) - ESM VMAD script and property
  decode, both object layouts, fragment and alias skip policy, FormID-to-
  ReferenceKey resolution, and exact PEX backing-variable binding.
* [Distant LOD](/formats/lod.md) - lodsettings plus BTR/BTO paths and LOD-specific NIF
  blocks, tree LST/BTT layouts, placement rules, full vanilla sweep evidence.
* [Skyrim INI settings](/formats/ini.md) - read-only decode, file precedence, localized
  string-table language, typed terrain-distance values, and OpenSky override policy.
* [NIF mesh](/formats/nif.md) - Gamebryo 20.2.0.7 container, scene graph,
  row-vector `Matrix33` convention, geometry/materials, SSE skin blocks,
  dynamic FaceGen + skeleton bind pose.
* [NIF Havok collision](/formats/nif-collision.md) - bhk root/body/shape graphs,
  rigid-body inertial tail, ragdoll and hinge constraints, blend-collision bone carriers,
  compressed mesh reconstruction, unit/filter policy, SkyrimLayer 12 trigger routing,
  Whiterun sweep and dynamics census evidence.
* [NIF particle systems](/formats/nif-particles.md) - NiParticleSystem/NiPSysData,
  emitter + modifier blocks, effect-shader wiring, Whiterun sweep evidence.
* [DDS texture container](/formats/dds.md) - DDS_HEADER/DXT10 layout, BCn + 32-bit RGB,
  mip chain math, color-space policy.
* [Actor records](/formats/actors.md) - ACHR/NPC_/LVLN/LVLI/LVSP/RACE/CLAS/ARMO/ARMA/OTFT
  layouts, the AIDT aggression, confidence, morality and assistance struct, TPLT chain +
  visual appearance resolution (skin/outfit/slot
  masking), FaceGen path convention + actor GPU assembly.
* [FaceGen TRI expressions](/formats/tri.md) - FRTRI003 base topology, named scaled
  vertex deltas, HDPT/RACE/NPC_ association, and defensive decode policy.
* [HKX packfile container](/formats/hkx-container.md) - Havok hk_2010 packfile
  header, section + fixup tables, class-name inventory, object enumeration.
* [hkaSkeleton object](/formats/hka-skeleton.md) - bone names, parent indices,
  reference pose decode + name-map onto the NIF skeleton nodes skinning uses.
* [hkaSplineCompressedAnimation](/formats/hka-animation.md) - idle-clip metadata,
  spline blocks, 16-bit vector/40-bit quaternion decode + local-transform sampling,
  and the `hkaAnnotationTrack` marks that carry the footstep tags.
* [HKX behavior graph objects](/formats/hkx-behavior.md) - shared object-graph pointer,
  array and string resolution; hkRootLevelContainer, hkbBehaviorGraph, graph/string data,
  variable value set, project + character string data, file role, vanilla census.
* [HKX behavior node classes](/formats/hkx-behavior-nodes.md) - byte layouts of every
  node, modifier, condition and Bethesda extension class the vanilla player behavior
  files contain, the class registry keyed by class name, and the graph walk on it.
* [SWF container](/formats/swf.md) - FWS/CWS signature + compression, bit-packed
  FrameSize RECT, tag stream framing, standard tag-name table (Scaleform UI);
  DefineShape-DefineShape4 decode + tessellation, lossless/JPEG bitmap tags,
  DefineFont2/3 glyphs + text tags, fontconfig.txt alias mapping, and the
  display-list control tags (place/remove, sprites, clip depth, asset imports).

* [FUZE voice container](/formats/fuz.md) - .fuz voice lines: the FUZE header, the
  optional .lip blob, the embedded xWMA stream, and the voice-file naming rule derived
  from the vanilla archive listing.
* [FaceFX lip animation](/formats/lip.md) - .lip header families, the tick-derived slot
  stride, the ambiguous marker framing and how the decoder resolves it, positional
  speech-slot mapping, confidence boundaries, and vanilla sweep evidence.
* [xWMA container](/formats/xwm.md) - .xwm music files: RIFF/XWMA framing, fmt
  WAVEFORMATEX parameters, dpds packet table, data payload, frame-only policy
  and vanilla sweep evidence.

* [RIFF/WAVE container](/formats/wav.md) - .wav sound effects: RIFF framing, the fmt
  PCMWAVEFORMAT chunk, 8/16-bit linear-PCM widening, the format policy and the
  buffer-rather-than-stream playback rule.

* [OpenSky save container](/formats/opensky-save.md) - our own .osav format, not
  Bethesda's: header metadata, load-order fingerprint, tagged chunks and the
  reference-delta, global-variable, Papyrus script-instance, Papyrus update-timer,
  runtime-inventory and spawned-reference entry layouts, determinism and version rules,
  atomic write, and the
  `OpenSkySaveStore` slot façade + fingerprint builders above it.

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.
* [Cell scene build](/engine/cell-scene.md) - exterior cell -> draw list: WRLD walk,
  STAT resolution, skip taxonomy, grouping, world bounds.
* [Cell streaming](/engine/cell-streaming.md) - camera position -> desired NxN exterior-cell
  grid, built off the main thread on one serial queue with a per-frame residency budget, and
  the world-state snapshot every dispatched build carries.
* [Runtime navigation](/engine/navigation.md) - resident NAVM graph, bounded feet
  projection, deterministic triangle A-star, radius-aware funnel paths, door crossings,
  budgeted invalidation, capped NPC capsule following with sparse persistence and actor
  triggers, the depth-tested navmesh/path debug overlay, and the
  `World > AI & Navigation` verification surface the M16 gate ships.
* [Perception and detection](/engine/detection.md) - fixed-step observer-target pass: view
  cone, exact line-of-sight ray, gait-based noise, the cited detection value with its stated
  gaps, accumulation into unaware/suspicious/detected, the investigate position, the three
  perception condition functions, and the view-cone debug overlay.
* [Actor package schedules](/engine/package-schedules.md) - ordered PKID selection,
  template inheritance, bounded/event-driven reevaluation, current-state inspection, and
  deterministic travel, wander, sandbox, sleep, and eat procedure machines, and the
  `World > AI & Navigation > Package` surface that shows which one won.
* [Terrain mesh build](/engine/terrain.md) - LAND -> per-quadrant meshes under the cell's
  objects: grid topology, base textures, XCLC quad-hiding, DNAM fallback plane, placement.
* [Procedural grass](/engine/grass.md) - deterministic LAND-driven placement, cell-owned
  instanced rendering, weather wind, distance fade, budget, and app controls.
* [Distant LOD streaming](/engine/distant-lod.md) - INI-driven cell-clipped rings, tree
  billboards, atomic replacement, asset lifetime, real-render evidence.
* [Sky + water environment](/engine/sky-water.md) - procedural time-of-day sky, per-cell
  water resolution/build, animated alpha-blend render path.
* [Weather runtime](/engine/weather.md) - region/climate weather selection, timed
  sky/fog/ambient transitions over time-of-day, published wind, force/pause app controls.
* [Interior door transitions](/engine/interiors.md) - interior CELL build, DOOR/XTEL
  resolution, selected activation, camera teleport, suspended exterior streaming.
* [Interaction targeting](/engine/interaction.md) - walk-mode view-ray selection,
  localized record names and action labels, typed activation events, HUD publication,
  exact door dispatch, and the world-item layer above it: taking a loose item, container
  transfer sessions, dropping into the world, and the `World > HUD & Interaction > Items`
  acceptance surface.
* [Free-fly camera](/engine/free-fly-camera.md) - WASDQE + mouse-look input capture,
  yaw/pitch pose -> view matrix, movement speeds tuned to Skyrim scale.
* [Terrain walk mode](/engine/walk-mode.md) - fixed-step capsule, terrain + mesh
  collide-and-slide, slope/ceiling response, bounded stairs, door pose reset, build-aware
  route timing gate with floor-safe interior waypoints, the three camera modes, the
  third-person orbit camera with collision-aware zoom, the rendered player body, and the
  first-person acceptance surface.
* [Static collision world](/engine/collision-world.md) - per-cell placed bhk shapes,
  immutable BVH broadphase, fail-loud geometry accounting, streaming lifetime + budgets,
  trigger volumes and their per-frame OnTriggerEnter/OnTriggerLeave occupancy diff.
* [Dynamic rigid bodies](/engine/dynamic-bodies.md) - which Havok bodies simulate, the
  convex collider and the narrowphase that reads a surface's facing off its own winding,
  the fixed-step integrator with its tunneling guard, penetration recovery and sleep rules,
  sphere and capsule sweeps, the player's shove, the per-instance delta that draws a body
  where the solver has it, deterministic exterior re-binning with draw handoff, the
  streaming and resting-transform lifecycle, and the optimized perf gate.
* [Death and constraint-solved ragdoll](/engine/ragdoll.md) - how a zero-health actor dies
  and hands its skeleton to the physics, the ragdoll built from the skeleton NIF's per-bone
  bodies and joints, what the authored constraint angles were measured to mean, the
  sequential-impulse joint solver and the position-based one it beat, the
  animated-to-simulated blend and the pose write-back, interleaved constraints and settling, persistent
  death and its stated visual cost, and corpse looting.
* [Actor idle animation](/engine/actor-animation.md) - HKX idle sampling, skeleton-world
  pose composition, NIF palette refresh, streamed lifetime, fallback accounting + budget,
  the graph-driven player path and its simulation clock.
* [Face morph runtime](/engine/face-morphs.md) - per-actor TRI weights, CPU position and
  normal composition, morph-capable skinned and shadow pipelines, and app controls.
* [Behavior graph runtime](/engine/behavior-runtime.md) - headless Havok Behavior
  evaluation: instance model, fixed update order, variables, events, bindings, clip time
  and triggers, weighted blends, state machines with event-driven transitions, crossfades
  and nesting, the transition-condition language, clip phase synchronization, root-motion
  extraction, multi-file behavior references, the first-person rig and its second graph
  instance, the `World > Player & Locomotion` destination, and the honest-coverage tally.
* [Living environment integration](/engine/living-environment.md) - combined M7 runtime,
  app A/B controls, exterior/interior evidence + frame/build/footprint gate.
* [Menu mode](/engine/menu-mode.md) - push/pop menu stack, world-vs-menu input-capture
  switch, world-sim pause via a pausable frame clock (no time jump on resume).
* [System menu](/engine/system-menu.md) - Resume/Settings/Quit selector, the menu-stack
  handoff that pauses the world, the data-root and audio-volume settings placeholders,
  and synchronized keyboard navigation through the visible vanilla `quest_journal.swf`
  System and Settings pages.
* [Quest journal](/engine/journal.md) - the Quests page of vanilla `quest_journal.swf`
  driven from quest state: the measured list contract, the row model and its string tables,
  `<Alias=...>` text substitution, the world-mode `J` key, the
  `World > Quests & Journal` surface, and the M13 gate that drives a quest end to end
  through it.
* [Inventory menu](/engine/inventory-menu.md) - the player's item list and its categories,
  the cross-movie character import vanilla `inventorymenu.swf` needs before it has a list
  at all, the `EntriesA` data contract, and the equip/unequip/drop actions behind it.
* [Container and barter menus](/engine/barter.md) - the two-pane transfer list shared by
  vanilla `containermenu.swf` and `bartermenu.swf`, the cited `fBarterMin`/`fBarterMax`
  price formula, gold-conserving merchant transactions, and the merchant nomination seam.
* [Inventory and equipment gate](/engine/inventory-equipment.md) - the M12 milestone gate:
  the take/transfer/equip/buy/sell/drop/save/load loop proved end to end with conservation
  at every step, the `World > Inventory & Equipment` destination, dev item grants, `XOWN`
  ownership reporting, and per-actor appearance-skip accounting.
* [AS2 runtime](/engine/as2-runtime.md) - ActionScript 2 interpreter and the movie it
  drives: value model + coercions, bounded execution, display objects and timeline,
  Scaleform Stage rectangles, events, indexed global mouse input and hit testing, the
  GameDelegate bridge, path-targeted HUD calls, missing-API tally.
* [Papyrus virtual machine](/engine/papyrus-vm.md) - bounded Skyrim PEX execution: typed
  values, explicit frames, arrays, states, a native registry, deterministic real/game-time
  suspension scheduling, faults and coverage tallies, with VMAD-supplied initial values;
  plus the main-actor world runtime, use-key and trigger dispatch, persistent world
  mutation, update timers, save state, the actor and spell native families with their
  measured call-site counts, the `World > Scripts` surface, and the M11 gate.
* [World audio playback](/engine/audio.md) - AVAudioEngine graph with 3D positional
  sources and non-positional music/ambience beds, streaming WMA decode off the main
  thread, vanilla SNCT category volumes, per-category mute and solo, source
  budget/eviction, the per-frame audio-update budget, and the `World > Audio` surface
  plus the M9 acceptance record.
* [World SFX + ambience](/engine/world-sfx.md) - world sound director wiring
  activation and animation events to one-shot and movement-loop SFX, per-cell
  ASPC/REGN ambience bed resolution into category submixes, and the
  `World > Audio > SFX & Ambience` verification surface.
* [Music playlists](/engine/music.md) - MUSC/MUST playlist selection through the
  CELL/REGN/WRLD precedence chain, the derived exploration/town/interior states,
  palette expansion and flag handling, the shipped-file `.xwm` resolution the
  vanilla `.wav` track names need, and the crossfading music director.
* [Game clock and calendar](/engine/game-clock.md) - timescale-driven game time over the
  Tamriel calendar: the deterministic GameClock value, the clock-owns-time authority rule
  for the vanilla time globals, weather's elapsed-game-hours feed, the CLOK save chunk,
  and the fixed-clock offscreen/CLI story.
* [Dialogue runtime](/engine/dialogue.md) - topic selection over quest state and CTDA
  conditions: the owning-quest gate, file order as selection order, say-once, the HELO
  greeting, DIAL priority ordering, and the per-response trace the acceptance panel reads;
  said-state as a world-state component keyed by INFO with its additive DLGS save chunk;
  what choosing a response does, including result-fragment dispatch through the Papyrus
  runtime and the route a quest-stage result takes to `QuestRuntime.setStage`; the three
  dialogue condition functions; the dialogue camera that frames the speaker's head as an
  override rather than a fourth camera mode, and the speaker focus that stops, turns and
  suspends the actor being talked to; and the fidelity gaps this version leaves open.
* [Dialogue menu](/engine/dialogue-menu.md) - the player-facing half of dialogue: Talk
  activation on an actor through the melee capsule narrowphase rather than the static
  collision BVH, the occluder rule that keeps a shopkeeper behind a door from being a
  target, the per-menu world-pause policy that lets a conversation run while the world
  keeps simulating, the measured `dialoguemenu.swf` contract including the one method that
  is measured and deliberately unused, the movie-free menu model, string-table resolution
  per field, gameplay subtitles on the HUD, and the entry points deferred to voice and lip
  sync.
* [Runtime reference identity and world state](/engine/runtime-state.md) - session-stable
  ReferenceKey identity over plugin and generated references, the per-cell
  RuntimeReferenceIndex, and the mutable WorldStateStore above it: typed component deltas,
  dirty tracking, reset-to-plugin-default, the bounded change journal, the
  deterministic snapshot, how a cell build applies that snapshot to render and
  collision together, how a mutation to an already-resident cell reaches the screen
  through a streamer-driven rebuild, the runtime global-variable layer and the value-lookup
  seam conditions and the clock read through, the save/load round trip through
  OpenSkySaveStore, and the `World > Runtime State` panel with its time, globals and
  conditions sections, the interleaved journal tail, the M10.1 and M10 acceptance
  records, and the inventory component above all of it: full-override stacks, re-derived
  container/actor/player baselines, the add/remove/transfer accounting layer with its
  conservation guarantees, carry weight and gold, and the additive INVN save chunk; plus
  the spawned-reference component that lets the running game place objects no plugin
  authored, its synthesized 0xFF-prefixed FormID, and the additive SPWN save chunk.
* [Actor values](/engine/actor-values.md) - the whole 164-entry table end to end: the cited
  race-plus-offset-plus-class-per-level derivation and its exact apportionment rule, the
  census against every auto-calc record's baked DNAM, the current-values-only runtime
  component, the override store's base-offset-plus-three-modifiers entries and their
  record-derived baselines, the precedence rule that lets a trained value survive
  re-derivation and still gain from it, the three actor-value write natives with their
  quoted slot semantics, the capped resistance query and its multiplicative composition
  rule, percent-per-second regeneration on the menu-pause-safe fixed step, the live HUD
  meter binding, the additive AVAL and AVOV save chunks, the negative-resistance weakness
  reading, and the panel provider seam.
* [Magic and active effects](/engine/magic.md) - the runtime notion of an effect acting on
  an actor: the cited archetype semantics for the value, dual-value and peak-value
  modifiers, the two timed behaviours the Recover flag selects and the instant application
  that is neither, the per-archetype coverage tally, condition gating at application time,
  the No Recast and peak-keyword stacking rules, the additive AEFF save chunk that makes
  AVOV's dropped temporary modifier recoverable, the potion and ingredient consumption path
  with its cited first-effect rule, the panel provider seam, and the caster runtime: the
  spellbook component and its SPLB chunk, where start spells actually come from,
  the actor spell baseline behind an NPC's known spells and the leveled spell lists it
  expands, the script-facing condition and Papyrus surfaces, the tome
  "Read" mark, readying a spell to a hand through the EQUP all-of/one-of distinction, the
  fire-and-forget and concentration cast loops with every cited refusal, abilities and the
  once-per-day power rule, the cast input and animation seam, and aimed delivery: the
  payload a cast resolves once, spell projectiles through the archery pipeline, the
  direct-versus-bystander area rule and the measured feet unit behind it, resistance and
  weakness scaling on hostile magnitudes, the combat consequences a hostile hit carries, and
  item enchantments: the measured charge model behind `floor(EAMT / cost)`, the ECHG chunk and
  the base-FormID key it costs, contact effects through the shared spell-hit path, the third
  `ActiveEffectMode` a constant effect needed, the worn reconcile that survives every equip
  path, the worn restriction that gates nothing at runtime and the 70 vanilla counterexamples
  that settle it, and the fortify actor values the damage formulas now read.
* [Perks at runtime](/engine/perks.md) - owning perks on an actor, the entry-point evaluator
  every combat and magic formula queries, which functions and entry points are covered, the
  condition-tab subjects the engine can and cannot bind, and the wired damage, block and
  spell-cost seams.
* [Skill advancement](/engine/skill-advancement.md) - how one use of a skill becomes skill
  experience, the three UESP formulas and the `AVSK` numbers this install authors, why the
  `Skill Advance` actor values hold the accumulated experience, the reporting seam every
  combat and magic runtime writes into, what each simulated action is worth, the carry rule
  at a threshold, the character-experience bank character leveling spends, and the actions
  that are documented but not yet simulated.
* [Character leveling](/engine/character-leveling.md) - the level curve and the four GMSTs
  behind it, where the level, banked experience and perk-point pool persist, when the level
  moves and the one stated deviation from the menu-confirmed vanilla one, what an attribute
  pick does and why the ten points live in a base override, the shared live player level
  every `PC Level Mult` derivation reads, the seven rules a perk-point spend has to
  satisfy, and the `World > Progression` panel that is the milestone's verification
  surface.
* [Archery and projectiles](/engine/archery.md) - the PROJ flight record, the measurement
  that settles `gravity` as a multiplier rather than an acceleration, the census-named bow
  draw and release events, the exact closed-form flight model on the fixed step, the
  documented bow-plus-arrow damage combination and draw-time curve, the split sweep an
  impact uses, stuck arrows under the vanilla count cap and the streaming lifecycle, the one
  shot model arrows and spell projectiles share, and the panel provider seam.
* [Melee combat](/engine/melee-combat.md) - draw and sheath on the clip annotation, attack
  and block through census-named graph events, the multi-consumer graph-event seam, the
  documented `fCombatDistance` reach formula and the swept-capsule hit volume, target
  filtering and one hit per swing, the install's own block GMSTs and how they differ from
  the secondary source, stagger, and the WEAP INAM impact-sound chain.
* [Crime and bounty](/engine/crime.md) - ownership enforced at last: the reference-then-cell
  `XOWN` precedence and the CELL owner this item decodes, the location parent chain that
  finds the hold answering for a place, the four crimes priced from the faction's own `CRVA`
  rather than from a game setting that does not exist, witnessing through the converged
  perception pass, the per-crime-faction bounty ledger with its counts, the stolen flag that
  splits an inventory stack and survives every move, the five choke points the hooks sit at,
  `GetCrimeGold` and the five Papyrus natives, and the v1 limitations written down rather
  than pretended away.
* [Combat loop](/engine/combat.md) - hostility derived from faction relations, RELA
  relationship rank and the actor's own AIDT aggression, with the documented
  precedence order and the named crime seam, the explicit override as its own
  component and its additive CBTS save chunk beside the FCTN memberships,
  combat state derived every step from who is engaged rather than stored, the
  per-actor combat behavior machine that perceives, approaches, attacks,
  blocks, breaks off at low health, searches the last place it saw the player and gives up, every
  cadence and threshold stated as OpenSky's own, the `StartCombat` and `StopCombat` natives,
  census-named recoil reactions in both directions, bounded reaction clips on the
  single-clip NPC playback, the four transient caps and the eight-fighter engagement cap,
  the casting phase and the rule a fighter chooses a spell over a swing by,
  the combat-music edge, the panel provider seam, and the `World > Combat & Physics`
  destination that is M15's verification surface and acceptance record.

## Rendering

* [Metal 4 mesh renderer](/rendering/metal4-renderer.md) - static + animated skinned paths:
  pipeline variants, uniform/palette rings, argument tables, counter-heap frame stats plus
  the live snapshot seam, offscreen render, scene types.
* [Cascaded sun shadows](/rendering/shadows.md) - cascade fit math, depth-only
  pre-pass with per-cascade caster culling clamped to resident cells, off/low/high
  quality + `World > Environment` surface, fly-bench CPU budget, PCF sun-term
  filtering, A/B verification.
* [Render debug views and layer isolation](/rendering/render-debug.md) - function-constant
  gated debug channels, the `RenderLayer` mask both the scene and shadow passes honour, the
  composition rule against the subsystem enables, and the `World > Render Debug` surface.
* [Particle playback](/rendering/particles.md) - deterministic CPU emitters, weather-wind
  modifiers, instanced Metal billboards, effect blend pipelines, app controls + Whiterun
  offscreen acceptance.
* [Precipitation volumes](/rendering/precipitation.md) - WTHR-driven camera rain/snow,
  shared particle rendering, wind, roof ray occlusion, storm sky darkening + acceptance.
* [Screen-space UI layer](/rendering/ui.md) - 2D overlay over the finished frame:
  anchored scene, layout + text primitives, system-font glyph atlas, scale handling,
  UI Lab surface, and the SWF display-list render layer (per-draw uniforms,
  stencil clips, live vanilla HUD, UI Lab movie selector).

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, stable local signing, no sandbox.
* [Coordinates + units](/decisions/coordinates.md) - Skyrim Z-up world kept verbatim,
  view/projection convert to Metal; matrix convention, winding, near/far, REFR euler.
* [First render cell](/decisions/first-render-cell.md) - WhiterunExterior06 at Tamriel
  (6,-2) as the 2.7/2.9 target; probe ranking, MODL `meshes\` prefix rule.
* [Metal shader tooling](/decisions/metal-tooling.md) - clang-format for .metal,
  compiler warnings-as-errors as the linter; documented exception to per-language rule.
* [AS2 runtime scope](/decisions/swf-as2-scope.md) - implement the closed 56-opcode
  set vanilla menus use in full; phase the open-ended host API behind a logged
  no-op plus tally.
* [Havok behavior scope](/decisions/havok-behavior-scope.md) - full-graph evaluation over
  the 55 classes the vanilla player files use; swim in, first person with full arms,
  clean-room sourcing rule.
* [App logo + icon pipeline](/decisions/app-logo.md) - original "North Peak" SVG mark,
  `make icon` renders AppIcon set via rsvg-convert; legal rationale.
* [Game-data string decoding](/decisions/string-decoding.md) - one lenient policy for
  every string read out of the install: UTF-8, then windows-1252, then ISO 8859-1,
  never a failure; the narrow strict exception for structural fields.
* [ffmpeg for audio decode](/decisions/ffmpeg-audio.md) - vendored decode-only LGPL build
  in a gitignored prefix, `import CFFmpeg` module map, dylibs embedded in the app bundle;
  why the Homebrew build is unusable and what LGPL requires.

## Tools

* [CLI dev tool](/tools/cli.md) - openskycli target sharing the engine sources:
  commands, mode-specific benchmark validation, and env-gated make probe harness.
* [Main-app asset browser](/tools/preview-gui.md) - Library > Asset Browser destination:
  VFS browsing, load-order reference-record inspectors, the nine M19 magic record families
  and what each summary resolves, toolbar World PNG capture, and offscreen NIF/DDS previews.
* [Main-app UI framework + placement](/tools/app-ui.md) - unified sidebar shell,
  destination registry, panel base classes, hosted sections, placement tree,
  layout + interaction invariants, accessibility-id contract.
* [Sidebar verification convention](/tools/sidebar-acceptance.md) - the record every
  milestone acceptance writes (path, destination id, control ids, readout, covering
  tests), what counts as evidence, and the per-milestone ledger.
* [Build system and xcodebuild invocation](/tools/build-system.md) - the one xcodebuild
  command line every make target and tools/ script shares: knobs and their defaults,
  `-quiet` versus the transcripts kept in `logs/`, Swift warnings as build errors, the
  derived built-products path, the `Config/*.xcconfig` layer that holds every build
  setting, the `OpenSkyShaderTypes` clang module that replaced the bridging header, the
  compilation cache and the flows it does and does not speed up, and what
  `-only-testing` does not save.
* [Run output layout and make prune](/tools/run-output.md) - one timestamped run
  directory per run under `logs/` and `build/test-results/` with a `latest` symlink, which
  script writes where, and the `make prune` rules that delete stale worktree DerivedData
  and aged-out runs without reaching a source.
* [Swift toolchain and language mode](/tools/swift-toolchain.md) - the Apple Swift 6.3.3
  baseline, Swift 6 language mode across every target, the `make swift-baseline` gate that
  enforces both, default main-actor isolation, and the isolation patterns the migration
  settled on.
* [Local environment and external state](/tools/environment.md) - dated record of
  machine-specific and third-party facts skills must not hardcode: TCC permissions,
  CI suspension, upstream spec-host quirks, each with the condition that retires it.

## Meta

* [Testing setup](/testing.md) - the three test targets and the shared support
  folder, make entrypoints, the RealData test plan behind `make realtest` and
  `make realtest-all`, the Sanitizers plan behind `make test-sanitize`, the
  watchdog, result reporting, code coverage, machine-specific quirks.
* Roadmap - not in this wiki. Open work lives in GitHub issues and milestones, where
  milestone `#n` is OpenSky milestone `Mn`. See AGENTS.md "Roadmap and open work".
