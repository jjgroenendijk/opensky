# Change log

Newest first. ISO-8601 date headings. See AGENTS.md "Documentation wiki".

## 2026-08-16

* **The caster runtime: known spells, hands and self-cast (issue #470)**: decoded spells
  reached no player. Item 19.7 adds `SpellbookState`, a world-state component holding one
  actor's known spells, read books, readied hands and spent greater powers, and
  `CasterRuntime` above it. The four fields share one slot for an invariant rather than for
  write locality: a readied hand must name a known spell, so forgetting one clears its hand
  in the same write and a save whose load order dropped a readied spell drops the hand
  instead of restoring it dangling. Where start spells come from turned out not to be where
  it looks: the SPIT "PC Start Spell" flag is set on exactly one record in the whole vanilla
  load order (`PCHealRateCombat`), because vanilla grants Flames and Healing from the intro
  quest's Papyrus script, so the two are named by editor ID and resolved through the load
  order and the finding is pinned by a real-data test. `NPC_` and `RACE` `SPLO` runs are now
  decoded and are the second source. Reading a tome adds the taught spell and records the
  book — the mark UESP documents on BOOK DATA flag `0x08`, with its own `[verification
  needed]` carried across; the tome is not removed, because no cited source says it is.
  Readying a spell deliberately does not go through `EquipmentRuntime`, whose refusal to
  equip anything the owner does not hold is the guard against duplication bugs and which a
  never-held spell would force open; the two layers meet over hands instead, and the spell
  side arbitrates both directions. `EquipSlotHands.choice` splits the all-of and one-of
  readings of an EQUP slot that `hands(of:)` collapses, which is what puts a master spell in
  both hands and a novice spell in the hand the player asked for. The cast loop implements
  both cited shapes: fire-and-forget charges, checks magicka at begin and again at release
  so a cast can never land unpaid, deducts the computed cost and applies the effect list to
  the caster; concentration drains continuously and applies once on entry and once per whole
  second, honouring the SPIT minimum duration and ending on the same insufficient-magicka
  rule. Every refusal — unsupported delivery, an uncharged release, an ability from a hand, a
  power already spent today — is a sentence and a tally entry rather than a silent no-op, and
  a zero-duration ability entry is counted rather than applied, because the effect runtime
  has no permanent mode and a one-off nudge wearing the name of a resistance would be worse
  than nothing. Casting binds no new key: a readied hand takes the attack or block button the
  way a drawn bow already does, and `CombatHandType.spell` is the state seam M25/M26 will
  hang an animation off. Spellbooks persist in a new additive `SPLB` chunk; a charge in
  progress deliberately does not, because restoring one would put the player back mid-cast
  with magicka already committed. Verified through **World > Combat & Physics >
  Spellcasting**. Aimed delivery and projectiles are 19.8.

* **Magic effects act on actors (issue #469)**: nothing in the engine had a runtime notion
  of an effect currently applying to someone; decoded ALCH and INGR effect lists reached no
  runtime system at all. Item 19.6 adds `ActiveEffectState`, a world-state component holding
  one actor's effects, and `ActiveEffectRuntime` above it. The Creation Kit's Recover flag
  selects between the two timed behaviours it documents — a magnitude held in the temporary
  modifier slot and handed back exactly on expiry, or a magnitude paid into the value once
  per completed second and never taken back — while a zero-duration effect applies once and
  is stored nowhere, which is what a restore-health potion is. Value Modifier, Dual Value
  Modifier and Peak Value Modifier are implemented against their cited definitions; every
  other archetype applies nothing and increments a per-archetype tally, as do an effect
  naming no actor value and a timed Recover effect on one of the three primaries, which has
  nowhere to go until those get the base-plus-modifiers storage item 19.5 declined to build.
  Effect-entry `CTDA` lists are evaluated against the target through the shared evaluator, so
  a list this engine cannot answer skips the entry and is counted rather than silently
  passing. No Recast refuses a second application, and two peak modifiers sharing a keyword
  keep only the stronger — the wiki's own question mark on that rule is recorded rather than
  resolved by guessing. Effects persist in a new additive `AEFF` chunk carrying how much of
  each actor value's temporary slot each effect owns, which is what makes `AVGN`'s
  deliberately dropped temporary modifier recoverable on load. The first consumer is
  consumption: drinking an ALCH applies its whole effect list, eating an INGR applies only
  its first effect per UESP's stated rule, and both are reachable from the inventory menu's
  new Consume button and from `World > Combat & Physics > Magic Effects`. One pre-existing
  bug fell out of it — the regeneration step rebuilt the actor-value component from the three
  primaries alone and dropped the general table every frame, so a held modifier would have
  survived exactly one frame.
* **The whole actor-value table is stored, resistances included (issue #468)**: item 15.3
  stored three actor values and answered nil for the other 161; item 19.5 stores all of
  them. `ActorValueState` gained a sparse general table keyed by vanilla index, each entry a
  base plus the permanent, temporary and damage modifier slots the Creation Kit's own
  scripting reference names, and `ActorValueRuntime` grew an index-addressed
  read/damage/restore/set surface over it — the three primaries keep their typed fast path,
  and only an index outside the table is still a miss. Baselines come from records where
  records author one: the eighteen skills from the cited `15 + racial bonus + class spread`
  formula over newly decoded RACE DATA skill bonuses and CLAS skill weights, plus speed
  multiplier from ACBS, and carry weight, mass and unarmed damage from RACE DATA. The
  resistance seam applies the 85% player-only cap and UESP's multiplicative
  Resist-Magic-first composition in one place, and states that no game setting on the
  install carries that cap. `GetActorValue`, `GetActorValuePercent` and the Papyrus actor
  natives answer for the whole table: of the 607 actor-value conditions in `Skyrim.esm`, 539
  named a non-primary value and were tallied misses, and all 539 now answer. The general
  table persists in a new additive `AVGN` chunk, minus the temporary slot, which the magic
  effect that set it will re-establish. `World > Combat & Physics > Actor Values` gained an
  "Other value" field, a "Set" button and a selected-value readout line with the modifier
  slots and the capped resistance fraction. Skill advancement, AVIF decode and applying a
  magic effect stay out. See [actor values](/engine/actor-values.md),
  [actor records](/formats/actors.md) and [the OpenSky save](/formats/opensky-save.md).

## 2026-08-15

* **The small magic records decode, and EQUP replaces the hand heuristic (issue #467)**:
  SHOU, WOOP, DUAL and EQUP gained decoders, `LeveledList` gained LVSP, and `ShoutStore`
  and `EquipSlotStore` resolve their links across the load order — a shout's three `SNAM`
  entries now print word and spell names rather than hex. The consequential half is EQUP:
  `EquipmentCatalog` reads a weapon's hands from its `ETYP` link through the plugin's EQUP
  graph, and `hands(for:)`, which guessed occupancy from the WEAP `DNAM` animation type, is
  deleted rather than kept as a fallback. A weapon whose link resolves to nothing takes the
  documented right-hand default and is counted. The load-order gate decoded 117 SHOU, 107
  WOOP, 33 LVSP, 2 DUAL and 7 EQUP with zero unread or malformed fields, and every one of
  the 3,354 weapon and 1,560 spell `ETYP` links that exist resolved — the only 5 misses are
  weapons carrying no `ETYP` at all. All five types are browsable in the Asset Browser.
  Shout casting, cooldowns and dual-cast runtime remain out of scope. See
  [magic records](/formats/magic-records.md) and
  [inventory and equipment](/engine/inventory-equipment.md).
* **Enchantments decode and reach the items that carry them (issue #466)**: ENCH now
  decodes identity, the `ENIT` header — 36 bytes, or the 32-byte variant that omits the
  worn-restrictions link — and the shared effect list, with unknown-preserving cast,
  delivery and enchantment-type enums. `EnchantmentStore` applies cross-plugin overrides,
  joins each effect against `MagicEffectStore`, costs it with the same curve a spell uses,
  and follows base-enchantment chains under a cycle guard. `Armor` gained the `EITM` link it
  used to skip, and weapon and armor item definitions now carry the link, the weapon-side
  charge and the winning ENCH identity. The load-order gate decoded all 766 definitions into
  757 winning identities with zero unread, malformed or unknown-enum values, and every
  `EITM` on 3,025 weapons and 2,885 pieces of armor resolved. Nothing applies an effect yet.
  See [magic records](/formats/magic-records.md).
* **Spells and scrolls decode, resolve and cost themselves (issue #465)**: SPEL and SCRL
  now decode identity, the shared 36-byte `SPIT` casting header, the scroll's inventory
  fields and the effect list, with unknown-preserving spell-type, casting and delivery
  enums. `SpellStore` applies cross-plugin overrides, joins each effect against
  `MagicEffectStore`, and computes the magicka cost from the documented curve; `BOOK`
  spell tomes and `WEAP` critical effects now name their spell. The load-order gate decoded
  1,560 SPEL and 109 SCRL definitions into 1,452 spells and 104 scrolls with zero malformed
  fields and zero unknown enums, and 1,091 of the 1,223 auto-calculated records reproduce
  their stored cost exactly, which is what settled where the formula truncates. See
  [magic records](/formats/magic-records.md).

## 2026-08-14

* **Magic-item effects resolve to decoded MGEF definitions (issue #464)**: MGEF now
  decodes identity, text, keywords, conditions, packed sounds and the full 152-byte DATA
  semantics with unknown-preserving archetype, casting and delivery enums.
  `MagicEffectStore` applies cross-plugin overrides and resolves ALCH/INGR EFID links, while
  the Asset Browser and shared text dump name effects and their actor values. The active
  load-order gate decoded all 1,812 definitions into 1,731 winning identities with 595
  unread VMAD fields, zero malformed fields and zero unknown enums. See
  [magic records](/formats/magic-records.md).
* **Localized string tables follow Skyrim's configured language (issue #441)**:
  `[General] sLanguage` from the layered `Skyrim.ini` files now selects every production
  `LocalizedStrings` table path, with a validated `english` fallback. App Settings shows
  the winning language and source, accepts a persistent filename-safe override, and reloads
  journal, dialogue, and streamed-world text immediately. See
  [localized string tables](/formats/strings.md) and [Skyrim INI settings](/formats/ini.md).
* **The walk-path probe crosses the Chillfurrow interior again (issue #405)**: the obsolete
  straight 192-unit segment ended inside a decoded collision shell, so bounded sidesteps
  cycled until timeout. The production route now follows two deterministic, floor-supported
  waypoints around the shell and reverses them for the paired-door return. The 640x360
  real-install gate completed 840 active frames, crossed 267.05 interior units, returned to
  `(31233.67, -9784.47, -4059.53)`, and passed collision, frame, and audio budgets. See
  [terrain walk mode](/engine/walk-mode.md).

## 2026-08-13

* **The Asset Browser is the M18 reference-data verification surface (issue #456)**:
  `Reference records (load order)` filters the eight M18 families by winning plugin and
  record type, sorts rows by editor ID, and names each record's winner and resolved identity.
  The shared inspector lists keyword users, flattened form lists, location parent chains,
  resolved encounter-zone and collision-layer links, and the merged default-object table;
  dangling links remain explicit `[UNRESOLVED]` values. Existing Skyrim.esm item inspectors
  and `openskycli record` use the same source-plugin-aware formatter, so KWDA arrays show
  keyword editor IDs. `M18AcceptancePanelTests` pins the full-content geometry and literal
  accessibility contract under `Library > Asset Browser`; the acceptance ledger records
  `AssetRecordInspectorStatsLabel` as its readout. See [asset browser](/tools/preview-gui.md).
* **Keyword, form-list and location conditions read M18 stores (issue #455)**:
  `ConditionDataResolution` snapshots the three load-order stores plus current and editor
  reference locations for off-main-actor evaluation. Fourteen measured functions now
  answer base-object keyword and nested-list membership, current/editor location and
  parent containment, location keywords, location aliases, and same-location comparisons;
  missing stores, reference facts and dangling FormIDs remain reason-tagged unavailable
  results. The ten-plugin active-load-order sweep pins an improvement from 69,225 of
  118,494 conditions (58.42%) to 76,579 (64.63%), while leaving mutable location-keyword
  float data unresolved. See [conditions](/formats/conditions.md).
* **Encounter zones, collision layers and default objects resolve across plugins (issue
  #454)**: ECZN decodes its short-tolerant packed level and ownership data, COLL decodes
  metadata plus resolved collides-with links, and DOBJ decodes the complete xEdit use-tag
  vocabulary while retaining unknown mod tags. Their stores add resolved-ID and
  case-insensitive editor-ID lookup; DOBJ merges sparse overrides per tag instead of
  replacing Skyrim.esm's defaults. PROJ follows its optional COLL link, and CELL/WRLD
  expose XEZN. The real-data gate met floors of 358 ECZN, 55 COLL and five DOBJ
  definitions, pinned Bleak Falls Barrow, and enumerated six active DOBJ records into an
  exact 369-tag union (the five masters plus Survival Mode). See
  [record decoders](/formats/records.md).
* **Locations now connect cells, keywords and direct quest aliases (issue #453)**: LCTN
  decodes its identity, parent, keywords and every packed reference/actor/cell array with
  measured partial-tail handling; LCRT shares the reference-tag decoder and CELL exposes
  XLCN. `LocationStore` adds load-order-wide lookup, later-plugin override precedence,
  cycle-safe containment and inherited-keyword queries. `RecordTextDump` names both record
  families, direct ALFL quest aliases fill and persist through the additive `QLOC` chunk.
  The real-data gate met census floors of 829 LCTN and 481 LCRT definitions, pinned the Whiterun ->
  Whiterun Hold -> Tamriel chain, and reduced the location-alias skip tally from 892 to 730
  by filling 162 direct locations. See [locations](/formats/locations.md).
* **Form lists preserve order and flatten safely across plugins (issue #452)**: `FormList`
  decodes EDID plus repeating LNAM links, retaining positional nulls and tallying a partial
  tail. `FormListStore` adds resolved-ID and case-insensitive editor-ID lookup over
  `RecordIndex`; whole-list overrides, plugin-relative nested resolution, recursion-stack
  cycle detection, a logged depth cap, and flattened membership keep malformed mods finite.
  `RecordTextDump` prints capped FLST entries and names decoded M18 targets. The active-load-
  order gate measured 1,219 winning lists, a largest list of 308 entries, deepest nesting 2,
  and no null LNAMs; it pins the nested 152-leaf Atronach Forge recipe list. See
  [record decoders](/formats/records.md).
* **Keywords are names rather than hardcoded FormIDs (issue #451)**: `Keyword` and
  `ActionRecord` defensively decode the shared optional EDID plus byte-RGBA CNAM shape,
  tallying malformed and unknown fields. `KeywordStore` layers resolved-ID and
  case-insensitive editor-ID lookup over the cross-plugin `RecordIndex`; `KeywordList`
  resolves a plugin-relative KWDA by name for membership tests and inspector display.
  `RecordTextDump` now decodes KYWD/AACT and prints resolved keyword editor IDs for item
  records when given the store. The real-data gate pins Iron Sword, Iron Cuirass and Gold,
  and measured 843 distinct KWDA identities across the active load order: all 843 resolved,
  with no unresolved tail. See [keywords and actions](/formats/keywords.md).
* **Cross-plugin records now have one load-order-independent index (issue #450)**:
  `RecordIndex` walks requested top groups once per active plugin, resolves raw record IDs
  through each plugin's TES4 MAST list, and keeps the highest-priority valid record under a
  canonical `ResolvedFormID`. Deleted records, malformed field framing, unreadable groups,
  and unreadable plugins preserve the earlier valid definition; the type-specific decode seam
  also falls back past a semantically malformed override. Null FormIDs, unknown source plugins,
  dangling resolved links, and identities whose candidates all fail decoding are distinct
  results instead of zero or an ambiguous optional. The eight M18 families collect 4,093
  records across the five masters in 135 ms before override identities collapse; synthetic
  tests pin precedence, deletion, master remapping, malformed data and skipped plugins, while
  the real-data gate pins the census floors and `ActorTypeNPC`. See
  [FormID + TES4 header](/formats/formid.md).

## 2026-08-12

* **The `.lip` layouts the M17 gate walked past now decode (issue #449)**: three findings,
  each measured across all 74,070 embedded lip blobs rather than inferred from an offset that
  happened to fit. First, the slot stride is carried by the duration field —
  `durationTicks == 4 * slotsPerFrame * frameCount + 28` — so the familiar 132 ticks per frame
  is `4 * 33`, and the 729 creature blobs whose vocabulary is 8 use 32 ticks per frame for an
  8-slot grid. Second, "key tuple width 512" is not a second curve encoding: 4,972 blobs carry
  one or three extra bytes between the frame count and the tuple width, so the tuple width,
  pre-roll and vocabulary sit one or three bytes later; read there they are an ordinary header
  with tuple width 2, and `LIPDecoder` searches for the first tail that is jointly consistent
  with the stride instead of assuming a fixed offset. Third, the `non-finite curve value`
  rejections were a misread, not bad bytes: at the failure the real value sits one byte later,
  and the decoder had lost phase at a `00 <tag> 00` triple. The tag alone cannot decide it —
  requiring `tag % 4 == 0` loses phase on 3,683 blobs and accepting every non-zero tag breaks
  1,828 that decoded before — so the triple is now a choice point resolved by backtracking
  against the whole payload, with multiples of four tried as a suffix first so every blob that
  decoded before decodes identically. Corpus decode went from 61,484 to 70,926 of 74,070; what
  remains is 3,104 blobs with no locatable header tail and 40 that frame to no reading, both
  still typed `LIPError` results. `World > Dialogue & Voice` reports the active line's decoded
  layout in `LipSyncStatsLabel`. See [.lip lip-sync tracks](/formats/lip.md).
* **The push gate compiles the real-data suites (issue #457)**: `make test` selects the
  `UnitTests` plan, which does not carry `openskyRealDataTests`, so a compile break there
  reached `main` and stayed invisible until someone ran `make realtest`. `make realdata-build`
  runs `build-for-testing` on the `RealData` plan — no install needed, no test run — and the
  pre-push hook runs it after `make test` and `make cli`, stamping its own green tree hash so
  the usual run-then-push flow does not pay for it twice. CI gained the same step. The
  `#expect` break the issue was filed for had already been fixed in the M17 landing; this is
  the part that keeps the class of break from landing again.
* **ShaderTypes reaches Swift as a clang module (issue #342)**: `ShaderTypes.h` moved to
  `opensky/SharedHeaders/ShaderTypes/` beside a `module.modulemap` declaring
  `OpenSkyShaderTypes`, `SWIFT_INCLUDE_PATHS` picked the directory up for every target, and
  both `SWIFT_OBJC_BRIDGING_HEADER` settings are gone — `openskycli` no longer borrows the
  app target's header. The 41 Swift files that use a shared type now say
  `import OpenSkyShaderTypes`; removing the bridging header also removed the free
  `import Foundation` and `import simd` it had been giving every file in the project, so
  five more files name `simd` and one names `Foundation` themselves. `Shaders.metal` is
  unchanged.
  The rebuild-blast-radius win the issue predicted did not materialise and the measurement
  is recorded rather than the hope: a `ShaderTypes.h` edit costs 38 seconds at 0 of 40
  cacheable tasks replayed, a one-line edit to an unrelated format parser costs 39 seconds
  at 1 of 40, so no Debug source edit in this project is cheap and the shared header was
  never the outlier. See [Build system](/tools/build-system.md).
* **M17 acceptance: one destination for the whole conversation (issue #209, item 17.8)**:
  the milestone's seven capabilities are now one loop a user can drive from one place.
  `World > Dialogue & Voice` (`Destination-dialogueVoice`) assembles the four sections the
  sub-issues built — Dialogue and its condition trace (17.3), Dialogue Camera (17.4), Voice
  with the playback clock and the lip-sync A/B toggle (17.5, 17.7), Face Morphs (17.6) — in
  the order a conversation uses them. Each section is standalone, so the move was a registry
  edit and changed no control identifier: `AudioVoice*` still names the submix controls
  because they are the UI-test contract. One readout is new,
  `VoiceSourceStatsLabel`, over `WorldAudioEngine.statsSnapshot()` narrowed to the voice
  submix. Decisions, with what was rejected: the sections were **moved** rather than
  duplicated into the new destination, because two live panels holding the same
  accessibility identifiers would break the UI-test contract that makes any of this
  checkable; the destination's override policy lights the dot for an open conversation, a
  forced camera, a scrubbed weight and lip sync switched off, and deliberately does not undo
  said-state or a quest stage, because those are what the milestone produced rather than a
  knob left off its default; and the headless gate drives `GameViewController`'s own entry
  points — the streamer's Talk activation and the `DialogueControlProviding` members the
  panel buttons and the live keys share — rather than re-implementing the conversation state
  machine in the test, which is what a second copy of `chooseDialogueTopic` would have been.
  Honest coverage, measured 2026-08-12 against the shipped masters: 15,037 topics and 31,465
  responses indexed; the pinned speaker is offered 54 topics with 6,481 rejected, 11,622
  conditions evaluated and 7,837 still unanswerable (functions 4167, 4725 and 4702 lead the
  residue); 75,408 `.fuz` entries, of which 74,070 carry a lip blob and 61,484 decode as
  standard tracks; and the gate's own chosen line reached 15 unmapped viseme slots after
  walking past three sibling recordings of the same response — two non-finite curve values,
  one unsupported key tuple width. SCEN playback did not land and is deferred explicitly
  rather than silently. Evidence: `M17AcceptanceTests`, `M17AcceptancePanelTests` and
  `M17AcceptanceBudgetTests` under `make test`; `M17AcceptanceRealDataTests` and
  `M17AcceptanceRenderTests` under `make realtest`, whose run directories are
  `logs/m17-acceptance/<stamp>/` and `logs/test-fast/<stamp>/` — the mouth region moved 717,
  740 and 748 pixels for lip sync off versus on at three times in one line, 725 pixels
  between the first and last of them, and each pair repeated to zero; over one exterior cell
  the dialogue camera moved 131,344 pixels and the vanilla `dialoguemenu.swf` drew 17,572
  over it. The one piece of evidence no test can produce is the audible one: deterministic
  tests cannot hear, and nobody has yet sat in front of the installed app and listened to a
  chosen line. That confirmation is outstanding and is recorded as outstanding rather than
  assumed. One unrelated fix rode along: `LipSyncRealDataTests` could not compile
  its `#expect(... allSatisfy(\.isFinite))` inside a `do`/`catch` under Swift 6.3.3, which
  had left the whole `openskyRealDataTests` bundle unbuildable. See
  [dialogue runtime](/engine/dialogue.md) and
  [sidebar acceptance](/tools/sidebar-acceptance.md).

## 2026-08-11

* **Audio-clock lip sync (issue #208, item 17.7)**: `LIPFile` now defensively decodes the
  24-byte FaceFX header and sparse 33-slot, 30 Hz curve grid embedded in `.fuz` voice lines,
  retaining duplicate, marker, unknown-header and unmapped-slot tallies. Actor-local
  `LipSyncPlayback` samples the source clock, uses a line-anchored one-way wall-clock fallback,
  maps positional slots onto FaceGen TRI speech targets and releases the final pose over
  0.15 seconds. `World > Audio > Voice` exposes a lip-sync toggle and live clock, weight and
  unmapped-slot state. The vanilla gate accounted for all 74,070 lip blobs, decoded 61,484
  standard tracks and classified 12,586 alternate or malformed layouts as typed results;
  three deterministic offscreen A/B timestamps changed 717, 740 and 748 pixels. See
  [FaceFX lip animation](/formats/lip.md) and [dialogue runtime](/engine/dialogue.md).

* **TRI face morphs (issue #207, item 17.6)**: resident actors now carry independent named
  FaceGen expression weights. A defensive `FRTRI003` decoder reads base topology and scaled
  Int16 targets; RACE and HDPT decoding reaches the expression container by matching HDPT
  `EDID` to each baked `BSDynamicTriShape`, with VFS existence, skinning and vertex-count
  guards retaining distinct miss reasons. The CPU composes position and topology-derived
  normal deltas into an actor-local frame-ring stream; morph-capable skinned scene, debug and
  shadow pipelines apply it before bone skinning, while cached meshes remain immutable.
  `World > HUD & Interaction > Face Morphs` selects a target, scrubs its zero-through-one
  weight and reports pairs, misses and unknown names. The real Heimskr gate paired six
  containers with 47 targets; `Aah = 1` changed 708 pixels and repeated exactly. See
  [TRI expressions](/formats/tri.md) and [face morph runtime](/engine/face-morphs.md).

## 2026-08-10

* **Voice playback: `.fuz` framing and a playback clock (item 17.5)**: a chosen dialogue
  response can now be heard. [`FUZFile`](/formats/fuz.md) frames the voice container — the
  `FUZE` header, the optional `.lip` blob, the embedded xWMA stream — and hands the payload
  to the existing `XWMFile` route, so a line streams down exactly the positional path a
  `.xwm` effect takes and `AudioSourceStreamer` never learned a second container. The
  file-name rule was the hard half: the community descriptions of it conflict, so it was
  derived from the install's own 75,408-entry listing with `openskycli audio voice-sweep`,
  which re-derives a name for every INFO response and reports every mismatch beside the
  editor IDs behind it. The two names share one 25-character budget rather than each having
  a fixed cap, which is what no published description gets right; the rule reproduces
  43,753 of 44,325 vanilla names (98.71%), and the residue is Bethesda's — 86 recordings
  whose quest or topic was renamed after export, 486 whose INFO no longer exists. New
  engine capability beside it: `playbackPosition(ofSource:)`, read from the player node's
  own clock so it is deterministic under offline rendering, and `onSourceFinished`, which
  fires only for a source that played out and not for one that was stopped, evicted or
  purged — items 17.3 and 17.7 both need those. World > Audio grows a **Voice** section
  whose picker is a filter over the corpus and whose readout states the true match count
  beside the truncated one.

* **Render debug views and layer isolation (issue #144)**: a visual bug can now be
  bisected instead of stared at. `World > Render Debug` switches the scene pass's output
  channel — wireframe, world normals, texture coordinates, mip level, shadow cascade, layer
  category — and switches whole layers off one at a time. The wiring is function constant to
  gate, uniform field to select: `FunctionConstantDebugView` is false in every shipping
  pipeline, so the debug branch folds away and those fragments generate the code they did
  before, while `FrameUniforms.debugMode` picks the channel with no pipeline rebuild. It has
  to be defined rather than merely absent from the shipping pipelines — Metal aborts
  pipeline validation on a referenced-but-undefined function constant, which is why the
  shipping grass, terrain and water pipelines now specialize their fragments too. Five
  debug pipeline states cover seven modes across five geometry paths, because the channel
  is a uniform and `alphaThreshold ?? 0` lets one static variant serve both the opaque and
  cutout groups. Isolation is one `RenderLayer` OptionSet
  rather than six more booleans beside the enables the renderer already carries; the
  composition rule ("a subsystem enable is the feature switch, the layer mask is the view
  filter, effective visibility is the AND") lives once on `RenderLayerPolicy` and is folded
  once per frame. The scene role is tagged on `RenderPlacement`/`DrawInstance` and not on
  `RenderMesh`, because meshes are shared and cached by VFS path so mesh identity cannot own
  a scene role, and the `.statics` default left every existing construction site alone. The
  shadow pass honours the same mask — a hidden static that still cast a shadow would make
  the tool actively misleading — and solo is derived from the mask rather than stored
  beside it, so the two cannot desynchronise. Neither control persists and neither reaches
  `renderOffscreen` unless a test asks, because a session that starts in wireframe reads as
  a rendering bug and that is the confusion the whole feature exists to remove. LOD level is
  dropped (there is no per-mesh LOD in this engine) and overdraw is deferred (it needs a
  blend-enabled pipeline set whose stencil alternative collides with the SWF layer).
  `RendererSetup.swift` gave up its shadow-pipeline factories to
  `RendererShadowPipelineSetup.swift` to stay inside the file cap. See
  [Render debug views and layer isolation](/rendering/render-debug.md).
* **Plugin load order from plugins.txt (issue #73)**: the engine reads the user's actual
  load order instead of assuming the five vanilla masters. `PluginsTextLocator` finds the
  file the way `GameDataLocator` finds the install — `OPENSKY_PLUGINS_TXT`, then the
  `OpenSkyPluginsText` key in the shared defaults domain, then the layouts a macOS install
  can take: beside the game, under `~/Library/Application Support/Skyrim Special Edition`,
  and inside each Windows compatibility prefix (the Steam Proton prefix beside the install,
  `~/.wine`, CrossOver and Whisky bottles), because there is no native macOS Skyrim SE and
  the game only ever writes this file into its Windows per-user folder. A configured path
  that cannot be read is reported rather than skipped; finding nothing is not a failure, it
  is the vanilla masters, which is what a stock install loads anyway — and is what this
  machine resolves to, having never launched the game (`docs/tools/environment.md`).
  `PluginLoadOrder` now returns a `Resolution` — the ordered entries, where the list came
  from, and which named plugins `Data/` does not hold — with the official masters pinned
  first, `Skyrim.ccc` next, and `*`-starred `plugins.txt` lines in file order; an unstarred
  line is a plugin the user switched off and does not load. The consequence that reaches
  rendering is archive priority: `ArchiveLoadOrder` walks the resolved plugin order rather
  than officials-then-alphabetically, so a mod's `.bsa` overrides the archives of every
  plugin before it. One deliberate deviation from the game, argued in
  `docs/formats/plugins-txt.md`: an archive whose plugin the order does not name is still
  opened, at the bottom, because dropping it would cost a machine with no findable
  plugins.txt every mod archive it can read today. Library > Load Order lists the resolved
  order and Settings gained a plugins.txt group beside the data root, so neither is
  environment-variable-only.

* **Dialogue camera and speaker focus (issue #427, item 17.4)**: a conversation now looks
  like one. While the dialogue menu is open the view frames the speaker's `NPC Head [Head]`
  bone from the side the player is standing on, and the speaker stops walking, turns to face
  the player and has its package suspended; Leave hands all four back. The camera is an
  override on `Renderer.freeFlyCamera` rather than a fourth `CameraMovementMode` — `G` never
  reaches it and the mode underneath never changes — undone at the top of each input frame
  and re-applied at the bottom, because `WalkController` integrates the player's facing out
  of that same pose and a frame simulated against the dialogue pose would turn the player
  round to face themselves. Its framing is derived rather than remembered: `openskycli gmst
  list --prefix f` over the shipped `Skyrim.esm` declares no `fDialogueCamera*`, no
  `fOverShoulder*` and no camera framing setting at all, so the distance comes from the
  player capsule and the projected field of view, and the fill fraction is
  `ThirdPersonCamera`'s rather than a second taste decision. The collision pull-in the two
  cameras share is now one `CameraCollisionProbe`. Speaker focus goes through the
  authorities that already own each thing: `stopActor` for the walk, a new `NPCFacingHold`
  turning in place at the mover's own yaw rate, and an `ActorPackageRuntime` suspension
  latch whose release force-re-selects for the world as it now is. `World > HUD &
  Interaction > Dialogue Camera` is the verification surface, with a force toggle aimed at a
  selected actor so the framing is checkable without a conversation, and a pivot gizmo in
  the M16 overlay registry. See [dialogue runtime](/engine/dialogue.md), "Dialogue camera".
* **One engine-wide string decode policy (issue #72)**: every parser that turns bytes from
  the install into text now shares [one lenient policy](/decisions/string-decoding.md) —
  valid UTF-8 decodes as UTF-8, otherwise windows-1252, otherwise ISO 8859-1 — and that
  chain is total, so decoding a string can no longer fail. Before this, BSA names and VMAD
  script data assumed windows-1252, PEX assumed UTF-8, NIF and the localized string tables
  already had their own fallback chain, and six SWF parsers each carried a private copy of
  the UTF-8-then-CP1252 dance; each site also picked its own failure behavior, so a
  mis-encoded name could take down an archive in one format and be tolerated in another.
  The reasoning for leniency is that a name is not the asset: rejecting a mesh because an
  author's exporter wrote a stray byte into a string table costs far more than mojibake in
  one label, and lookups fold case and separators on both sides, so a wrong-encoding name
  still matches itself. `BinaryReader` string reads take the policy by default and accept
  `TextDecoding.strict(_:)` for the few structural fields whose encoding the format itself
  pins down (Havok ASCII type and version names). Bounds and framing stay strict —
  leniency covers the bytes-to-text step only. Consequently `PexError.invalidString` and
  `ScriptDataError.invalidString` are gone, since nothing can raise them any more. The
  language a localized lookup resolves against is still hardcoded to english; that half
  is now issue #441.

* **Dialogue menu, Talk activation and subtitles (issue #205, item 17.3)**: the player can
  now start a conversation. New [dialogue menu](/engine/dialogue-menu.md) covers the
  player-facing half of M17. A living, non-hostile actor under the crosshair becomes an
  ordinary crosshair target with a new `InteractionAction.talk`, picked by reusing
  `MeleeHitDetector.closestApproach` against actor capsules rather than by putting actors
  into the immutable per-cell collision BVH they move through every frame; the nearest
  solid hit is still the occluder, so a shopkeeper behind a shut door is not a target.
  [Menu mode](/engine/menu-mode.md) gained a per-menu `MenuWorldPolicy`, because vanilla
  dialogue is the one menu that captures input while the world keeps running — voice,
  facing and lip sync all advance on that clock — and a pausing menu opened over a
  conversation still stops the world and hands it back on close. The vanilla
  `dialoguemenu.swf` contract was measured with the new `openskycli swf dialogue-menu`
  probe: zero faults, zero unimplemented opcodes, the `DialogueMenuObj` state vocabulary
  read off the movie rather than pinned to numbers, and `TopicList.SetSelectedTopic`
  measured and deliberately unused because driving it with a row index sends the movie back
  to row 0. Response text resolves out of `.ilstrings` and the DIAL `FULL` and INFO `RNAM`
  row text out of `.strings`, each measured with `--text` against all three tables. The
  HUD's long-reserved `SubtitleTextHolder` is finally driven, and clears on advance and on
  exit until item 17.5's playback clock can time a line. `World > HUD & Interaction >
  Dialogue` is the verification surface, with a condition-trace readout that says why a
  topic the player expected is not listed.

## 2026-08-09

* **Dialogue runtime (issue #426, item 17.2)**: a speaker now has something to say. New
  [dialogue runtime](/engine/dialogue.md) covers the headless half of M17 — which topics a
  speaker offers, which response wins inside each, what choosing one does, and what
  survives a save. Selection gates a topic on its owning quest running (all 15,037 DIAL
  records in `Skyrim.esm` name one), keeps only DATA category 0 for the player's menu,
  evaluates the responses in the file order `DialogueStore` preserves and takes the first
  that passes, skips a say-once line that is already spent, honours the INFO ANAM forced
  speaker, and orders the result by DIAL PNAM priority with a FormID tie-break that is
  ours. Every considered response keeps its `ConditionOutcome` and one of four rejection
  reasons, because item 17.8 has to explain why a line the player expected did not appear.
  Said-state is a new `DialogueRuntimeState` world-state component keyed by the INFO
  record's session-stable key — per response, not per speaker, which is what the Creation
  Kit's say-once wording describes — travelling in the additive `DLGS` chunk
  ([OpenSky save container](/formats/opensky-save.md)). Nothing else persists: the vanilla
  sweep found zero INFO records carrying a PNAM previous-info link against 4,294 carrying
  TCLT links, so branch progression is a pure function of the chosen response. The INFO
  VMAD fragment tail is decoded rather than skipped
  ([Papyrus attachment data](/formats/vmad.md)) — 7,661 tails carrying 8,009 result
  fragments across the five masters, none with a byte left over, its count read as a flag
  population rather than as a stored number — and a chosen response's begin and end
  fragments dispatch through the ordinary Papyrus FIFO, so a quest-stage result reaches
  `QuestRuntime.setStage` along the route the Creation Kit authored rather than through a
  second, dialogue-only path into quest state. Three condition functions came off the
  measured demand list of those records rather than off a guess: `GetIsVoiceType` (6,324
  conditions), `GetIsAliasRef` (5,320) and `IsInDialogueWithPlayer` (428)
  ([conditions](/formats/conditions.md)). The env-gated selection test pins one concrete
  speaker under the plugin-baseline quest state. The fidelity gap that number exposes is
  documented rather than hidden: OpenSky offers every player-facing topic whose conditions
  pass, while the original engine also scopes topics to the speaker's active dialogue
  views, and a link-target filter that looked like the fix was measured and rejected for
  removing genuine top-level topics. No UI: item 17.8 owns the panel.
* **M16 milestone acceptance (issue #203)**: the AI has a sidebar. `World > AI &
  Navigation` (`Destination-aiNavigation`) is the milestone's verification surface and its
  fourth world destination: six sections in the order a session uses them — switch on the
  navmesh, path and detection overlays; choose an actor from a resident-actor popup or by
  pointing the crosshair at one; send it somewhere through 16.4's mover and stop it again;
  read the package its schedule selected and force a re-selection; read every detection pair
  it is part of beside the provenance of every constant in the formula; and make it hostile
  and watch which phase its combat machine is in. One explicit selection binds all six,
  which is what `World > Combat & Physics` cannot do: that panel acts on the nearest
  resident actor, which is right for one opponent in front of you and useless for following
  one named guard through a market. The move control's destination is the crosshair's own
  raycast hit at up to 8,192 units, projected onto the navmesh by the path query — an
  inspection rather than a use key, so it is not gated on a player-controlled camera. Three
  debug overlays that default off are the destination's only overridden-ness; a walked-to
  position, a selected package and an angry actor are world state a user produced on purpose
  and no reset undoes them. The gate itself is one guard living one day through the four
  real runtimes wired in the app's own order: a schedule selects a package off the game
  clock, the destination becomes a navmesh corridor, the mover walks it out of a market and
  through a door into an inn, the perception pass notices a player running at it, the combat
  machine closes and swings to a contact step, loses the player and searches, gives up into a
  *fresh* package selection — the evening one, because the clock moved while it fought — and
  then re-engages the same quarrel and runs at a tenth of its health. Against the install the
  same chain runs over Ysolda's own stack (five distinct packages over twenty-four hours),
  the real Chillfurrow corridor through door `0001633D` (four waypoints, four triangles,
  eight expansions, 31.17 ms offscreen) and detection constants of which ten of twenty-three
  come from plugins rather than OpenSky defaults. The overlay pixel evidence is the real
  navmesh over the user's own cell: 24,178 changed pixels from 545 triangles, and 333 more
  from the corridor's three line segments. The AI adds no frame budget of its own — item
  16.4's 2 ms mover slice is asserted to fit inside the shipping `animationUpdateBudgetMS`
  rather than sitting beside it, which is the constraint M13 set and M14 and M15 honoured.
  Adding the destination took `DestinationRegistry`'s enum body past the type-length cap, so
  the three menu destinations moved to `DestinationRegistryMenus.swift`; the registry is
  still the single registration point. Updated [runtime navigation](/engine/navigation.md),
  [actor package schedules](/engine/package-schedules.md),
  [perception and detection](/engine/detection.md), [the combat loop](/engine/combat.md),
  [the main-app UI framework](/tools/app-ui.md) and
  [the sidebar acceptance ledger](/tools/sidebar-acceptance.md). M16 is closed.

* **Combat AI (issue #424)**: the opponent is no longer a clock. `DevTargetDriver` and
  `CombatLoopRuntimeTarget` are deleted, and `CombatBehaviorMachine` decides instead — one
  fixed-step, per-actor machine that engages when 16.6 detection reports the player,
  approaches to weapon reach through the 16.4 mover, attacks on the shipping
  windup-contact-recovery path, spends a gap with its guard up on a seeded roll, breaks off
  at a fifth of its health and runs along a path away from the player, hunts the position
  detection remembered when it loses them, and gives up into a fresh 16.5 package
  selection. The machine asks for movement and never performs it: 16.4 stays the movement
  authority, and a point no navmesh reaches is a refused request rather than a slide. Combat
  state now derives from who is *engaged* rather than from who is angry, so the music stops
  when a fight ends instead of when the last hostile is killed; `combatBlock(of:)` answers
  for every actor, so an NPC's guard reduces the player's hit through the same pinned 15.4
  formula; `GetCombatState` returns 2 while searching, which is the third documented value
  and the first time it has been reachable; and `StartCombat` and `StopCombat` are installed
  as `Actor` natives, routed through the loop, with a target other than the player a tallied
  failure because this engine simulates no actor-versus-actor fight. Eight actors fight at
  once — the mover's own crowd cap — and what the cap refused is counted rather than
  dropped. Every cadence, probability, threshold and distance is stated as OpenSky's own in
  `CombatBehaviorSettings`, because no record carries one. The `World > Combat & Physics >
  Combat Loop` section lost its spawn and reset buttons with the clock and gained one
  readout line per fighting actor. The Skyrim.esm gate runs a real `GuardWhiterun*` ACHR
  through the whole loop against the player over real Whiterun collision, offscreen, with
  the per-step cost recorded. Updated [the combat loop](/engine/combat.md),
  [the Papyrus VM](/engine/papyrus-vm.md), [conditions](/formats/conditions.md),
  [perception and detection](/engine/detection.md) and
  [the sidebar acceptance ledger](/tools/sidebar-acceptance.md).

* **Perception and detection (issue #202)**: resident actors the AI drives now look and
  listen. A fixed-step, capped, time-sliced pass runs a view cone, an exact line-of-sight
  ray against static collision, and a gait-based noise term for every observer-target pair,
  and accumulates the resulting detection value into a level that reads as unaware,
  suspicious or detected with a remembered investigate position. The formula's shape and its
  ten `fSneak*` constants come from UESP "Skyrim:Sneak" and the install — read with the new
  `openskycli gmst list --prefix`, which settled that UESP's
  `fSneakDistanceAttenuationExponent` and the two equipped-weight settings do not exist as
  GMSTs — while the view cone, the crouch and sprint gait weights, and the accumulation
  rates are stated as OpenSky's own. Light level, muffle, action sounds and both skill
  levels are pinned at documented neutral values and listed as gaps rather than
  approximated. `GetDistance`, `GetLineOfSight` and `GetDetected` register at xEdit's
  indices 1, 27 and 45 over a new `DetectionResolution` seam, with `unavailableDetection` as
  its own tally bucket so an untracked pair never reads as an undetected one. A depth-tested
  cone-and-memory-line overlay joins the 16.3 registry, and the panel seam
  (`DetectionStatsLabel`) waits for the M16 gate. The Skyrim.esm gate pins every load-order
  setting resolving from a plugin and a real `GuardWhiterun*` ACHR moving through all three
  states as the player walks 2800 units toward it across real Whiterun collision. New page:
  [perception and detection](/engine/detection.md); updated
  [conditions](/formats/conditions.md) and [the CLI reference](/tools/cli.md).

* **Actor packages and schedules (issue #201)**: NPC_ records now retain ordered PKID
  stacks and resolve `useAIPackages` through template chains. The bounded PACK decoder reads
  general data, calendar schedules, header conditions, template/public inputs, and
  procedure names without absorbing branch-local CTDAs. Resident actors select the first
  scheduled true package on exact boundaries or within 15 game minutes; `GetDisabled`
  resolves runtime enable overrides over plugin baselines. Deterministic travel, wander,
  sandbox, sleep, and eat machines emit movement/loop commands, with readable current state
  for the future M16 panel. Synthetic tests include a real path query over generated NAVM
  geometry; the Skyrim.esm gate pins 21 reachable packages and four Whiterun residents over
  a full day. New pages: [AI packages](/formats/packages.md) and
  [actor package schedules](/engine/package-schedules.md); updated
  [actor records](/formats/actors.md) and [conditions](/formats/conditions.md).

* **NPC locomotion and path following (issue #423)**: active NPCs now own capped,
  fixed-clock `WalkController` capsules over streamed navmesh corridors, steer and select a
  walk or run gait, cross paired door waypoints, repath once after a bounded stall, and then
  record a give-up. Live actor transforms feed rendering and combat; arrival, give-up, cell
  handoff, and save are the only transform-journal boundaries. Actor capsules now fire the
  existing Papyrus trigger events with their own identity. The app uses observed in-place
  gait clips behind a graph-agnostic drive seam, and `MoveToPointControl` plus readouts form
  the M16 panel contract. Synthetic tests pin corridor, door, trigger, recovery, persistence,
  and cap behavior; real-install tests cover the Chillfurrow exterior-to-interior route and
  the graph-cost decision. Updated pages: [runtime navigation](/engine/navigation.md),
  [actor animation](/engine/actor-animation.md), and [Papyrus VM](/engine/papyrus-vm.md).

* **World-space debug overlay (issue #422)**: the renderer now accepts stable, pluggable
  per-frame sources of colored triangles and polylines, uploads one capped vertex list, and
  draws it through a translucent read-only-depth Metal pass on both drawable and offscreen
  paths. The first source colors resident navmeshes per cell and highlights the latest valid
  path corridor plus waypoint line behind independent default-off toggles. Exact submitted,
  drawn and truncated primitive counts feed the future M16 panel seam. Pure builder tests pin
  vertex colors, topology grouping, registry replacement and cap enforcement; a synthetic
  Metal test proves an offscreen pixel delta. `openskycli screenshot --navmesh-overlay`
  supplies the real-install capture path. Updated page: [runtime navigation](/engine/navigation.md).
* **Dialogue records and store (issue #204)**: DIAL topics now retain priority, owning
  quest/branch, category and authoritative SNAM subtype; marker-opened INFO response runs
  carry flags, links, conditions, subtitles and animation references in file order; VTYP
  supplies voice directory IDs and flags. NPC_ VTCK resolves through the `useTraits`
  template chain, and the group-descending `DialogueStore` indexes topics, INFOs and voice
  types for M17's runtime. The vanilla sweep pinned 19,844 DIAL, 41,188 INFO and 183 VTYP
  records across the five masters with zero decode failures. It also corrected the issue
  pointer: shipped INFO NAM1 subtitles resolve through ILSTRINGS, matching UESP, not
  DLSTRINGS. New page: [dialogue records](/formats/dialogue.md); updated
  [actor records](/formats/actors.md).

* **Resident navmesh pathfinding (issue #200)**: cell scenes now carry their decoded NAVM
  geometry into a streamer-reconciled runtime graph. Bounded feet projection feeds a
  deterministic triangle A-star; radius-reduced portals feed the funnel; paired XTEL doors
  split it into explicit crossings with reference and waypoint index. Corridor cell
  sequences and target tolerance invalidate stale results, while the named two-per-frame
  budget bounds queued replacement work. Synthetic coverage includes grids, cross-cell
  links, doors, malformed geometry, misses, unloads and repeatability. A real-install probe
  found the named Whiterun-hold-to-Chillfurrow route and the exterior-to-interior farm door
  route, including the expected `0001633D` crossing. New page:
  [runtime navigation](/engine/navigation.md).

## 2026-08-08

* **NAVM and NAVI navmesh decode (issue #199)**: the first item of M16 (AI). `NVNM`
  geometry — vertices, triangles with per-edge neighbours and flags, edge links into
  neighbouring navmeshes, and door links — plus the `NAVI` index map that says which
  navmeshes exist, where each one is, and which link to which. New page:
  [navmesh records](/formats/navmesh.md); also updated
  [record decoders](/formats/records.md).

  **The parent-cell union needed settling between the two sources.** The four bytes after
  the parent worldspace are either a CELL FormID or a pair of grid coordinates, and UESP
  says the switch is the worldspace equalling `0x0000003C` while xEdit switches on the
  worldspace being null. UESP's rule cannot generalise past Tamriel, so the decoder
  implements xEdit's, and the census probe checks it three ways on real data: the parent
  the payload decodes to against the CELL the record was found under, and against the NVMI
  entry NAVI holds for the same navmesh. All three agree across the Whiterun target area.

  **Geometry is not in the store.** `NavmeshIndex` holds the NAVI side only — FormID to
  entry, location to navmeshes, the NVSI deletion set — and is built once in
  `CellProviderIndexes` beside the other record indexes. A navmesh's vertices and triangles
  come from its own cell through `CellSceneBuilder.collectNavmeshes`, which is the other
  half of the deliberate NAVM skip in `collectTaggedReferences` and stays off the scene
  build path: nothing rendered or collided reads a navmesh, so the streamer should not pay
  the whole payload on every cell build. The pathing graph (16.2, issue #200) pairs the two.

  **Out-of-range is a decode error, not a later crash.** Every count is checked against the
  bytes actually remaining before it sizes an allocation, and every local vertex, triangle,
  door, cover and grid index is range-checked at decode time — including the case where a
  triangle's edge flag redirects its neighbour value from the triangle array to the
  edge-link array. Cover data, the navmesh-grid squares, the NVMI island block and NAVI's
  NVPP are skipped, each named and tallied rather than silently dropped.

  **The census corrected the decoder once.** An edge link's triangle index is not a local
  triangle: range-checking it against the mesh carrying the link rejected more than half the
  vanilla navmeshes in the target area, always on that field, with values far past the local
  count. It indexes the navmesh the link names instead — xEdit agrees by omission, giving
  the door link's triangle a `wbTriangleLinksTo` callback and this one none — so nothing
  local can check it and the decoder no longer tries. Everything else in the target area
  decoded clean on the first pass.

  Nothing draws a navmesh yet (16.3, issue #422); the verification surface for now is the
  Asset Browser detail pane and `openskycli record`, which print a decoded summary for
  `NAVM` and `NAVI` like they already do for the other decoded record types.

* **The real-data suites are their own test target (issue #418)**: `openskyRealDataTests`
  now holds every env-gated suite and nothing else, so `Config/RealData.xctestplan` selects
  it the one way plan-level selection actually works — by target. That deleted the plan's
  57-entry `selectedTests` list, the loop in `tools/realtest.sh` that re-emitted it as one
  `-only-testing` flag per suite, and the lint that kept the list spelled right, all of which
  existed only because a plan cannot select Swift Testing tests. The unit compile lost 56
  files and 14 820 lines it was paying for on every `make test` and every incremental
  `make test-fast` rebuild, for suites that skip without a data root. What replaces the list
  is `openskyTestSupport/`, a folder compiled into both unit bundles, holding the 38 shared
  fixtures — the same mechanism that shares `opensky/Engine/` between the app and
  `openskycli`. Updated pages: [testing setup](/testing.md).

  **Three fixtures were split, not renamed.** `CellSceneBuilderTests`, `CellStreamerTests`
  and `PapyrusWorldActivationTests` were suites doubling as fixtures, extended across ten to
  nineteen files each, and the real-data suites reach them. The alternative — renaming the
  fixture half — would have touched every call site and changed the test identifiers of
  suites that have nothing to do with this change. Instead the type declaration and its
  reusable members moved to `openskyTestSupport/` and the `@Test` methods stayed behind as an
  extension of the same type, which is a shape the files were already written in. No call
  site moved and no test identifier changed. The one member `private` inside the old single
  file had to widen, which is the seam the new `openskyTestSupport/AGENTS.md` warns about.
  `M10AcceptanceTests` needed less: its shared part was six constants, so they became
  `M10AcceptanceClock` and the suite was left alone — a suite type cannot be the `enum`
  SwiftFormat rewrites an all-static `struct` into.

* **M15 accepted — the player fights, kills, loots and reloads (issue #198)**: the milestone
  gate wires, verifies and records what the other eight items built. The route is one
  continuous fight and it enters the engine where a player does — real key *and mouse* events
  reach a real `GameMetalView`, which fills the shipping `CameraInputState`, which each frame
  becomes a `CameraInput` for `LocomotionBridge.acceptFrame`, `WalkController.update` and the
  four combat runtimes, in the order `Renderer.advanceCamera` and the `GameViewController`
  satellites run them. The arena under it is synthetic (a floor, a wall, one crate of movable
  clutter), the graph over it is an eleven-state machine wired to the census names the three
  name sets declare, and the whole thing runs headless with no device and no install.
  Sub-issues: [#192](https://github.com/jjgroenendijk/opensky/issues/192) Havok dynamics data
  and the census, [#193](https://github.com/jjgroenendijk/opensky/issues/193) dynamic
  rigid-body simulation, [#194](https://github.com/jjgroenendijk/opensky/issues/194) the actor
  gameplay entity and actor values, [#195](https://github.com/jjgroenendijk/opensky/issues/195)
  melee, [#196](https://github.com/jjgroenendijk/opensky/issues/196) archery and projectiles,
  [#197](https://github.com/jjgroenendijk/opensky/issues/197) death and the constraint-solved
  ragdoll, [#374](https://github.com/jjgroenendijk/opensky/issues/374) the combat loop and dev
  target, [#375](https://github.com/jjgroenendijk/opensky/issues/375) the Papyrus `Actor`
  natives and combat conditions. Updated pages: [combat loop](/engine/combat.md),
  [actor values](/engine/actor-values.md), [melee combat](/engine/melee-combat.md),
  [archery](/engine/archery.md), [ragdoll](/engine/ragdoll.md),
  [dynamic bodies](/engine/dynamic-bodies.md),
  [sidebar acceptance](/tools/sidebar-acceptance.md).

  **The graph fires the fight, not the test.** Every contact frame, nock, release and ragdoll
  hand-off in the route is a *clip trigger* coming back out of a behavior graph on its own
  clock, exactly as a vanilla annotation does. The rejected alternative was handing the
  runtimes the event names directly, which is what the per-item suites do and is right there:
  it proves each runtime and proves nothing about the seam between them and the animation.
  Writing it the other way turned the gate into an integration of eight items rather than
  eight unit tests run in a row, and it immediately made a documented engine rule load-bearing
  — one update fires one transition, so an event raised on the very frame another transition
  completes is dropped. A combat route presses far more often than a locomotion one, so every
  step now lets the previous clip hand back before it presses anything (`settleGraph`). That
  is the route being deterministic about a known rule, not a workaround for a defect.

  **Two graphs, because an event has to reach the right actor.** The player's graph is
  attached to the bridge and the opponent's is stepped beside it. A stagger raised on the
  opponent has to be taken by the opponent and by nobody else, and that is a claim only a
  second graph can carry; the route asserts the player never enters the stagger or the death
  state. The rejected alternative — one graph and a target parameter — would have made the
  seam untestable in exactly the place it matters.

  **Decisions worth the record.** Full constraint-solved ragdolls over a simplified
  spring-per-bone approximation, because the vanilla skeletons carry real `bhkRagdollConstraint`
  and `bhkLimitedHingeConstraint` limits and an approximation would have thrown away data
  already decoded. The dev target over early AI, because perception, packages and pathing are
  M16's and half an AI here would have put a second, worse decision layer in the engine for
  M16 to remove. A sequential-impulse solver on the same fixed step the walk controller uses,
  rather than a second clock, so a stalled frame has one clamp and not four. And the
  transient-persistence policy: hostility and death are components and survive a save, while
  arrows in flight and corpses still falling are dropped on the way out, because a fight saved
  mid-swing has to reload consistently rather than reload with an arrow frozen in the air.

  **The surface is `World > Combat & Physics`** (`Destination-combatPhysics`): actor values
  with damage and restore controls, weapon and attack state with the hit trace, projectile
  spawn and trajectory readouts, the ragdoll trigger, hostility and dev-target controls, and
  physics freeze and reset with body counts — the whole loop drivable without knowing a key or
  a CLI command. Melee, Archery and Death & Ragdoll moved here from
  `World > Player & Locomotion`, which is what items 15.4, 15.5 and 15.6 each said would decide
  their home once the combat surface outgrew that panel; their readout ids moved with them
  (`LocomotionMeleeStatsLabel` to `CombatMeleeStatsLabel`, and its two siblings), and the
  ledger rows are rewritten rather than left pointing at a path that no longer exists.

  *Evidence:* `M15AcceptanceTests` (the fight, its exact repetition, and the paused frame that
  advances no part of it), `M15AcceptancePanelTests` (the destination as one surface on one
  provider set), `M15AcceptanceBudgetTests` (the shipping `validatedFlyUpdateBudgets` over the
  same benchmark configuration, the four fixed-step clocks' stall bounds, and the 15.2 clutter
  and 15.6 repeated-collapse stresses), `CombatPhysicsPanelTests`, `CombatMeleePanelTests`,
  `CombatArcheryPanelTests`, `CombatRagdollPanelTests`, `DestinationRegistryTests` and
  `AppSidebarModelTests` (the id and registry contracts), `M15AcceptanceRealDataTests`
  (env-gated, device-free) and `M15AcceptanceRenderTests` (env-gated and device-gated).

  **Honest coverage on the local install, 2026-08-08.** Over the vanilla `0_master.hkx`: all
  44 combat, archery and ragdoll event names and all 8 variables declared, zero unresolved;
  361 updates driving 3,062 generator and 3,219 modifier evaluations; zero unevaluated
  generators, zero partial generators, zero unresolved clips, zero unapplied bindings, zero
  undecodable objects, zero feature gaps and zero crashes. What is still owed is semantics
  rather than decode: pass-through modifiers `BSSpeedSamplerModifier` 361,
  `hkbKeyframeBonesModifier` 361 and `hkbEvaluateExpressionModifier` 173. The M14 close-out
  named two modifiers as M15's to implement rather than tally; one of them,
  `hkbRigidBodyRagdollControlsModifier`, now records zero pass-throughs because item 15.6
  reads its `m_durationToBlend`, and the other, `hkbKeyframeBonesModifier`, is still a
  pass-through and is stated as such rather than quietly closed. Condition functions
  implemented: 14. Motion systems simulated: `dynamic`, `sphereInertia`, `sphereStabilized`,
  `boxInertia`, `boxStabilized`, `thinBox`; not simulated: `invalid`, `keyframed`, `fixed`,
  `character`. Constraint classes decoded: all seven `bhk` classes the census names. Pixels,
  same run: drawing the weapon moved 44,872 changed pixels against idle, the swing moved
  48,002 against the drawn stance, and a second player driven through the identical sequence
  from a fresh graph drew a byte-identical frame (0 changed pixels). Two of the four pixel axes
  the issue names are *not* covered and the reason is the engine rather than the suite: an
  arrow in flight has no drawn representation (only the stuck arrow it becomes does, through a
  cell rebuild), and a ragdoll collapse reaches the renderer through `RenderScene.ragdollPoses`
  keyed by an ACHR, which the player rig is not. Both are covered by numbers in
  `M15AcceptanceTests` instead — the arrow's whole trajectory, and the ragdoll's spawn, settle
  and resting pose — which is what the sidebar-acceptance convention makes pixel evidence
  optional for.
* **The test loop got its overhead back (issue #417)**: `make test-fast` and the rewired
  `make realtest` split `build-for-testing` from `test-without-building`, so a warm rerun of
  one test costs 4–17 s instead of the ~80–85 s that session mining measured per invocation
  — overhead that was the single largest wall-clock cost of fixing an issue, with the same
  test re-run four to eleven times while iterating. The `.xctestrun` regenerates off an
  mtime sweep of sources, `Config/`, the project file, and `.vendor/ffmpeg`; the RealData
  root rides in it verbatim, so a gated test passes with no env injection. The per-run
  `-enumerate-tests` selector validation is gone — an entire extra xcodebuild invocation per
  single-test run — replaced by the post-run result-bundle count plus near-match suggestions
  from a cached enumeration on the failure path only. The pre-push hook now skips its
  `make test` + `make cli` rerun when both stamped the byte-identical tree green
  (`tools/green-stamp.sh`); a dirty tree or any content change runs the full gate. What
  issue #82 retired comes back without the fragile part: no `.xctestrun` rewriting, because
  plan environment entries land in it already. Follow-up filed as issue #418 (move the
  real-data suites to their own target). Updated pages: [testing](/testing.md),
  [local environment](/tools/environment.md) (Xcode 26.6 `-enumerate-tests` flag limits,
  `.xctestrun` naming and layout).

* **Ragdoll self-collision is back, from the biped filter bits (issue #413, split from
  #407)**: a corpse's arms no longer pass through its own torso. Updated pages:
  [ragdoll](/engine/ragdoll.md), [NIF collision](/formats/nif-collision.md).

  **The bits are a reading, not a guess.** nif.xml's `CollisionFilterFlags` puts a
  `BipedPart` in the low five bits of the `HavokFilter` flags byte and says they mean a part
  only on layers 8, 32 and 33. The vanilla humanoid confirms it rather than merely permitting
  it: all eighteen bodies are on layer 8 in group 0, and every part number lands on the
  anatomically correct enum name — `P_HEAD` on the head, `P_L_CALF` on the left calf,
  `P_R_FOOT` on the right foot, through all sixteen distinct values. A mask read at the wrong
  width or offset would still produce numbers; it would not produce that anatomy, and
  `RagdollSelfCollisionRealDataTests` asserts it bone by bone.

  **What Havok does with the parts is stated, because Havok does not publish it.** A pair is
  admitted when both bodies carry a part, neither is `No Collision`, the parts differ, and
  the two are more than two joints apart in the ragdoll's own joint graph. The third rule
  earns its place on real data — `NPC COM` and `NPC Spine` both read `P_BODY` and are the
  second-deepest overlap in the skeleton. The fourth is a graph distance rather than a
  hard-coded humanoid table on purpose: one hop is what a constraint means, two hops is the
  pair a shared parent holds together, and deriving it from the constraint data means a
  dragon or a mod's creature is filtered without anyone writing its anatomy down. The result
  is 116 of 153 pairs admitted and **none of the 24 that already overlap at the bind pose**,
  which is why the thirty-to-forty-five standing contacts that made 15.6 switch the whole
  thing off cannot occur.

  **It exposed a settling gap that predates it.** A ragdoll reaches rest by either the
  coordinated route, which checks every joint first, or 15.2's ordinary per-body sleep, which
  asks nothing about them — and once every bone is asleep nothing solves a joint again. With
  bones ignoring each other there was never anything left to hold one open at the end of a
  fall; a self-collision contact can, and the vanilla left elbow rested three units and six
  degrees open. `RagdollInstance` now makes its final pose-only projection on arrival at rest
  by either route, repeating until every joint is inside half the settling thresholds. That
  elbow now rests at 0.14 units and 1.7 degrees, and the sixty-collapse stability gate is
  unchanged.

* **Scripts can now ask an actor how it is doing (issue #375, roadmap item 15.8)**: nine
  `Actor` natives, three script events, five condition functions, and the CTDA combat-target
  run-on that had been unresolvable since #251. Updated pages:
  [Papyrus VM](/engine/papyrus-vm.md), [conditions](/formats/conditions.md),
  [combat loop](/engine/combat.md), [actor values](/engine/actor-values.md).

  **Two surfaces, one death path.** The acceptance gate asks that `DamageActorValue` kill at
  zero, that `Kill` route the same way, and that `OnDeath` fire exactly once. The tempting
  shape — have the natives write `ActorDeathState` themselves — would have produced a second
  death path that never spawns a ragdoll and never raises the census-named graph events,
  while the 15.6 per-frame sweep silently stopped noticing corpses it had not made. So both
  natives empty health through `ActorValueRuntime` and then call
  `RagdollRuntime.noteZeroHealth(of:killer:)`, which is where the latch already lived.
  Exactly-once falls out of that latch rather than out of a second set kept beside it, and a
  sword, an arrow, a sidebar button and a script now make identical corpses. `Kill` empties
  health *before* killing for a reason a player can see: a corpse at full health would draw
  a live HUD bar over a body and make `GetActorValue("Health")` disagree with `IsDead()`.

  **`SetActorValue` is not implemented, on purpose.** The Creation Kit wiki is explicit that
  it sets the *base* value and leaves modifiers intact, and that "While GetActorValue returns
  the current value, SetActorValue sets the base value." OpenSky re-derives maximums from
  RACE, CLAS and NPC_ on every read precisely so a save cannot carry a number a changed load
  order no longer authors, so there is no base-override store to write. The only thing it
  could have written is the current value, which is `ForceActorValue`'s job — every "buff
  this NPC's max health" script would silently have moved its current health instead. It
  stays an unimplemented native, counted by name in the tally, until a base override exists.
  `ModActorValue`, `ForceActorValue`, `Resurrect`, `StartCombat` and `StopCombat` are absent
  for their own stated reasons.

  **The actor-value table was copied, not remembered.** Both new surfaces address actor
  values by vanilla identity — a signed index in a CTDA parameter, a name string in a
  Papyrus argument — so `ActorValueIdentity` holds xEdit's `wbActorValueEnum` verbatim,
  `Unknown NN` placeholders included, because renumbering around a gap would put every later
  index one off. Health is 24, magicka 25 and stamina 26 because dev-4.1.6
  `Core/wbDefinitionsTES5.pas` says so. 15.3 stores three of the 164 entries; the other 161
  are real actor values with no store, and each miss is tallied by name rather than answered
  with a zero, which makes the tally the list of what to store next.

  **`IsWeaponOut` is not a bool.** The Creation Kit wiki documents three returns — 0 nothing
  drawn, 1 fists only, 2 a weapon in either hand — and OpenSky produces 0 and 2 and never 1,
  because the melee runtime tracks where the weapon *is* rather than whether the actor is
  unarmed while it is out. An actor whose draw state nothing observes, which is every actor
  but the player, reports the gap instead of answering "sheathed": that is a fact about an
  actor and nothing in this engine knows it. `GetCombatState` is the same shape — 2
  "Searching" needs perception, so M16 will make it reachable and until then it is stated
  rather than faked.

  **Run-on type 3 resolves per subject, not per session.** The obvious reading — "the combat
  target is `CombatLoopState.target`" — would give an NPC's condition the *player's* target.
  A CTDA asks about the combat target of the object it runs against, so the actor seam
  carries one per actor and 15.7's model fills both directions: the player fights the nearest
  hostile living actor, and every hostile living actor fights the player. Both sides of a
  fight therefore evaluate, and a corpse fights nobody.

* **Settled ragdolls stop moving at the solver (issue #407)**: a ragdoll's floor contacts
  and joints now run as one sixteen-iteration velocity solve, alternating their order while
  keeping both families' accumulated impulses for the whole substep. The old four-contact-
  then-eight-joint order always let the joints reopen the floor solution, leaving hands,
  feet, and the head at thirty to fifty engine units a second and creeping the corpse until
  the whole-body settling window intervened. Both the synthetic limb and the vanilla
  humanoid now reach the ordinary per-body sleep thresholds without that workaround.
  Sleeping bones also refuse later joint impulses and pose corrections, matching the
  contact solver's existing invariant. The coordinated whole-ragdoll settling check remains
  as a persistence safety net for uneven geometry, but now waits for the documented pivot
  and angular-limit bounds before freezing the pose. Biped-filtered self-collision is separate
  follow-up [issue #413](https://github.com/jjgroenendijk/opensky/issues/413).
* **The pieces became a fight (issue #374, roadmap item 15.7)**: hostility, derived combat
  state, an opponent that attacks back, reactions in both directions, bounds on everything a
  fight spawns, and the combat-music edge M9 left a seam for. New page:
  [combat loop](/engine/combat.md).

  **The opponent is a clock, and the code says so.** NPCs are render-only with single-clip
  playback and carry no behavior graph, so a real opponent — perception, packages, pathing —
  is M16's. `DevTargetDriver` is therefore a fixed-interval phase machine that attacks from
  wherever it stands at whatever is in front of it, and `CombatLoopRuntimeTarget.swift` is
  named as the file M16 replaces. What it does do is go through the shipping paths: the 15.4
  swept-capsule hit volume, the 15.4 block-and-damage formula, and the 15.3 actor-value
  store, so everything downstream of "an opponent hit the player" is already the real thing.
  Two stand-in behaviours are written down rather than hidden — it turns to face the player
  at the contact step, because a placement facing points where the level designer aimed it
  and never at whoever walked in, and it never moves, so a player who steps back is safe
  permanently.

  **Combat state is derived, not stored.** "In combat" is *some resident actor is hostile
  and alive*, recomputed every fixed step from the same actor list the fight runs over; the
  current target is the nearest of those, ties broken on the lower `ReferenceKey`. A stored
  flag would have to be cleared by a death, a cell unload and a panel toggle, and the one
  that was forgotten would leave the player permanently in combat with a corpse. Hostility
  itself *is* stored, as its own `ActorCombatState` component with a `neutral`/`hostile`
  enum and no `dead` case — death is already `ActorDeathState.isDead` and a second spelling
  of one fact is a second thing to keep in agreement. It persists in a new additive `CBTS`
  save chunk, split out of `RDLT` for the reason `AVAL` and `DETH` were: a component kind
  inside `RDLT` is versioned by `formatVersion`, so an older build would refuse every save
  containing a fight rather than load the rest of the world.

  **The hit reaction was read, not guessed.** The census over the user's own install was
  re-run for this item; the third-person `0_master.hkx` declares `recoilStart`, `recoilStop`
  and `recoilLargeStart` as events and `IsRecoiling` and `recoilMagnitude` as variables, so
  a blow on the player writes the magnitude and then raises `recoilStart`, in that order.
  `recoilLargeStart` stays unraised: which magnitude selects the heavier variant is a
  threshold no open source states. The same census supplied the three reaction clip paths,
  and settled one substitution honestly — there is no unarmed stagger clip anywhere in the
  set, every `staggerback` variant being prefixed by a weapon class, so an unarmed stand-in
  plays `1hm_staggerbacksmall.hkx`. `ActorAnimationPlayback` grew a bounded clip override to
  play any of them and return to idle, and its loader moved to
  `ActorAnimationClipLoader` where a second caller can reach it.

  **Everything a fight spawns is now bounded.** Arrows in flight (12), arrows standing (32),
  corpses simulating (8) and dynamic bodies awake (64), each enforced every step. The
  numbers are OpenSky's — vanilla's live in its code, not in any record — and are taken from
  what the 15.2 clutter stress and the 15.6 collapse stress actually carry. Trim order
  differs per population because only two of the three registries know what "oldest" means:
  projectiles and ragdolls are appended to in spawn order, while a dynamic body is placed by
  its cell build and carries no spawn time, so the awake cap sleeps them in `ReferenceKey`
  order. No cap deletes what a player is looking at — a trimmed corpse keeps the resting
  transform its death state recorded and a slept body keeps its pose, so the cap costs
  motion, not position.

  **Combat music took the seam M9 shaped for it.** `MusicState` gained its `combat` case and
  is the one state not derived from the streamer's context: entering combat selects the
  first `MUSCombat...` record directly, by FormID for determinism, and remembers the
  selection it interrupted; leaving restores exactly that rather than re-resolving, so a
  fight that started in a town ends in the town's playlist. A cell crossed mid-fight updates
  the return target instead of interrupting the fight, and a load order with no combat
  playlist leaves the music alone and says why.

  Evidence: `CombatLoopRuntimeTests` drives the whole synthetic fight headless — provoking,
  the opponent's blow, the blocked blow against the pinned formula, the out-of-reach miss,
  the magnitude-before-recoil order, the death that ends combat, the music edge, the caps,
  and what a save drops — plus `DevTargetDriverTests` on the phase machine and its
  determinism, `CombatLoopStateTests` and `CombatTransientLimitsTests` on the pure values,
  `CombatHostilitySaveTests` on the `CBTS` round trip and its older-build tolerance, and
  `WorldMusicCombatTests` on the music edge. `HKBBehaviorCensusRealDataTests` was re-run
  against the install for the event and clip names, and `CombatLoopRealDataTests` closes the
  loop on the install itself: the vanilla player graph declares all four recoil names, all
  three reaction clips decode against a real character skeleton, and one fixed step over 32
  resident actors costs **0.0380 ms** against a 0.1 ms budget
  (`logs/combat-loop-budget.log`, 2026-08-08).
* **Dynamic bodies follow the exterior cell they occupy (issue #401)**: each body now keeps
  its immutable placing cell beside a fixed-step-updated occupied cell. Residency retires
  it with the latter, so clutter pushed across a boundary continues simulating after its
  source cell unloads. The cell composition detaches that reference's tagged draw instances
  and merges them exactly once under the occupied cell without retaining the source cell's
  terrain or other geometry. Resting transforms remain world-space and are journalled under
  the authoritative placing cell, including while that cell is absent.
  [Dynamic rigid bodies](/engine/dynamic-bodies.md).

## 2026-08-07

* **The hand-type encoding, settled from the install (issue #403)**: `iRightHandType` and
  `iLeftHandType` are now written, so drawing a sword plays the sword's own equip animation
  and the attack states behind it become reachable.

  **The encoding was read, not guessed.** The M14 census gave both variables their names and
  their `int32` type and nothing else, so item 15.4 deliberately left them unwritten rather
  than pick a number. Three independent readings out of
  `meshes\actors\character\behaviors\` agree on the thirteen values: `weapequip.hkx` binds
  `hkbManualSelectorGenerator::m_selectedGeneratorIndex` straight to the variable, so the
  child list of `Weap_Equip_MSG` is the encoding in order (1 `1HM_Equip.hkx`, 2
  `Dag_Equip.hkx`, 3 `Axe_Equip.hkx`, 4 `Mac_Equip.hkx`, 5 `2HC_Equip.hkx`, 6
  `2HW_Equip.hkx`, 7 `Bow_Equip.hkx`, 8 `Stf_Equip.hkx`, 12 `DLC01\CrossBow_Equip.hkx`);
  `0_master.hkx` names the same values as the state ids of its `MT_LeftHandOverride` machine,
  which is where 9 spell, 10 shield and 11 torch come from; and the transition conditions in
  `1hm_behavior.hkx` and `magicbehavior.hkx` agree wherever they overlap. It is **not** the
  WEAP DNAM animation type: DNAM spells crossbow 9 and the graph spells spell 9 and crossbow
  12, so `CombatHandType.init(weapon:)` is a conversion rather than a cast.

  **Two other things had to be true before the draw ran.** `weaponDraw` is declared by the
  graph but named by no transition in any character behavior file — in vanilla it is the
  intent and the engine decides what it equips — so the runtime now raises `WeapEquip`,
  `Magic_Equip` or `Unequip` beside it, which is what `0_master.hkx` actually transitions on.
  And an annotation authored at a clip's first frame could never fire, because the crossing
  test was half-open on the update that seeded the clip; `1HM_Equip.hkx` carries
  `BeginWeaponDraw` at 0.0, so that update now covers the closed interval. Five of the equip
  clips carry no such annotation at all, so `WeapEquip_Out` and `Unequip_Out` are observed as
  the backstop.

  Verified headless against the local install: the graph runs `1HM_Equip.hkx`, fires
  `BeginWeaponDraw`, reaches `Weap_Readied_State`, and answers `attackStart` with a
  `HitFrame` the sweep runs on. The `World > Player & Locomotion > Melee` readout gained a
  hands line naming each hand and its number.
  [Melee combat](/engine/melee-combat.md), [behavior graph runtime](/engine/behavior-runtime.md).
* **Death and constraint-solved ragdoll (issue #197)**: an actor whose health reaches zero
  raises the death events its graph declares, hands its skeleton to the physics on the
  graph's own hand-off frame, and collapses under a joint solver running inside the 15.2
  fixed step. The simulated bones write back through the pose path the skinning palette
  already reads, the corpse settles, its resting transform persists across a save, and
  activating it opens a container over its inventory.

  **The solver is sequential impulse, and position-based dynamics was the alternative it
  beat.** XPBD is more forgiving of a stiff eighteen-bone chain at low iteration counts and
  was seriously considered; it lost because the contact solver 15.2 shipped is already
  sequential-impulse with position-level recovery, and a ragdoll bone is in contact with the
  floor and jointed to its neighbour in the same substep. Two solver families over one set
  of velocities means each undoes part of the other's work every iteration.

  **Two readings of the authored constraint angles were settled by measuring the vanilla
  humanoid at its bind pose, not by reasoning.** The direction the roll is measured in runs
  from body B's reference axis to body A's: that puts all four hinge kinds inside their
  authored ranges — knee -0.054 in `[-1.920, 0]`, ankle -0.498 in `[-0.596, 0.063]`, elbow
  +0.019 in `[0, 1.920]`, wrist -0.060 in `[-0.087, 0.349]` — where the opposite direction
  puts three of the four outside, the ankle by 0.44 radians. And `maxFriction` is read as a
  rate rather than a torque, because the humanoid authors exactly two values across its
  seventeen joints (10.0 on every cone, 0.01 on every hinge) and there is no distribution to
  infer a unit from. The bind pose is otherwise very nearly satisfied — every cone and plane
  angle under 0.08 radians, pivots coincident on fourteen of seventeen joints — which is the
  evidence the frame mapping is right; the other three carry authored slack, symmetric left
  and right.

  **Three stability findings, each from the real-data probe rather than from taste.** A
  restoring bias on an angular limit is the Baumgarte term the contact solver already
  refuses, and it pumped a corpse from 20 to 52 engine units a second over thirty seconds
  with one ankle violation growing from 0.27 to 1.77 radians; recovery moved to the poses.
  The pose corrections need several passes to propagate down a six-link chain — with one
  pass the knees sat seven units apart forever — but must accumulate and be applied once,
  because applying each pass in turn spends the whole clamp budget several times over and
  does work against gravity. And a ragdoll's bones cannot collide with each other: eighteen
  capsules of eighteen-unit radius on twenty-unit bones overlap by construction, and a
  corpse lying still carried thirty to forty-five contacts and jittered forever until
  self-collision came out.

  **A ragdoll settles on displacement, not velocity.** 15.2's per-body sleep test never
  fires on a jointed chain: a corpse that has visibly stopped still carries thirty to fifty
  units a second in its hands and feet, and a corpse that never sleeps is never persisted.
  The root travelling less than three units in a second now sleeps the whole ragdoll, which
  is what a viewer means by stopped. The residual itself is issue #407.

  **Persistence records the resting root transform and not the per-bone pose**, in its own
  additive `DETH` save chunk. The visual cost is stated rather than hidden: a corpse reloads
  lying where it came to rest in the skeleton's rest pose, not in the tangle it died in.

  `hkbRigidBodyRagdollControlsModifier` stops being a pass-through and publishes its
  `m_durationToBlend` as the hand-off's blend; `hkbPoweredRagdollControlsModifier` and
  `BSRagdollContactListenerModifier` stay pass-through, both out of this item's scope.
  Real data: the vanilla humanoid resolves 18 bones and 17 joints with nothing skipped, and
  collapses onto a floor and settles with every constraint resolved.
  [Death and constraint-solved ragdoll](/engine/ragdoll.md).
* **Compilation caching is on (issue #341)**: `COMPILATION_CACHE_ENABLE_CACHING = YES` in
  `Config/Base.xcconfig`, adopted on measurement rather than on the feature description. It
  pays for exactly one flow, and pays for it well: a Debug rebuild of a state this checkout
  has compiled before with the intermediates gone drops from 45.1 to 9.8 seconds, with 106
  cache hits and no misses, and the same rebuild in Release — `make install` after a
  `make clean` — drops from 779.8 seconds to 29.5, since a whole-module compile has nothing
  incremental to fall back on. It buys nothing on a branch switch in place, nothing for `make cli`
  after `make build`, and nothing measurable on an ordinary one-file edit; a cold populating
  build costs one to two percent more. A second worktree pointed at a warm store hits only
  SDK module builds, because a project source task's key embeds its absolute path and Xcode
  emits no prefix mapping, so the store is deliberately not shared between worktrees. The
  store lands in `DerivedData/CompilationCache.noindex` on its own, which is already the
  external volume, and `make clean` now keeps that directory while removing the rest —
  without which the fast flow would never occur, since a clean was the main reason the
  intermediates ever disappeared. `make clean DEEP=1` drops it too. Full table of measured
  flows in [Build system and xcodebuild invocation](/tools/build-system.md).

* **Archery and projectiles (issue #196)**: a shot from the held mouse button to the arrow
  standing in the wall. `PROJ` is parsed — the milestone's one new ESM record — a bow is
  drawn and loosed through census-named graph events, and the arrow it launches flies on the
  same fixed step every dynamic body does, sweeps what it passes through, takes health off
  what it hits, and is left standing there.

  **What PROJ `gravity` means was measured, not assumed.** Neither UESP nor xEdit states the
  member's unit, and the two candidate readings — a dimensionless multiplier over world
  gravity, or an acceleration in units per second squared — are distinguishable by looking at
  the data. Censusing all 134 PROJ records in `Skyrim.esm` by DATA `type` gives, for the 20
  of type `arrow`, `gravity` bounded by 1 (min 0.000, max 0.350, mean 0.332, 19 of 20
  non-zero) beside a `speed` running to the thousands (min 1000, max 15000, mean 3960). A
  member bounded by one next to a member in the thousands is a scale, not an acceleration.
  The arithmetic agrees outright: the vanilla iron arrow drops 18.90 world units over 1,000
  units of level flight on the multiplier reading and 0.0135 units on the acceleration
  reading — no drop at all, and a shipped record does not carry a member that does nothing on
  every projectile it has. The whole-set figures deliberately do *not* show this and are
  recorded anyway, because a handful of `missile` records carry values into the thousands
  and drag the all-types mean to 149; the finding is about arrows.

* **None of archery's three GMSTs is a GMST on this install.** `f1PArrowTiltUpAngle`,
  `f3PArrowTiltUpAngle` and `fVisibleNavmeshMoveDist` resolve to the UESP-documented default
  across the whole active load order, and neither `Skyrim_Default.ini` nor the four quality
  presets beside it names any of them. They are engine defaults rather than data, so the
  source string each reports is "UESP-documented default" — the truth rather than a degraded
  answer — and the resolution is kept so a mod that does add the GMST wins and the readout
  says which plugin did it. Two cross-checks fall out of the same page: UESP's "a weapon with
  a reach of 1 has a reach of 141 distance units" is the same `fCombatDistance` melee
  resolves to 141.000, and its note that projectile ranges run "in the tens of thousands" is
  confirmed by every vanilla arrow carrying `range` 60000 — so `fVisibleNavmeshMoveDist` is
  what actually bounds a shot, not the record.

* **The flight model is exact rather than approximate, and that is deliberate.** With no drag
  the motion under constant acceleration has a closed form, and `ProjectileFlight.step` is
  that form over one `dt`. Semi-implicit Euler — what the dynamic-body solver uses — would
  accumulate a half-a-dt-squared error per step, which is fine for a crate settling on a
  floor and is not fine for a trajectory whose apex and impact point the acceptance gate
  pins. The runtime accumulates frame time and advances on `WalkController.fixedTimeStep`, so
  a shot fired from a given pose lands in the same place at 60 Hz as at 240 Hz.

* **The impact query is split, and the split is the answer to the issue's open choice.**
  Static geometry gets the 15.2 sphere sweep, because PROJ carries a `collisionRadius` and an
  arrow is not infinitely thin; actor capsules get `MeleeHitDetector.closestApproach`, which
  is exact against a capsule and costs one closed-form solve per actor per step. Each capsule
  is tested against the whole step segment rather than at sampled points along it, so a thin
  actor cannot slip between two samples of an arrow covering 30 units per substep. One impact
  per projectile is enforced by the projectile ceasing to exist rather than by a filter.

* **Stuck arrows ride the dropped-item channel.** A landed arrow is a `ReferenceSpawnState`
  of its own AMMO at the impact transform — the one runtime-object channel this engine has —
  capped at UESP's own vanilla number ("only 15 missed arrows or bolts can be present at
  once, once a 16th has been fired the first one fired will despawn") and reconciled against
  the streamer's resident set each frame, so an unloading cell takes its arrows with it.
  In-flight projectiles are removed by any reset without resolving, which is what makes them
  something a save/load does not persist. The honest limitation: the arrow is spawned at a
  world transform rather than attached to an actor's bone, so an actor that walks away leaves
  it where it landed.

* **Damage is the documented combination.** UESP "Skyrim:Archery" gives
  `(bow damage + arrow damage)` and the three-branch draw-time curve, and "Skyrim:Weapons"
  gives the `(1 + skill/200)` term; the perk, enchantment and potion terms are M18's and
  enter as one multiplier defaulting to 1. The page marks the middle draw branch approximate
  and that caveat is carried rather than smoothed over. The draw fraction scales the launch
  speed as well as the damage, so a snap shot is slower and drops further as well as hitting
  softer.

* **The left mouse button now reports an edge and a level.** Melee acts on the press and
  archery on the hold; the view sets both from one mouse-down and clears only the level on
  the mouse-up and on capture loss, so a button released outside the window cannot leave a
  bow drawn forever. Which of the two acts is decided by WEAP DNAM `animationType == .bow`.
  `LocomotionGraphEventQueue` gained its third cursor with no change to the queue, which is
  what item 15.4's promotion from drain-once bought.

  The vanilla player graph declares a home for all ten archery event names and for
  `bBowDrawn`, with zero misses. What it does with a raised `bowDrawStart` is bounded by the
  same unresolved `iRightHandType` encoding item 15.4 documented (issue #403), so until that
  is settled the graph-driven path raises correctly and receives nothing back, and the
  sidebar's Fire control is the way to put an arrow in the air. Both go through the same
  `ArcheryRuntime.loose`. New sidebar section `World > Player & Locomotion > Archery`; new
  CLI subjects `gmst archery` and `archery [--census]`.

* **Melee: draw and sheath, attack and block, hit volumes, damage (issue #195)**: a swing
  from the key press to the health that comes off. The rule the whole item is built on is
  that the *graph* decides and the engine only asks: the engine raises `attackStart`, and
  the behavior graph decides whether an attack state was entered, how long the windup lasts,
  and which frame connects. Every melee state is read off the events the graph fires back
  rather than timed beside it, which is the same rule the footstep director follows and
  which means there is no engine-side swing timer for a stagger to have to cancel.

  Every event and variable name comes from the M14 census over the install, never from
  memory, and the vanilla player graph accepts all fourteen of them with zero misses. Two it
  does *not* get: `iRightHandType` and `iLeftHandType` are `int32` variables the census
  names but gives no encoding for, so OpenSky leaves them unwritten rather than guess which
  integer means "one-handed sword" and silently select the wrong animation set. The cost is
  visible and recorded — raising `weaponDraw` moves the vanilla graph but never reaches the
  `BeginWeaponDraw` annotation, so the state stays `drawing` — and the real-data test
  asserts that outcome, so settling the encoding (issue #403) turns it red.

* **The graph-event seam is multi-consumer now.** `LocomotionGraphEventQueue` was
  drain-once with one consumer, and a drain-once queue cannot have two: whichever drained
  first would take the whole batch. It now holds one cursor per registered consumer, with
  positions in a monotonic sequence rather than indices into the storage, so trimming the
  front cannot rewind anybody. The 64-name bound is over *undrained* names, so a consumer
  that stops draining costs the other nothing but its own lost tail. With no consumer
  registered the buffer is dropped outright, which is why the bridge registers both cursors
  in `init` rather than lazily — a cursor created on first drain would find the queue
  already empty.

* **The install disagrees with UESP about the block settings, and the install wins.** UESP
  "Skyrim:Block" writes both block formulas in percentage points with a 30 weapon base, an
  85% cap and a 1.5 skill weight. Reading `Skyrim.esm` through the new `openskycli gmst
  combat` gives fractions instead, and two different values: `fBlockWeaponBase` 0.300,
  `fBlockMax` 0.700, `fBlockSkillMult` 2.000. What UESP still supplies is the shape — which
  term multiplies which — and that shape reconciles with the fractions on exactly one
  reading: the base terms and the cap are fractions, the scaling terms are percentage points
  per unit, so each scaling term carries a `/ 100`. Every fallback in `CombatSettings` is now
  the install's value rather than the printed one, and says so in its source string.

* **Both M14 feature tallies turned out to be observability rather than gaps.** The issue
  asked whether attack states need `clipUserControlled` (79 evaluations) and
  `stateMachineTransitionInterrupted` (61) implemented. Read against the evaluator, both
  already are: clip mode 2 reads `m_userControlledTimeFraction` through the variable-bound
  member map, and an interrupted transition already restarts from wherever the machine has
  got to and drops the older blend, which is exactly what attack cancel needs. The coverage
  delta is zero and the tallies count real events rather than skipped ones.

* **`ItemDefinitionStore` keeps the decoded WEAP records beside the unified item views**, and
  `Weapon` decodes the INAM and BIDS impact links it had been skipping. Melee needs DNAM
  reach, speed and stagger and the INAM impact set, and `ItemDefinition` deliberately carries
  only what every item family has in common; a second dictionary costs one pointer per weapon
  and keeps the common view from growing a weapon-shaped hole every other family fills with
  nil. The hit-impact chain is then the footstep chain with one link changed —
  `HitFrame -> WEAP INAM -> IPDS -> IPCT for the material -> SNDR` — so it reuses
  `FootstepStore`'s indexes rather than loading a second copy.

* **Actors have health, magicka and stamina, and the HUD bars are live (issue #194)**: the
  M8 meters had been a static placeholder driven once at startup with `.full`, because
  nothing in the engine knew what an actor's health was. Item 15.3 supplies it end to end.

  The derivation is the part worth recording. The Creation Kit wiki gives the shape — base
  is "determined by their Race, Class, and Level" and calculated is "Base + Offset" — and
  UESP CLAS gives the arithmetic, including the exact apportionment method for the per-level
  points: complete sets first, then the leftover one at a time in decreasing weight order
  with ties going to stamina, magicka, health. The two constants are the `iAVDhmsLevelUp`
  and `fNPCHealthLevelBonus` GMSTs, read from the load order rather than hardcoded.
  `ActorBase` now decodes the ACBS stat words it had been skipping, `Race` decodes the DATA
  starting attributes and regen floats, and a new `CharacterClass` decodes CLAS attribute
  weights.

  Citations were not taken on trust. The Creation Kit bakes its own calculated triple into
  every NPC_'s DNAM, so the real-data test derives values for all 4297 auto-calc records in
  `Skyrim.esm` and compares against them: 4271 match exactly. That census is also what
  settled an undocumented question. When `useTraits` and `useStats` resolve to different
  records, which race feeds the starting attributes? Neither source says. With the traits
  race, 61 records disagreed with their own DNAM; with the stats record's race, 26 — and
  every one of those 26 inherits from `EncBandit04TemplateMelee`, whose DNAM contradicts its
  own ACBS while its sibling `EncBandit03TemplateMelee` matches the formula exactly. The
  Creation Kit documents that a baked value goes stale when an offset changes without the
  Stats tab being refreshed, so the formula is right and one vanilla record is not. The test
  pins the count at 26 rather than tolerating a range.

  The runtime side follows the inventory and quest precedent exactly: `ActorValueState` is a
  ninth `WorldStateComponentKind` holding **current values only**, because the maximums are
  a pure function of the records and persisting them would let a save carry a number a
  changed load order no longer authors. It travels in its own additive `AVAL` save chunk for
  the reason every gameplay chunk since `INVN` has: a component kind inside `RDLT` is
  versioned by `formatVersion`, so an older build would refuse the whole save instead of
  loading the world with everyone at full health. `hasZeroHealth`, which item 15.6 consumes,
  is derived rather than stored — a stored flag and a stored health can disagree, and after
  a round trip nothing could say which was right.

  Regeneration is percent-of-maximum per second straight off RACE DATA, on a 1/60 s fixed
  step chained onto the same `Renderer.onWorldUpdate` closure the Papyrus VM uses. That is
  what makes the menu-pause rule apply for free: a paused frame delivers delta 0, and a zero
  delta advances nothing. Health deliberately does not regenerate at zero, because whether a
  dead actor comes back is 15.6's decision and not this layer's.

  No SWF work was needed for the meters. `HUDMeterBinding` is an engine type that turns
  current values plus maximums into the existing `HUDMeterValues` and gates on change, so
  the acceptance test drives player damage and watches the bars move with no window and no
  SWF runtime in the picture. `ActorValueControlProviding` specifies the panel seam now; the
  panel ships with the M15 gate. New probe: `openskycli actor-values`.

* **Simulated clutter is drawn where the solver has it (issue #193)**: the dynamic
  rigid-body world was complete and invisible. Collision, sweeps, the player's shove and the
  resting-transform persistence all ran on live poses, but the drawn mesh came from the
  matrix its cell build baked, so a shoved barrel rolled and settled without moving on
  screen and then jumped to its resting pose when the settle triggered a cell rebuild.

  Rebuilding a cell per frame is not an option and rebuilding draw groups per frame is the
  player body's answer, which it needs only because skinned geometry is placed by its bone
  palette as well as by its model matrix. Rigid clutter needs neither. What ships instead is
  a per-instance delta: `DynamicBody.instanceDelta(fromPlacedPosition:orientation:)` is the
  rigid transform from the pose the build drew a reference at to the pose the body is at,
  `DynamicBodyWorld.instanceDeltas` collects them per frame keyed by REFR FormID, and
  `Renderer.drawn(_:)` substitutes `delta * baked` in the two places instance transforms
  reach the GPU. Applying it on the left of the baked matrix means the reference's XSCL
  scale and the mesh's own local transform never have to be recovered, and the shadow pass
  gets the same substitution, so a moving body's shadow travels with it.

  A `DrawInstance` carries a `referenceFormID` only when a body owns it, so every other
  placement in the world costs one integer comparison; a body resting where it was placed is
  absent from the map rather than present with an identity, so settled clutter costs what
  static clutter costs. The placed pose the delta is measured from is now refreshed on every
  `setCell` rather than only for new bodies — a rebuild that bakes a settled pose has to move
  the reference point with it, which also fixes the panel's reset returning a body to the
  plugin's pose instead of the current build's.

* **NIF graph walks spend heap instead of call frames (issue #388)**: the first sanitizer
  baseline crashed `NIFModelTests.absurdDepthIsMalformed()` under Address Sanitizer with a
  stack-guard hit rather than a poisoned-memory report — the 70-node chain the test builds
  exhausted the thread stack before the depth-64 cap could reject it. ASan only shortened a
  margin that was already thin: one `visit` frame carries a decoded `NIFNode` and a
  `float4x4`, the block decoder sits on top of it, and a NIF is attacker-shaped input that
  any secondary thread parses on a 512 KB stack rather than the main thread's 8 MB. The cap
  was never measured against a frame size, so it was standing in for a stack budget it did
  not know.

  All five NIF graph walks — the bind hierarchy, the mesh flatten, the particle collect,
  the collision scene-target visitor, and the collision shape graph — now descend through
  one shared explicit work stack, `NIFGraphStack`. It queues `enter` steps in reverse child
  order so `next()` yields the same pre-order a recursive descent produced, and pushes a
  `leave` sentinel behind a node's children in place of the `defer` that used to pop the
  cycle-detection path. Each walk keeps its own range, depth, and cycle diagnostics, so the
  error text and the skip-versus-throw behavior are unchanged.

  Depth is now a heap cost, which makes each cap a plausibility policy on scene graphs
  again rather than a proxy for the caller's stack. `NIFModelTests` flattens a chain sitting
  exactly at the cap on a thread with a 64 KB stack, and `make test-sanitize` is clean under
  both configurations.
* **The vanilla player graph fires its footstep tags (issues #385, #394)**: walking the real
  locomotion graph for a second fired `moveStart` and `IdleStop` and nothing a footstep set
  answers to, so the whole footstep chain — set selection, material, tag resolution, PCM
  playback, all of it separately tested and all of it correct — was fed by an event stream
  that never carried a footstep. Three faults stacked, and each hid the next.

  **The animation carries the marks, not the behavior file.** `FootLeft` and `FootRight` are
  `hkaAnnotationTrack` annotations inside `mt_walkforward.hkx`, at 0.2333 s and 0.8 s of its
  cycle. The clip evaluator read only `hkbClipTriggerArray`, on the documented belief that
  Havok bakes annotations into it at export with `m_isAnnotation` set — which the vanilla
  data flatly contradicts: every locomotion `hkbClipGenerator` in `mt_behavior.hkx` carries
  an *empty* `m_triggers`. `hkaAnimation.m_annotationTracks` at 0x28 is now decoded and its
  marks fire through the same crossing test the authored triggers use.

  **Events echoed forever across a behavior reference.** The parent raised the child's
  `firedEvents` — its *active* set, which already held everything the parent had pushed down
  the update before — back onto itself, so every crossing event bounced between `0_master`
  and `mt_behavior` once per update without end. The pull now reads the child's `pending`
  queue, which is what the child's own nodes raised, and the push skips the names just
  pulled from that same child.

  **The real-data test built a graph the engine never builds.** It assembled the instance by
  hand and left `references` nil, so `0_master.hkx` ran as the shell it is with no locomotion
  behind it. It goes through `PlayerBehaviorGraph.load` now, the same loader the app uses.

  The echo mattered because `LocomotionGraphEventQueue` is bounded at 64: three events per
  step across 120 steps left the drain holding twenty updates of the same echoing names, so
  even after the annotations fired they were evicted before an audio frame read them.
* **Run directories are allocated atomically (issue #306)**: `tools/run-dir.sh` picked its
  collision suffix by testing `[ -e ]` and then calling `mkdir -p`, which is check-then-act.
  Two runs starting inside the same second both saw the name free, both succeeded, and
  shared a directory — then collided on the file they each wrote into it, surfacing as
  `xcodebuild` reporting `Existing file at -resultBundlePath` and reading like a stale file
  rather than contention. A bare `mkdir` retried on failure fixes it, because creating a
  directory is atomic and exactly one racing caller can win a name. Measured with 40
  concurrent callers: the old code handed out 10 distinct directories, the new code 40.
  The original report was against `make test-one`'s hardcoded bundle path, which the
  per-run directories of issue #347 had already retired; this closes the race that survived
  it.

* **`make test-ui` runs, and it was never a permissions problem (issue #380)**: the UI
  target had compiled and never once executed, dying at harness init with `Timed out while
  enabling automation mode`. Four issues read that string as a missing TCC grant and chased
  it — #364 found ad-hoc signing, #365 and #366 pinned one Apple Development identity, and
  `tools/test-perms.sh` grew to point at Automation and Full Disk Access for the terminal.
  The signing work was right for its own reasons and changed nothing here.

  Streaming `tccd` across a failing run settled it: **zero** `kTCCServiceAccessibility`
  requests in the whole ninety seconds, the only line naming the runner a `syspolicyd`
  Gatekeeper check. Nothing was ever denied because nothing ever asked. Sampling the app
  under test showed where it actually sat — `libXCTestBundleInject.dylib` →
  `-[XCTestDriver _prepareTestConfigurationAndIDESession]`. `openskyTests` is app-hosted, so
  a plan carrying both bundles makes `xcodebuild` stand `opensky.app` up as a *unit-test
  host* in the same session the UI runner is trying to drive it in. The app waits for an IDE
  session that belongs to the runner; the runner waits for the app to enter automation mode;
  XCTest times out after sixty seconds. `-only-testing:openskyUITests` never helped because
  a selector filters which tests run, not which targets the session stands up.

  `Config/UITests.xctestplan` lists `openskyUITests` alone and `make test-ui` selects it.
  `AllTests.xctestplan` is deleted rather than left as a footgun: it *is* the deadlock, and
  nothing else used it. With the harness alive the runner does now request Accessibility, so
  the grant is real — one click per code signature, against
  `openskyUITests-Runner.app` rather than the terminal, which is what `test-perms.sh` should
  have said all along.

  Reaching the first test case then exposed what the target had been hiding. Six of nine
  tests failed on `outlines["AppSidebar"].cells[...]`, which matches nothing: the rows are
  `NSTableCellView`s, published to the accessibility hierarchy as groups, so the ids are
  reachable only by matching the identifier without constraining the element type. A seventh
  failed reading `.label` on a readout whose text AppKit exposes as the element's `value`.
  Both had been green in `DestinationRegistryTests` the entire time, which is precisely the
  gap the issue predicted — a unit test pins the id string, only a UI test proves the id is
  reachable. `make test-ui` is now 9 passed, 1 skipped, 0 failed, and the standing
  `environment.md` entry is retired by its own stated condition.

## 2026-08-06

* **Dynamic clutter settles and fits its frame budget; routing is on by default
  (issue #392)**: item 15.2 shipped with two of its acceptance criteria unmet, and this
  closes both. Against Chillfurrow Farm the probe went from 13 of 51 references coming to
  rest — with 20 of the other 38 falling more than twenty thousand units out of the world —
  and a 247 ms fixed step, to **51 of 51 asleep** with a largest drop of 137 units and a
  step of well under a millisecond. `CellSceneBuilder.simulatesDynamicBodies` now defaults to
  true and the probe asserts both claims instead of printing them.

  Four rules were wrong, and each was invisible to the synthetic suites because each needs
  geometry those fixtures did not have. **A surface faces the way it is wound**, not toward
  the body's centre of mass: vanilla ships a model whose decoded centre of mass sits below
  every vertex of its own collider, so the old rule read the shelf it stood on as facing down
  and drove it through. Skyrim's collision soups are consistently wound front face outward,
  measured over a whole interior; a box and a convex hull are the exception, because this
  engine derives their connectivity itself and so orients them away from an interior point.
  **A shape's nearest face vetoes its far ones**: a body hovering three units over a shelf
  board was finding the board's underside twenty units away and being told it was twenty units
  inside the board, so the narrowphase now ranks by distance whether or not a face reports a
  penetration. **One penetration is corrected once**: a sample generates a contact per placed
  shape it is near, and applying each in turn moved a body by the sum of a dozen identical
  corrections — 118 units through a farmhouse floor in a single step — so corrections
  accumulate per body against what that body has already been moved, capped per substep.
  **Sleep is measured with hysteresis, at the body's own scale, and disturbed only by
  motion**: a body at rest on triangle-soup geometry twitches as its samples cross triangle
  edges, so a tally that zeroes on any twitch never reaches sixty; and because a step adds
  gravity before contacts resolve, testing a neighbour's *velocity* made every awake body look
  busy and left settled pairs waking each other forever, one sleeping on step 61 and woken on
  step 62.

  The step also got 24x cheaper from work that is now correct rather than merely faster:
  one substep instead of eight (nothing is flying any more), sleeping bodies costing nothing,
  per-triangle work hoisted out of the per-sample loop into `DynamicSurfaceTriangle`, an exact
  plane-distance bound that dismisses a triangle before the closest-point query, and a
  recovery depth scaled to the body rather than a flat 48 units.

  The perf gate needs an optimized build to mean anything — a step is a few hundred
  microseconds of tight `simd` arithmetic, which `-Onone` costs around 24x — so
  `make realtest-perf` builds this suite with `-O` into its own derived-data tree and holds it
  to the real 2 ms budget, while a default `make realtest` still gates at an unoptimized
  ceiling. `docs/engine/dynamic-bodies.md` loses its "what is not done yet" section.

* **Movable clutter simulates: fixed-step rigid bodies, shape sweeps, and settling drops
  (issue #193)**: collision had been static-only since 4.3, and item 15.1 decoded the
  inertial tail without anything consuming it. The cell build now splits each player-solid
  `bhkRigidBody` in two — `NIFRigidBodyDynamics.isSimulated` bodies with a runtime key go to
  `CellScene.dynamicBodies`, everything else stays in `StaticCollisionSet` — and the split
  follows the dynamics census rather than the motion byte, which on vanilla data would have
  made 1027 immovable bodies dynamic. `DynamicBodySolver` steps them on the same 1/120 tick
  the player capsule runs on. Two findings shaped it. The narrowphase has to be *signed*
  against a triangle: an unsigned distance flips the push direction the moment a corner
  passes through a floor, so the sign comes from the triangle plane oriented toward the
  body's centre of mass, which is stable because a convex body's centre is always outside a
  surface it rests on. And penetration recovery has to move *positions*, not velocities: the
  textbook Baumgarte velocity bias — what the first draft used — leaves a resting body with a
  standing upward velocity fighting gravity forever, so it never reaches the sleep threshold
  and never settles. A moving body hands the rest of the engine ordinary
  `StaticCollisionShape` values at its current pose, so the capsule, the interaction ray, and
  the new sphere and capsule sweeps see clutter through queries that already existed.
  Streaming reconciles bodies against residency once per frame rather than being pushed at,
  which makes coverage transitions, door transitions, and world-state rebuilds all correct
  without any of them knowing physics exists; a settled body persists through the existing
  `.transform` component. `docs/engine/dynamic-bodies.md` is new.

  Routing clutter out of the static set is **off by default**
  (`CellSceneBuilder.simulatesDynamicBodies`). The real-data probe found two things the
  synthetic suites cannot see: about half of a vanilla farmhouse's clutter is authored
  *intersecting* the shelf it stands on and is not reliably expelled from it, and the step
  costs roughly 230 ms against a 2 ms budget. Three narrowphase rules were corrected while
  chasing the first — orient a contact from the pre-substep centre, rank a shape's triangles
  by nearest surface rather than deepest penetration, and keep a model's non-simulated bodies
  static — and two structural wins landed on the second, and neither is closed. Turning the
  flag on by default would trade a world where a barrel is reliably solid for one where it
  sometimes sinks through a shelf, so it stays off and issue #392 carries the two remaining
  items with their measurements.

* **`NiTriStripsData`'s Consistency Flags is a ushort, and the three clutter meshes that
  said so decode again (issue #376)**: the collision strips decoder skipped eight bytes for
  Consistency Flags plus the additional-data ref where `nif.xml` has six, so every field
  after it was read two bytes late. The strip table then produced a triangle count that did
  not match the declared one, or point indices past the vertex array, and the whole collision
  root was dropped for `clutter\coffins\nordiccoffinstatic03.nif`,
  `clutter\goatskin\goatpeltstatic.nif` and `clutter\nightmother\nmbody01.nif`. Those are the
  only three assets in the install that reach this decoder — every other collision mesh is a
  packed or compressed shape — so nothing had ever exercised it against real bytes until the
  dynamics census swept the whole clutter tree, and the synthetic fixture repeated the same
  wrong width, which is why the unit tests were green throughout. A probe over the three
  files settled it before any change: with a six-byte skip all five strips blocks read to
  exactly their last byte with every point index inside the vertex array and the declared
  triangle count matching, and with eight neither held. Both checks stay — a mismatch is
  still a tallied failure rather than whatever geometry falls out. The fixture now also has
  a `niTriStripsDataFullPrefix()` variant carrying normals, tangents, vertex colors and a UV
  set, since the minimal one skipped the arrays where a width can be wrong, and the clutter
  and skeleton census sweeps now assert zero decode failures the way the exterior sweep
  already did.
* **The unit tests run under sanitizers: `Config/Sanitizers.xctestplan` and
  `make test-sanitize` (issue #383)**: nothing in the repo had ever run under a runtime
  sanitizer, in a codebase that reaches ffmpeg across a C boundary, slices
  `UnsafeRawBufferPointer` over memory-mapped archives, and does most of its concurrency in
  the `nonisolated` declarations that opt out of what Swift 6 checks statically. `Sanitizers`
  joins `UnitTests`, `AllTests`, and `RealData` as the scheme's fourth checked-in plan, with
  one configuration per sanitizer because Thread and Address cannot be enabled in the same
  build: `threadSanitizerEnabled` for `Thread`, `addressSanitizer.enabled` plus
  `undefinedBehaviorSanitizerEnabled` for `Address`. It is a separate plan rather than two
  more configurations on `UnitTests` because xcodebuild builds *and* runs every configuration
  in a plan, so `make test` — the pre-push gate on every commit — would have paid for both
  sanitized builds. Measured while wiring it: each configuration lands in its own
  `Variant-TSan` and `Variant-ASan-UBSan` products directory, and
  `-only-test-configuration Thread` still builds the ASan variant, so `SAN=Thread` narrows
  what executes and not what compiles. `tools/test-sanitize.sh` runs it under the memory
  watchdog at 12288 MB, well above the real-data caps, because sanitizer shadow memory
  multiplies resident size. The plan carries the same `opensky`-scoped `codeCoverage` entry
  the other two unit plans grew in issue #382, so a sanitized bundle reports the same
  engine-scoped number rather than an unscoped one.
* **First sanitizer baseline: clean under TSan, one real crash under ASan (issue #383)**:
  3129 tests across both configurations, 3069 passed, 59 skipped on the usual Metal and
  data-root gates, one failure. Thread Sanitizer reported nothing at all across the whole
  bundle, which is the more surprising half of the result. Address Sanitizer crashed the test
  host on `NIFModelTests/absurdDepthIsMalformed()` — not a poisoned-memory report but a
  stack-guard hit inside `NIFNodeHierarchy.Builder.visit(ref:parent:depth:)`, whose 64-level
  depth cap is a plausibility limit on scene-graph depth rather than a measured stack budget.
  The recursion reaches the guard page before the cap fires, so the check that exists to
  reject a malformed mesh does not protect a parse running on a small-stack thread. Filed as
  issue #388 rather than fixed here, so `make test-sanitize` is red on that one test until it
  lands; every other test in the bundle is green under both sanitizers.
* **Heimskr's model order was never nondeterministic — the assertion was stale (issue
  #384)**: `ActorAssemblyRealDataTests.rendersHeimskrAtACHRWorldPose()` expected monk boots,
  robes, hood and got boots, hood, robes, which read as an unordered collection somewhere in
  the resolve. It is not. Five consecutive `openskycli actor --npc Heimskr` runs produce
  byte-identical part lists, and the probe says why: `ClothesMonkRobesHooded` `00107106`
  lists `MonkRobesAA` `000BAD04` (DNAM priority 15) ahead of `MonkHoodAA` `000BAD03`
  (priority 10), and `ActorVisualResolver.inDrawOrder` sorts every worn armature by ascending
  priority. The assertion landed 2026-07-20 with the assembler; the priority sort landed
  2026-08-01 with equipment (issue #299), and nobody re-ran this single test in between. So
  the order is a contract and the expectation was simply twelve days out of date. Fixing the
  snapshot alone would leave it just as able to rot, so the test now also asserts the rule
  that produces it — the worn parts' DNAM priorities, read back through the resolver, must be
  `[10, 10, 15]` — and a synthetic test covers the specific shape that caught nobody's eye,
  priority reordering two armatures *within a single ARMO* on the plugin `defaultOutfit`
  path. The existing draw-order tests only ever exercised the runtime equipped-set path
  across separate pieces. Verification: the real-data test green three runs in a row, and the
  suite green under `make realtest-all`.

* **Code coverage was already being measured and thrown away (issue #382)**: nothing in the
  repo reported coverage, so there was no way to answer "is this parser actually covered, or
  does it just have a test file next to it?" across 49 format parsers other than by reading
  both. Measuring the cost before making it unconditional, as the issue asked, found there
  was no cost: `ENABLE_CODE_COVERAGE` defaults to `YES` in Xcode and no `Config/*.xcconfig`
  overrides it, so every `.xcresult` the repo has ever written already answers
  `xcrun xccov view --report`. Nobody had run the command. Adding
  `-enableCodeCoverage YES` to a warm `make test` recompiled nothing and moved the wall
  clock from 37.5s to 35.5s — inside the noise, because it turned on something already on.
  So there is no `make test-coverage` to remember and no flag: `codeCoverage` is a
  `defaultOptions` entry on `UnitTests.xctestplan` and `AllTests.xctestplan`, scoped to the
  `opensky` target, and `make test-report` prints the percentage under the pass/fail counts.
  The scoping is the part the plan entry actually buys — an unscoped report puts a
  meaningless 86.68% for `openskyTests.xctest` and a 0/0 for `openskyUITests.xctest` beside
  the number anyone wants, which is the engine's. Baseline: **80.31% of lines
  (57543/71652)**, at 3070 passed and 59 skipped. No threshold gate and no number in CI in
  this pass, deliberately: the value is finding the defensive branches in the parsers that
  no test ever takes, which is exactly the code "malformed input must not crash" is about,
  not defending a percentage. A floor gets argued from a baseline, the same discipline the
  perf budgets already require.
* **The real-data suites run as a set: `Config/RealData.xctestplan` and `make realtest-all`
  (issue #381)**: 48 env-gated suites skip in every `make test` run, and the only way to run
  one was `make realtest T=...`, which deliberately runs exactly one — so the highest-value
  integration coverage in the repo was never executed as a set by anyone. `RealData` joins
  `UnitTests` and `AllTests` as the scheme's third checked-in test plan — the real-data
  variant the plan split (issue #346) predicted, landed the same day — and
  `make realtest-all` runs it under the memory watchdog, failing if any test
  fails or if zero executed. Measuring the plan mechanism first, as the issue asked,
  answered three questions and reshaped `tools/realtest.sh` around the answers. A plan's
  `environmentVariableEntries` **does** reach the unit-test host, which is what issue #82
  needed and could not find: the `build-for-testing` / rewrite the generated `.xctestrun`
  with `plistlib` / `test-without-building` sequence is gone, replaced by an ordinary
  `xcodebuild test -testPlan RealData`, and the separate `DerivedData/opensky-realtest`
  cache it existed to protect went with it. A plan environment value is **not**
  macro-expanded, so `$(OPENSKY_DATA_ROOT)` arrives at the host as a literal 21-character
  string; the plan therefore holds a literal path and is now the one place the data root is
  configured, with the script reading it back out and refusing to run against a conflicting
  exported `OPENSKY_DATA_ROOT` instead of silently testing an install the plan does not
  name. And a plan's `selectedTests` **does not match Swift Testing tests** at all — the
  identifiers reach the runner as `OnlyTestIdentifiers` and select nothing, which showed up
  as a green run that executed zero tests — so the script reads the plan's list and passes
  one `-only-testing` per suite, which does work. The plan stays the named, diffable
  declaration of the set either way, and the new `make realdata-plan` lint (in `make lint`)
  asserts it is exactly the suites that declare `dataRoot: GameDataRoot?` and carry a
  `@Test`, so adding a real-data suite and forgetting the plan is a lint failure rather than
  silent coverage loss. `make realtest T=...` keeps its exactly-one enumeration guard, which
  is about selector typos and not about the set. Neither target runs on push: they need an
  install CI does not have and must never be given. The first full run executed 62 tests
  across 48 suites in 12 minutes and found two failures that reproduce on their own
  (issues #384 and #385) — which is the point of the target, since neither test had been
  re-run since it landed. It also found that `make test-report` printed "no failing tests"
  for every bundle: its walk recursed on `children`, and the root object holds the tree
  under `testNodes`, so it never reached a single node. The counts above it were always
  right; the per-failure detail was never printed.

* **Checked-in test plans replace the auto-created one (issue #346)**: the `opensky` scheme
  carried `shouldAutocreateTestPlan = "YES"` and no `.xctestplan`, so there was nowhere
  reviewable to say "unit only" — that logic lived as `-only-testing` and `-skip-testing`
  flags spread across the `Makefile` and `tools/test-ui.sh`. Two plans now sit in `Config/`
  beside the xcconfigs, for the same reason those live there: `UnitTests.xctestplan` lists
  `openskyTests` alone and is the scheme default, `AllTests.xctestplan` lists both bundles.
  Selecting the plan is what actually drops the UI bundle's compile and link, which the
  selector never did — `xcodebuild` builds every buildable in a scheme's Test action before
  it consults `-only-testing`. Measured directly: touching `openskyUITests/` and running
  `make test` used to recompile the bundle and now does not mention it at all, at an
  unchanged 3282 passed and 59 skipped. `make test`, `make test-one`, and
  `tools/realtest.sh` take the unit plan; `make test-ui` takes `AllTests` because it needs
  a plan that carries the UI bundle. Two selectors still ride on top of a plan: `test-one`
  keeps `-only-testing` for the single class or method and switches to `AllTests` when the
  selector names `openskyUITests`, since the unit plan cannot select a test it does not
  list. `realtest.sh` now finds its `.xctestrun` by the plan-qualified name, because a tree
  built before this change still has the planless one beside it and `find` order is not
  sorted. A sanitizer or real-data variant becomes another plan configuration from here
  rather than another flag combination.
* **The stale-`testmanagerd` remedy needed `kill -9`, not `killall`**: verifying the test
  plans ran into a wedged XCTest daemon two days old, which failed `make test` and
  `make realtest` alike with `The test runner hung before establishing connection`. On
  `make realtest` it surfaced first as the selector-validation step reporting the target
  root instead of the one test, because `-enumerate-tests` hangs the same way. The remedy
  in [Testing setup](/testing.md) said `killall testmanagerd`; the wedged daemon ignored
  SIGTERM and stayed up through two of them. `kill -9` on the pid cleared it and both
  entrypoints went green immediately, `make test` back to its unchanged 3282 passed. The
  bullet now names the symptom, says to check the daemon's start date, and says to escalate
  to `-9`.
* **`opensky/` split into `App/`, `Engine/`, and `SharedHeaders/` (issue #336)**: target
  membership was a hand-maintained list of 111 path strings — the
  `PBXFileSystemSynchronizedBuildFileExceptionSet` that kept app-only sources out of
  `openskycli`. Filesystem-synced groups put every new file under `opensky/` into both
  executables, so an AppKit import broke the CLI build until someone remembered the
  exception, and the list itself was constant project-file churn and a merge-conflict magnet
  across worktrees. Membership now comes from the filesystem: the app target synchronizes
  `App/` plus `Engine/` plus `SharedHeaders/`, `openskycli` synchronizes `Engine/` plus
  `SharedHeaders/` plus `openskycli/`, and the exception set is gone entirely. The split is
  exactly the old list — `App/` holds the AppKit and SwiftUI shell, the view controllers,
  the panels, `Shell/`, `Branding/`, and `Assets.xcassets`; `Engine/` holds every CLI-safe
  source including `Shaders.metal`; `SharedHeaders/` holds `ShaderTypes.h` alone, because
  both targets pin their bridging header at it. `MTL_HEADER_SEARCH_PATHS` now names
  `opensky/SharedHeaders` so `Shaders.metal` still resolves its `#import` from its new
  sibling folder. `tools/lint/cli-boundary.sh` no longer parses the project file; it greps
  `opensky/Engine/` for AppKit, Cocoa, and SwiftUI imports and fails on any hit, which is
  both cheaper and states the rule directly.
* **Stage 2 of issue #336 (a shared engine target) is not justified by measurement**: the
  premise was that roughly 550 engine sources compiling once per executable makes the
  pre-push `make cli` an expensive second engine build. A cold `make cli` into a fresh
  derived-data path measures 25 s wall on this machine (2026-08-06), which is not a
  demonstrable drag, and the trade-off on the other side is real: a module boundary blocks
  cross-module inlining under whole-module optimization in renderer hot paths unless
  cross-module optimization or `@inlinable` is adopted. Left undone deliberately. The other
  motivation — letting `openskyTests` test the engine directly instead of being app-hosted
  through `TEST_HOST` — stands on its own and would need its own issue.
* **Havok dynamics data: the inertial tail, constraints, and a real-data census (issue
  #192)**: the collision decoder had been skipping 140 bytes in the middle of every
  `bhkRigidBodyCInfo2010` — mass, inertia tensor, center of mass, damping, friction,
  restitution, the velocity ceilings, and the deactivator/solver/quality bytes — because
  the query path only ever needed the filters and the motion system. All of it is now
  decoded into `NIFRigidBodyDynamics`, and the constraint refs and body flags that follow
  it are read too. Seven `bhkConstraint` classes decode (ball and socket, hinge, limited
  hinge, prismatic, ragdoll, stiff spring, and the malleable wrapper around any of them),
  each with its pivots, frames, angular limits, and the three motor variants. The ragdoll
  carrier turned out not to be a container class at all: the per-bone bodies hang off
  `bhkBlendCollisionObject` and the bone mapping is the name of the `NiNode` each one
  targets, so scene traversal now records target names alongside transforms and
  `boneNames(of:)` resolves a joint's entity pointers into the bone pair it binds.
  The census over the install decided two things the spec could not. First, the motion
  system byte does not separate movable from static: 1027 immovable bodies read
  `MO_SYS_BOX_STABILIZED` with zero mass, the exporter's default, so mass and layer are
  the discriminators and `isSimulated` tests both. Second, vanilla ragdolls use exactly two
  constraint classes — 624 ragdoll cones and 512 limited hinges across 751 distinct bone
  pairs, every end bound — which is the list item 15.6 has to instantiate. Masses land
  between 0.1 and 750 kg with both distributions peaking in the 1-10 kg decade, which is
  the evidence that the tail is read at the right offset. The sweep also surfaced three
  vanilla clutter meshes whose triangle-strip collision has never decoded (issue #376);
  that predates this work and is filed rather than fixed here.

## 2026-08-05

* **Movement authority follows `m_extractedMotion` rather than a speed threshold (issue
  #370)**: the bridge used to hand a step to the graph's own root travel whenever that
  travel exceeded 10 units per second, a floor set against an *average* vanilla clip jitter
  of about 1 unit per second. The average was the wrong statistic — the test runs per step
  at 1/120 s, where a root bone moving 0.09 units reads as 10.8 units per second — so a few
  hundred steps of the M14 acceptance route took the root-motion branch on jitter alone, and
  one of them moved the capsule backwards along the walk direction. The two units of travel
  it contributed were never visible, but the classification was wrong in kind: a vanilla clip
  animates in place and can carry no travel at all. The parser now reads whether
  `hkaAnimation.m_extractedMotion` resolves, the clip evaluator reports the identity for
  every clip that does not carry one, and `BehaviorRootMotion.isExtracted` is what the bridge
  branches on — a property of the file rather than of a measured distance, so an
  extracted-motion clip that stands still for a step keeps authority and an in-place clip
  never gains it. The acceptance route now asserts `rootMotionDistance == 0` and a monotone
  forward walk leg rather than a small bound, and the panel's Root Motion readout states the
  rule beside the two totals so a zero reads as the expected answer. A clip that does carry a
  reference frame still has its travel approximated from the root bone, because
  `hkaAnimatedReferenceFrame` itself is undecoded; that is now tallied
  (`clipExtractedMotionApproximated`) rather than silent. See
  [walk mode](/engine/walk-mode.md) and
  [hkaSplineCompressedAnimation](/formats/hka-animation.md).
* **`make test` no longer inherits the machine's persisted data root (issue #362)**: the
  unit-test host is the app bundle, so it read the app's own defaults domain and found
  `OpenSkyDataRoot` pointing at the retail install. A panel-reset test then asked
  `TerrainLODSettings` to read `Skyrim_Default.ini` off an external volume and the host
  parked in `open()` for good — several thousand cases in, at 0.1% CPU, taking the pre-push
  hook with it. `TEST_RUNNER_OPENSKY_DATA_ROOT=""` never prevented this, because it clears
  only the environment variable. `GameDataLocator.locate` now takes its persisted defaults
  and its Steam fallback as optionals and withholds both inside a test host
  (`XCTestConfigurationFilePath`, the signal the headless host already uses), so a unit test
  reaches an install only through `OPENSKY_DATA_ROOT`. Withholding beats special-casing the
  one caller: it makes "unit tests are install-independent" structural rather than a rule
  each new call site has to remember, and it matches what the real-data suites already do by
  hand. Explicitly injected sources are untouched, so every existing resolution-order test
  reads the same; the only visible change is `notFound(searched: [])`, whose message now
  says no fallback location was consulted. The environment note recording the old hang is
  deleted rather than amended — its cause is gone. *Evidence:* `GameDataLocatorTests`
  (withholding asserted from inside the host, env var still winning with both sources nil,
  the empty-searched message), and `make test` passing on this machine with the persisted
  `OpenSkyDataRoot` still in place, which is exactly the configuration that used to hang.
  Docs: [game data locator](/engine/game-data-locator.md), [testing setup](/testing.md).

* **M14 accepted — the player walks, runs, sprints, jumps, sneaks and swims, in both
  perspectives (issue #191)**: the milestone gate wires, verifies and records what the other
  seven items built. The route is one continuous drive through every locomotion state, and
  it enters the engine where a player does: real key events reach a real `GameMetalView`,
  which fills the shipping `CameraInputState`, which each frame becomes a `CameraInput` for
  `LocomotionBridge.acceptFrame` and `WalkController.update` — the order
  `Renderer.advanceCamera` runs them in. The world under it is synthetic and closed-form
  (flat ground, a 20-degree slope, a basin 156 units under water, a streaming boundary, a
  load door), the graph over it is an eight-state machine wired to the events the bridge
  itself raises, and the whole thing runs headless with no device and no install. Decisions
  worth the record: the gate evaluates the *whole* graph rather than tallying a subgraph,
  because a state the route cannot reach is a state nothing proves; swimming stayed in the
  gate rather than being deferred with the water rendering, because the gait, the hysteresis
  and the swim clips are all M14's; the first-person half is a second graph reaching the same
  states from the same input rather than a camera-only change, which is what
  `M14AcceptanceTests` asserts state by state; and the movement-authority split — one
  horizontal source per fixed step, vertical motion the controller's alone — is now visible
  rather than merely documented, as two running totals on the panel that cannot both grow on
  one step. Writing the route turned up two engine facts. A reset used to hand the graph a
  `JumpFall` and a `JumpLand` for the single step a freshly-seated `WalkController` spends
  deciding it is standing on something, so every door transition reported a landing the
  player never took; ground events now start once the capsule is standing. And the
  root-motion speed floor is marginal against per-step vanilla clip jitter, which is issue
  #370 rather than a fix here. The new surface is `World > Player & Locomotion`
  (`Destination-playerLocomotion`): live graph, bindings, camera mode, root-motion trace, and
  the forced-state and event dev controls, so the loop is drivable without knowing a key.
  *Evidence:* `M14AcceptanceTests` (the route, and its exact repetition),
  `M14AcceptancePanelTests` (the destination as one surface on one provider set),
  `M14AcceptanceBudgetTests` (the shipping `validatedFlyUpdateBudgets` over the same
  benchmark configuration, plus the stalled-frame and zero-length-frame bounds),
  `PlayerLocomotionPanelTests` and `DestinationRegistryLocomotionTests` (the id and registry
  contracts), `M14AcceptanceRealDataTests` (env-gated, device-free) and
  `M14AcceptanceRenderTests` (env-gated and device-gated). Honest coverage on the local
  install, 2026-08-05: 684 updates over the vanilla `0_master.hkx` and its `_1stperson` peer;
  6,836 generator and 4,870 modifier evaluations third person, 6,836 and 5,554 first person;
  zero unevaluated generators, zero partial generators, zero unresolved clips, zero unapplied
  bindings, zero undecodable objects, and zero missing variable or event names on either
  perspective. What is still owed is semantics rather than decode: pass-through modifiers
  `BSSpeedSamplerModifier` 684, `hkbKeyframeBonesModifier` 684,
  `hkbRigidBodyRagdollControlsModifier` 684, `BSIsActiveModifier` 80, `BSModifyOnceModifier`
  1, `hkbTwistModifier` 684 (first person only), and the feature gaps `clipUserControlled`
  79 and `stateMachineTransitionInterrupted` 61. Pixels, same run: the body drew 41,274
  changed pixels, a sprint moved 43,605 against idle, a second player driven through the
  identical input reproduced the sprint frame exactly, first person differed from third by
  381,016, and a mode round trip returned a byte-identical frame. See
  [behavior graph runtime](/engine/behavior-runtime.md),
  [terrain walk mode](/engine/walk-mode.md), and the
  [sidebar acceptance ledger](/tools/sidebar-acceptance.md).

* **Footsteps use the ground's real material (issue #358)**: `FootstepStore.resolve` always
  took a `MATT` material and nothing could ever supply one, so every footstep fell back to
  the impact table's representative entry — stone-solid for the vanilla humanoid sets — and
  the player sounded identical on snow, wood, grass and gravel. The three missing pieces
  landed together. First, the collision world now carries a material: every `bhk` shape kind
  keeps the `SkyrimHavokMaterial` it names, and the two block kinds that store several
  (a compressed mesh's chunk table, a packed strip shape's sub-shapes) emit one shape per
  material instead of a per-triangle table. Second, `MaterialTypeIndex` turns that value into
  a `MATT` record: the value is a CRC32 of the Creation Kit material name, so the index
  hashes every `MATT.MNAM` and looks the mesh's value up. `nif.xml` names the rule but not
  the CRC parameters, and the ones it implements — reflected `0xEDB88320`, zero initial
  register, no final complement — are pinned against 32 of the enum's documented values in
  `HavokMaterialHashTests`. Third, terrain, which has no Havok material at all: each cell
  resolves its `LAND` splat stack into one `MATT` per terrain vertex through `LTEX.MNAM`, so
  a ground sample names what it found. `WalkController.groundMaterial` reports whichever
  applies — terrain when the snap put the feet down, else the flattest walkable contact, else
  the step-support surface — and the renderer's audio tick hands it to the footstep director.
  World > Audio > Footsteps gained `AudioFootstepMaterialControl`, which pins a material in
  place of the ground contact so one surface can be heard deliberately, and a `Material:`
  readout line. See [material types](/formats/material-type.md),
  [footstep records](/formats/footstep.md), [NIF collision](/formats/nif-collision.md),
  [terrain records](/formats/land.md), [collision world](/engine/collision-world.md),
  [terrain walk mode](/engine/walk-mode.md), and [audio engine](/engine/audio.md).
* **One checked-in signing identity, for every target including the UI test runner (issue
  #364)**: moving signing out of the pbxproj (issue #343) replaced a checked-in
  `CODE_SIGN_IDENTITY = "Apple Development"` and `DEVELOPMENT_TEAM` with a gitignored
  `Config/Local.xcconfig` that nobody had filled in, so every build after that commit
  signed ad-hoc. Ad-hoc signing produces a different signature each build and macOS keys
  TCC grants to the signature, so each build read as a new application: `make test-ui`
  asked for Automation every run, and the real-data unit tests hung in `open()` waiting on
  an access prompt for the external volume the game install sits on. Deriving the identity
  from the keychain was tried first and reverted — it has the same failure mode whenever
  the derivation comes up empty, and it makes the signature depend on machine state
  nothing in the repository can check. `Config/Signing.xcconfig` now names the identity
  and team outright, and `Config/UITests.xcconfig` includes it instead of pinning `-`:
  `openskyUITests-Runner.app` is the process that asks for permission to drive the app, so
  leaving it ad-hoc kept the dialog coming back even after the app itself was signed. The
  `make test-ui` recipe also passed `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` on the command
  line, which wins over every xcconfig layer, so that override is gone too.
  `tools/config-local.sh`, `Config/Local.example.xcconfig`, and the `config-local` make
  target are gone; an override is a hand-written `Config/Local.xcconfig`, still gitignored,
  or `XCODEBUILD_FLAGS` on the command line, which is what CI uses. See
  [Build system and xcodebuild invocation](/tools/build-system.md).

## 2026-08-04

* **No-op builds are no-ops again (issue #338)**: the three ffmpeg shell script phases were
  declared `alwaysOutOfDate = 1`, so every build re-validated the vendored prefix, re-copied
  and re-signed the three dylibs into `Contents/Frameworks`, and thereby dirtied the bundle
  enough that Xcode re-signed the whole app — on builds where nothing had changed. The flag
  is gone from all three. The embed phase now runs off the `.xcfilelist` inputs and outputs
  it already declared, and each check phase writes a
  `$(DERIVED_FILE_DIR)/ffmpeg-check-$(TARGET_NAME).stamp` so it has an output to be up to
  date against. All three also stopped listing the directory `.vendor/ffmpeg/lib` as an
  input, since a directory's mtime does not move when a dylib inside it is rebuilt in place;
  they declare `embed-inputs.xcfilelist` instead, which names the resolved dylibs and whose
  own rewrite by `tools/ffmpeg/link-vendor.sh` is what still surfaces the friendly
  missing-prefix error. Verified: clean build embeds and validates, touching a dylib re-runs
  both phases, a second `make build` or `make cli` runs no script phase and no `CodeSign`,
  and deleting the prefix still fails with the `run 'make bootstrap'` message. See
  [ffmpeg for audio decode](/decisions/ffmpeg-audio.md).
* **`make prune` plus a run-directory retention convention (issue #347)**: run output had
  no owner. Each linked worktree carries its own tens-of-gigabytes `DerivedData/`, and the
  worktree for a merged branch leaves it behind — 24 such trees, 51 GB, were sitting under
  `.claude/worktrees/` when this landed — while `tools/probe.sh`, `tools/test-ui.sh`, and
  `tools/realtest.sh` each dropped loose files into `logs/` under their own naming, so a
  stale capture read exactly like the current one. Every writing script now allocates one
  directory per run through `tools/run-dir.sh` — `logs/<script>/<UTC timestamp>/` with a
  `latest` symlink, and `.xcresult` bundles in the same shape under `build/test-results/`
  — prints it, and passes it down to nested scripts through `OPENSKY_RUN_DIR` so one run
  of `make realtest` keeps both transcripts, its enumeration, and its bundle together.
  Timestamped names sort in time order, which is how `make prune` decides both "newest
  run" and "past the retention age" without trusting modification times. `make prune`
  deletes the `DerivedData/`, `build/`, and `logs/` of any checkout under
  `.claude/worktrees/` that `git worktree list` no longer names, plus `build/install`,
  aged-out runs (keeping the newest per script so `latest` resolves), and pre-convention
  leftovers; it prints the whole plan with sizes and reasons before deleting, reports the
  space freed, and `make prune DRY_RUN=1` stops after the plan. The old ad-hoc
  `rm -rf build/test-results/*.xcresult` in `make test` and `make test-one` is gone. See
  [Run output layout and make prune](/tools/run-output.md).
* **Build settings moved to `Config/*.xcconfig`, signing out of shared config (issue
  #343)**: the five build-configuration lists in the pbxproj duplicated Swift mode,
  concurrency flags, ffmpeg search paths, linker flags, deployment target, and signing
  across every Debug/Release pair, so a settings experiment meant pbxproj surgery and the
  file was the top merge-conflict surface between parallel worktrees. All ten
  configurations now carry an empty `buildSettings` block and a `baseConfigurationReference`
  into `Config/`: `Base` plus `Debug`/`Release` at the project level, one file per target
  above them. `xcodebuild -showBuildSettings` is unchanged for all four targets in both
  configurations apart from the two `OPENSKY_*` variables the signing indirection adds.
  `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` are no longer checked in: they resolve from
  a gitignored `Config/Local.xcconfig` that `tools/config-local.sh` creates from a
  checked-in template, defaulting to the ad-hoc signing CI already passes, and a linked
  worktree copies the main checkout's file so a dev-signed setup does not silently become
  ad-hoc. See [Build system and xcodebuild invocation](/tools/build-system.md).
* **Swift warnings are build errors now (issue #350)**: the test targets had accumulated
  about a hundred compiler warnings, and since a warning is signal the `make test` output
  filter keeps, a run that recompiled them buried the result in diagnostics nobody read.
  Every one is fixed — `try` on calls that do not throw, discarded `try?` and `map`
  results, two `SystemMenuPanelTests` cases missing `@MainActor`, and `#require` nested in
  a comparison, which the testing macro cannot disambiguate. Turning the setting on
  surfaced five more in `openskycli`, which `make test` never compiles. Three sat in
  `opensky/`
  rather than in the test targets, all of them dead code that computed the right answer
  the long way round: `PlayerBodyError` fell back on a `??` whose left side could not be
  nil, `PapyrusWorldEvents` compared an already-unwrapped value to `nil`, and
  `HKBClassRegistry.entry` erased its decoder through a closure that implicitly captured a
  metatype the compiler could not prove `Sendable`. Nothing changed behaviorally. With the
  count at zero, `SWIFT_TREAT_WARNINGS_AS_ERRORS` is on in both project-level
  configurations so it cannot grow back. See [build system](/tools/build-system.md).
* **NIF `Matrix33` is a row-vector rotation (issue #354)**: every decoded NIF rotation was
  the transpose of the rotation it means, because the format multiplies row vectors and
  OpenSky's matrices multiply column vectors. Vanilla statics hid it — their `NiNode`
  rotations are overwhelmingly identity — and a skinned mesh's bind palette hid it too,
  since it is built from two halves of the same file that cancel the error. Every pose
  composed on top of that palette inherited it, so feeding a skinned actor any composed
  skeleton pose tore it into long flat shards, on the M6 clip path as much as on the M14
  player. Reading the nine floats as rows fixes it: `skeleton.hkx`'s reference pose now
  reproduces `skeleton.nif`'s bind pose to 5.3e-5 world units over the 96 bones the two
  files share, where it was off by up to 61.9. The palette composition moved out of
  `RenderMesh` into a Metal-free `SkinningPalette` so the round trip is unit-tested against
  hand-built matrices, and the real-data render gate now bounds a posed body's silhouette
  against the bind-pose body's rather than only asserting that two frames differ. See
  [NIF](/formats/nif.md) and [actor animation](/engine/actor-animation.md).
* **Footstep audio events (issue #352)**: deferred from item 14.5 and now landed. The
  locomotion bridge already stepped the vanilla player graph and the vanilla locomotion
  clips already carry their own footstep triggers, so this is routing rather than a step
  timer: `LocomotionGraphEventQueue` hands the third-person graph's fired events to
  `WorldAudioFootstepDirector` once per frame, and the director walks the tag through the
  footstep set on the player's feet to a positional source placed at the capsule bottom.
  New record decoders for `FSTP`, `FSTS`, `IPDS` and `IPCT`, plus `ARMA.SNDD`, which is
  what makes barefoot, light boots and heavy boots sound different without the engine
  choosing anything. Two findings worth keeping: an `FSTS` lists its `XCNT` counts
  walk-first and lays out the `DATA` arrays those counts size **swim-first**, which
  `NPCWerewolfFootstepSet` settles on its own; and the chain ends at a `.wav`, not an
  `.xwm`, so the M9 engine could not have played a footstep — or any door or activator
  effect — no matter how well it was routed. See [footstep records](/formats/footstep.md),
  [world audio playback](/engine/audio.md) and [terrain walk mode](/engine/walk-mode.md).
* **Sound effects are RIFF/WAVE, not xWMA (issue #352)**: all 5,978 `.wav` files in the
  install are uncompressed linear PCM, and a 62-file sweep across the archives found
  `wFormatTag` 1 at 16 bits per sample in every one. `WAVFile` reads them and
  `WorldAudioEngine` picks its playback path by peeking at the RIFF form type: `XWMA`
  streams as before, `WAVE` is scheduled as one buffer and retires itself when it has
  played out. See [RIFF/WAVE container](/formats/wav.md).

* **First-person arms (issue #190)**: milestone 14 item 14.7. The player gets a first-person
  rig — the `_1stperson` skeleton and arm meshes, assembled through the same `ActorAssembler`
  path the third-person body uses and anchored to the eye through the `Camera1st [Cam1]` bone
  the first-person skeleton alone carries — driven by a second `BehaviorGraphInstance` over
  the first-person `0_master.hkx` that `LocomotionBridge` feeds the same variables and events
  as the third-person one, differing only in `IsFirstPerson` and in having its root motion
  dropped. `PlayerRigVisibility` states the whole per-mode matrix as one value: first person
  draws the arms and hides the body, third person and fly do the reverse, the body casts its
  shadow in every player mode, and the arms never cast. Equipment reaches the arms through
  ARMA MOD4/MOD5, which the record decoder now reads; a piece declaring no first-person model
  is dropped with a reason rather than falling back to a mesh skinned to bones the 99-bone
  first-person rig does not have. The arms are encoded into a compressed viewport depth
  slice so they cannot push through world geometry standing against a wall — a deliberate
  deviation, since vanilla's answer lives in its renderer — and the first-person field of
  view is an OpenSky setting, because the install declares none that OpenSky can read. See
  [behavior graph runtime](/engine/behavior-runtime.md) and
  [terrain walk mode](/engine/walk-mode.md).
* **A skinned vertex can be empty in one index space and not the other (issue #190)**:
  6 of the 468 top-level vertices in `1stPersonCuirassLight_1.nif` carry no influence in the
  global `BSVertexDataSSE` stream while the same vertices' partition-local weights are
  populated, which threw the whole file away and left the first-person cuirass invisible.
  An empty global entry now defers to the partition entry, and a vertex empty in both keeps
  zero weights instead of failing the mesh. See [NIF](/formats/nif.md).
* **Third-person player body and camera (issue #189)**: milestone 14 item 14.6. The player
  gets a rendered third-person body, assembled from `Skyrim.esm` `NPC_ 00000007` through the
  same template and visual resolvers a streamed ACHR uses, held by the renderer rather than
  by a cell so it survives every scene swap, and posed by the vanilla `0_master.hkx` behavior
  graph through a `RenderAnimation` conformer that runs on the simulation clock rather than
  the wall clock. `CameraMovementMode` gains `thirdPerson`; `G` cycles fly, first person, and
  third person, and the `World > Camera` selector lists the same three. The orbit framing is
  derived from the measured player capsule and the renderer's field of view, because the
  install declares no camera settings of its own — no `fOverShoulder*` GMST, no `[Camera]`
  section in `Skyrim_Default.ini` — and the zoom collides through the same
  `CapsuleWorldCollider` seam the character does. See
  [Terrain walk mode](/engine/walk-mode.md) and
  [Actor idle animation](/engine/actor-animation.md).
* **Behavior references resolve (issue #189)**: `0_master.hkx` is a shell whose locomotion
  branches are `hkbBehaviorReferenceGenerator` nodes naming other behavior files.
  `BehaviorReferenceSource` follows them into their own graph instances, sharing the
  skeleton and clip source and coupling variables and events by name. See
  [Behavior graph runtime](/engine/behavior-runtime.md).
* **Clip triggers relative to the end of a clip had the wrong sign.**
  `m_relativeToEndOfClip` carries an offset *from* the end and the vanilla data writes it
  negative — `MT_JumpLand` places `JumpLandEnd` at -0.8 — so the absolute time adds rather
  than subtracts. Subtracting put the trigger past the end of the clip, where nothing
  crossed it, and that one sign parked the whole vanilla player graph in `JumpLandState`:
  the root machine entered it on the first ungrounded step and never saw the event that
  leaves. With it fixed the graph reaches its real locomotion states and loads 22 clips
  where it had loaded 4.
* **Blender children are masked per bone.** `hkbBoneWeightArray` scales a child's weight
  bone by bone, which is what an upper-body layer needs; blending Skyrim's arm layers
  without it averages three unrelated poses over the whole skeleton.
* **Composed poses tear skinned actors (issue #354).** Writing any composed pose into a
  skinned actor's palette shards the mesh, while the NIF bind palette renders it correctly —
  including the rig's own reference pose, with no animation involved. The defect is in the
  composition-to-palette path and predates milestone 14, so streamed NPCs are affected
  through `ActorAnimationPlayback` as well. Recorded in
  [Actor idle animation](/engine/actor-animation.md) and tracked separately.

## 2026-08-03

* **One shared xcodebuild invocation (issue #344)**: `build`, `cli`, `test`, `test-one`,
  `install`, `app-path`, and `cli-path` had each spelled out their own command line and had
  already drifted — `install` cold-built into a private `build/install` cache, `test` passed
  no configuration. They now all expand one `xcb` define, and `tools/probe.sh`,
  `tools/realtest.sh`, and `tools/test-ui.sh` share the same values through the new
  `tools/xcodebuild-lib.sh`. Every xcodebuild run goes through
  `tools/xcodebuild-run.sh`, which keeps the whole transcript in `logs/<name>.log` and
  prints only diagnostics, failures, and the closing status — a green `make build` is two
  lines against a 1,300-line transcript. `app-path`/`cli-path` derive the products
  directory instead of paying seconds for `-showBuildSettings`, `install` reuses the main
  cache, `clean` no longer runs `xcodebuild clean` on a directory it then deletes, and the
  SwiftFormat pre-commit hook formats and re-stages in one invocation each. See
  [Build system](/tools/build-system.md).
* **`-only-testing:openskyTests` does not stop the UI bundle from building.** The
  expectation behind the change was that it would; a from-scratch `make test` still
  compiles `openskyUITests`, because xcodebuild builds every buildable in the scheme's Test
  action before it consults the selectors. The flag is kept for its clearer intent, and the
  build cost stays for checked-in test plans (issue #346) to remove.

* **Character-controller bridge (issue #188)**: milestone 14 item 14.5. `LocomotionBridge`
  couples player input and the behavior graph to the M4 capsule controller. Sprint (Option),
  sneak (C, a toggle), and jump (Space) join the input path; the bridge writes the census
  variables and raises the census events into the graph each fixed step, and the controller
  hands back position, vertical velocity, and grounded state on the next one. Movement
  authority is a stated rule: one horizontal source per step chosen by the bridge, vertical
  forces owned by the controller, never both on one axis. Jump, surface swimming with
  hysteresis, and the paused-frame no-op land with it. See
  [walk mode](/engine/walk-mode.md) and [behavior graph runtime](/engine/behavior-runtime.md).
* **Vanilla Skyrim locomotion carries no root motion, and that is measured rather than
  assumed.** Not one of the 2,654 HKX files under `meshes\actors\character\` contains an
  `hkaAnimatedReferenceFrame`, and every locomotion clip leaves
  `hkaAnimation::m_extractedMotion` null; three seconds of driving `mt_behavior.hkx`
  accumulates 0.04 units of root travel. The clips animate in place and the engine supplies
  the travel, so the bridge's default horizontal source is the resolved gait speed, with the
  root-motion branch reserved for data that does animate travel.
* **MOVT decoded so the new gaits have provenance (issue #188)**: no GMST states a sprint,
  sneak, or swim speed, so they come from the movement types the player's gaits are authored
  in — `NPC_Sprinting_MT` 500, `NPC_Sneaking_MT` 47.2, `NPC_Swimming_MT` 80.1 units/s — and
  jump takeoff is derived from `fJumpHeightMin` over the controller's gravity rather than
  hand-tuned. `gmst movement` reports all seven values with their sources. See
  [record decoding](/formats/records.md).
* **State machines, transitions, and clip synchronization (issue #330)**: milestone 14 item
  14.4. `hkbStateMachine` now runs for real — start-state selection across all three
  `m_startStateMode` values, enter and exit notify events, event-driven transitions from a
  state's own array and from the machine's wildcards, `hkbBlendingTransitionEffect`
  crossfades, nested machines, and the four machine-level event ids. Driving the vanilla
  `mt_behavior.hkx` with the events it declares walks `MT_Standing_State` to
  `MT_LocomotionType_State` and back. See
  [Behavior graph runtime](/engine/behavior-runtime.md).
* **The transition flag map was confirmed against the install, not assumed.** The strongest
  piece: `0x100` is set on exactly the 3,340 transitions with a null `m_condition` and
  clear on the 429 that carry one, which is what `FLAG_DISABLE_CONDITION` means. The
  wildcard bits appear only inside wildcard arrays, and `FLAG_TO_NESTED_STATE_ID_IS_VALID`
  only where the id names a state of the nested machine. Bits `0x8`, `0x40`, `0x80`, and
  `0x4000` are never set in the vanilla player graph.
* **Transition conditions are a real little language, and it was recovered from the data.**
  429 authored strings, all fitting one grammar of comparisons, `&&`, `||`, `!`, and
  parentheses over float-valued variables and literals — including variable-against-
  variable (`Speed >= fMinSpeed`) and leading-dot literals (`.25`). A string that will not
  parse, or that names a variable the graph does not declare, blocks its transition and is
  tallied rather than defaulting to true: an animation that does not start reads as a bug,
  while one that starts wrongly reads as engine behaviour.
* **Clip synchronization keys off `m_indexOfSyncMasterChild`, not off a flag bit.** An index
  into a child array cannot mean anything but "these children follow that one", while the
  blender flag bit map is still unconfirmed — so the mechanism that keeps a walk clip and a
  run clip of different lengths in phase is driven by the unambiguous member. 28 blenders
  in the vanilla player graph name one.
* **Two decisions are recorded as decisions.** Transition selection order is priority, then
  own-before-wildcard, then array order, because Havok's tie-break is undocumented in the
  sources consulted and a total order is what makes two instances agree. An interrupted
  crossfade is dropped rather than nested inside the new one, and every drop is tallied.
* The env-gated sweep over all 35 vanilla player behavior files still reports zero
  undecodable objects and zero unevaluated generator classes, and the 8,880
  `stateMachineStartStateOnly` entries item 14.3 recorded are gone.

* **Headless behavior graph evaluation (issue #187)**: milestone 14 item 14.3. A decoded
  Havok Behavior graph now runs. `opensky/Behavior/` holds `BehaviorGraphInstance` —
  variable storage seeded from `hkbVariableValueSet`, a two-phase event queue,
  `hkbVariableBindingSet` application, implicit node activation, and a fixed update order —
  plus clip evaluation over the existing spline-sampling seam, normalized-weight blending,
  selector and modifier semantics, and `BehaviorTally`, the ranked honest-coverage ledger
  in the shape of `ConditionTally`. See [Behavior graph runtime](/engine/behavior-runtime.md).
* **The binding member paths in the vanilla files carry no `m_` prefix.** The authored data
  spells them `blendParameter`, `startStateId`, `selectedGeneratorIndex`, while the
  decoders name their fields after the Havok members, which do. The first version of the
  evaluator resolved every binding correctly and then looked all of them up under the wrong
  key; the probe's new applied-bindings ledger is what surfaced it, and paths now normalize
  on both sides. Measurement over the install, not a guess.
* **Blender flags are decoded but not acted on, on purpose.** `blendParameter` is the
  most-bound member in the player graph, so parametric blending is the largest piece of
  locomotion still owed — but the local decode's flag bit map is not confirmed against an
  independent source, and writing the parametric path against an unverified map would be
  the invented-internals mistake AGENTS.md forbids. Authored weights are used directly and
  every such blender costs one `blenderParametricAsWeights` tally entry.
* **State machines run their start state and nothing else**, which keeps the probe
  meaningful without stepping on item 14.4 (#330): transitions, transition effects, and
  synchronization stay there, and every start-state run is tallied.
* The env-gated probe over the install stepped all 35 vanilla player behavior files, third
  person and first person, 60 updates each: 37,620 generator evaluations, 2,602 events
  fired, 82 clips loaded, zero unresolved clips, zero undecodable objects, zero generator
  classes without a route. `HKASplineAnimationFixture` moved to its own file so the clip
  tests can advance and loop a real decoded spline animation rather than a stand-in.

* **Swift 6 language mode across every target, with a toolchain gate (issue #314)**: the
  last step of the #310 migration. The app and CLI configurations moved from
  `SWIFT_VERSION = 5.0` to `6.0`, joining the test targets #313 had already moved, so all
  eight configurations now compile under strict concurrency checking with no command-line
  override. `tools/lint/swift-baseline.sh` (`make swift-baseline`) asserts both halves —
  Apple Swift 6.3.3 or newer, and every `SWIFT_VERSION` reading `6.0` — and runs from
  `make check`, the pre-commit hook, and the CI `build-test` job. See
  [Swift toolchain and language mode](/tools/swift-toolchain.md).
* **The remaining errors were all one shape: a helper beside a nonisolated type that had
  quietly inherited the target's main-actor default.** Isolation is per declaration, so a
  `private struct` under a `nonisolated struct` is main-actor isolated unless it says
  otherwise. `MusicFieldReader`, `InfluenceAccumulator`, `FFmpegDecodeResources`, the SWF
  parser walkers, `ShadowCascade` and `UIVerticalStack` were all that; each is now
  `nonisolated`, which is what they always were in fact.
* **Two seams needed more than an annotation.** `PapyrusWorldAccess` could not carry its
  bridge across `MainActor.assumeIsolated` until `PapyrusWorldQuestBridge` declared
  `Sendable` (every conformer is a `@MainActor` class and so already was one; only the
  existential needed to say so), and the inventory/container movie bridges now decode an
  `AS2` call into a menu action *before* hopping, because the call itself is not
  `Sendable`. `QuestAliasDecoder`'s four key-path tables went behind one
  `@unchecked Sendable` wrapper with the reason written down, rather than four
  suppressions or four dictionaries rebuilt per subrecord.
* **The interesting failure was a runtime one, not a compile error.** Swift 5 mode let
  nonisolated tests call `SystemMenuSection.readout(for:)` and friends; Swift 6 compiled
  the same call but inserted an isolation check, and the whole test bundle crashed on it.
  Those helpers are documented as pure so they can be tested without AppKit, so the fix
  was to mark the pure section readouts `nonisolated` — not to move the tests onto the
  main actor. `RuntimeStateChangeSection.describe` stayed isolated, because it really does
  read a main-actor provider.
* **Havok behavior node classes (issue #329, roadmap 14.2)**: the node tree below the
  root generator, decoded. Fifty new class decoders — state machines and their state,
  transition and event-property arrays; clip, blender, selector, modifier-wrapper and
  behavior-reference generators; the blending transition effect; conditions and expression
  arrays; thirteen stock modifiers; and the twelve Bethesda `BS*` extension classes —
  each a `nonisolated struct` declaring its own offsets through the 14.1 cursor, with no
  reflection and no class-layout system. `HKBClassRegistry` maps a class name to its
  decoder so the 14.3 evaluator and the CLI walk a graph generically, and
  `HKBGraphTopology` plus `HKBDecodeReport` are the two views on it. See
  [HKX behavior node classes](/formats/hkx-behavior-nodes.md).
* **The full-graph rule now has teeth.** The milestone decided that a census class without
  a decoder is a failed sweep, not a tolerated tally entry, and
  `HKBNodeDecodeRealDataTests` asserts exactly that: across the 35 vanilla player behavior
  files, 31,719 objects decode, no class lacks a decoder, no object fails, and every one of
  the 55 classes the census reported is covered. Unresolved fields: 58,076 `noFixup` —
  absent optionals, which is what Havok writes for a null pointer — and not one
  `outOfBounds`, `sectionMissing`, `negativeCount`, or `undecodableString`. That zero is
  the evidence the offsets are right, and it is the same shape of evidence 14.1 used.
* **Writing the truncated-object test found a real bug in the 14.1 helper.**
  `HKXObjectCursor.pointer(at:)` resolved a fixup without first bounds-checking the
  member's own eight bytes, so a pointer running off the end of a short object reported
  `noFixup` — indistinguishable from a legitimately null optional — rather than
  `outOfBounds`. Since the whole sweep assertion above rests on that distinction, the
  helper was wrong in precisely the way the assertion exists to catch. It bounds-checks
  first now. Worth recording because the bug was invisible against well-formed vanilla
  data and only a deliberately malformed synthetic fixture exposed it.
* **Per-class synthetic coverage is table-driven, not sampled.** `HKBNodeClassTests` runs
  three cases against every class in the registry: a zero-filled object of the class's
  declared Havok size must decode with no miss worse than `noFixup` (so no decoder reads
  past its own class), a 16-byte-truncated object must still decode and report
  out-of-bounds members rather than trap, and a pointer patched to an undefined section
  must report `sectionMissing`. The table's size column is the same one the docs publish,
  and a separate test asserts the table and the registry describe the same set, so a new
  decoder cannot land without its three cases.
* **`openskycli hkx` now prints graph topology.** Below the census it lists the whole-file
  decode histogram and then walks the node tree — state machines with their state counts
  and start modes, clip generators with their animation paths, blender children with their
  weights, transition effects with their durations. `tools/probe.sh` gates on it
  (`mt_behavior.hkx`: 5,115 objects decoded, no class without a decoder, 5,110 nodes
  reached, root state machine `MT_RootBehavior`). The walk reaching exactly five fewer
  nodes than the file has objects is the arithmetic that shows it misses nothing: the root
  container, behavior graph, graph data, string data and variable value set are the five
  that sit above the node tree. Sidebar UI is deferred under the AGENTS.md parser
  exception to 14.5, the first item with a visible consumer — a player the graph drives.
  See [CLI](/tools/cli.md).
* **`make realtest` was missing its `vendor-link` prerequisite**, so the target failed at
  build time in a fresh linked worktree, where `.vendor` is a symlink `make` creates. Every
  other build target already depended on it.
* **Havok behavior object graph and behavior census (issue #186, roadmap 14.1)**: M14's
  first item, and the one that turns the 2026-07-20 "reimplement Havok Behavior graphs"
  line into a scoped decision with measurements behind it. Three parts landed together.
  Shared object-graph resolution (`HKXObjectGraph`, `HKXObjectCursor`) replaces the fixup
  dictionaries `hkaSkeleton`, `hkaSplineCompressedAnimation`, and `hkaAnimationBinding`
  each rebuilt privately; all three were reworked onto it with no behaviour change and
  their tests unchanged, which is what proves the API. The graph-level classes
  (`hkRootLevelContainer`, `hkbBehaviorGraph`, `hkbBehaviorGraphData`,
  `hkbBehaviorGraphStringData`, `hkbVariableValueSet`, plus project and character string
  data) decode the naming and entry points everything downstream keys on. And the census
  sweeps the install. See [HKX behavior graph objects](/formats/hkx-behavior.md) and
  [Havok behavior scope](/decisions/havok-behavior-scope.md).
* **The census is the point, not the parsers.** 2,654 `.hkx` files under the character
  actor folder, zero container parse failures, every one a 64-bit `hk_2010.2.0-r1`
  packfile — so the feared tagfile among the behavior files does not exist and no second
  container parser is needed. 35 behavior files (18 third-person, 17 first-person), 55
  distinct object classes, 301 distinct variable names, 1,985 distinct event names. Every
  one of the 35 graphs is rooted at an `hkbStateMachine`, without exception. That class
  list is what item 14.2 (#329) owes and the name surface is what 14.5 binds to; both are
  now measured rather than guessed.
* **Twelve of the 55 classes are Bethesda's own `BS*` extensions.** A decoder set covering
  only stock Havok classes would leave holes in the middle of the vanilla player graph, so
  the 14.2 class registry has to carry `BS*` as first-class entries.
* **Resolution records misses instead of throwing them.** An unresolvable field yields nil
  plus a reason (`noFixup`, `sectionMissing`, `outOfBounds`, `negativeCount`,
  `undecodableString`); a caller that needs the field converts that into its own typed
  error. `noFixup` is Havok's null optional and is expected — vanilla produces exactly two,
  both `m_ragdollName` on the first-person character files, which have no ragdoll. Every
  other reason means a decoder read the wrong bytes, and the sweep asserts there are none
  across the whole install. That is the evidence the documented offsets are right.
* Scope decided here and binding on the rest of M14: full-graph evaluation over the
  measured class set rather than a native state machine, swim inside the milestone rather
  than deferred to a water one, and first person with full arms rather than a camera mode
  — the install ships a complete parallel first-person behavior set, so the cost is running
  the evaluator twice, not writing a second system.
* `openskycli hkx` now prints the same census fields for one file, so any behavior file is
  inspectable without the test suite.
* **M13 milestone acceptance (issue #185, roadmap 13.6)**: quests are a gameplay loop, not
  five landed parts. The gate proves one quest end to end — running, advanced by a real world
  event through script code, its stage fragment executing and mutating `WorldStateStore`, its
  alias resolved, its title, objective and journal paragraphs on the vanilla page, and a
  mid-quest save resuming into a fresh engine at the same stage. The five parts it stands on
  are #181 (QUST decode and quest VMAD fragments), #182 (quest state component and the
  stage/objective runtime), #322 (quest script instances, `Quest` natives, stage fragments),
  #183 (alias resolution) and #184 (the journal page and the `World > Quests & Journal`
  destination). No new engine behaviour landed here; this issue wired, verified and recorded.
* The synthetic half is the only place the chain is real from end to end, and that is a
  deliberate trade. `M13AcceptanceChain` builds a lever whose compiled `OnActivate` calls
  `SetStage` on a VMAD quest property, and drives it with a raycast use-key press through
  `CellStreamer` — the same entry point `M11ScriptedWorldChain` uses, one call below the app.
  A vanilla quest cannot do that yet: every candidate advances through dialogue.
* **Decision: the real-data gate sets stages from outside rather than through a dialogue
  INFO.** The issue asked for that negotiation to happen here, and the rejected alternative
  was a minimal INFO slice to make one vanilla quest self-advance. It was declined because a
  slice large enough to fire a `SetStage` fragment from dialogue is a dialogue system with a
  quest gate's name on it, and it would have made M13's evidence depend on an undecoded
  record family. The census is what settles it rather than a hunch: 72 quests qualify as
  journal-visible with fragments and no unimplemented condition, and not one of them
  progresses without dialogue.
* **Decision: the quest is started before the lever's cell attaches.** A VMAD object property
  binds to a live handle or to nothing, so a lever naming a dormant quest binds to nothing.
  The rejected alternative was rebinding properties after a quest starts, which would mean a
  second binding pass over every attached reference on every `Start`. Bringing quests up at
  session wire-up and streaming cells in afterwards is what the app already does, so the gate
  does it in that order and says why.
* **Decision: whole-snapshot equality is the synthetic gate's claim, not the real one.** On
  real data `attachRunningQuestScripts` fills the aliases of every start-game-enabled quest
  in `Skyrim.esm`, so a restored store legitimately holds tables the saved one never had. The
  real-data suite compares the quest's own `QuestRuntimeState` and `QuestAliasState` and its
  rendered page instead; the synthetic suite, with exactly one quest defined, keeps the
  stronger assertion including the generated-key allocator position.
* **Evidence:** `M13AcceptanceTests` (the scripted loop, its accounting and the save/load
  resume, no device and no install), `M13AcceptancePanelTests` (one uninterrupted run through
  the real sidebar and the registry-built panel, every readout by accessibility id),
  `M13AcceptanceBudgetTests` (stage fragments inside `PapyrusTickBudget`, quest conditions
  executing no bytecode, the shipping fly-path update validators),
  `M13AcceptanceRealDataTests` (`MGRArniel01` walked end to end with pinned tallies) and
  `M13AcceptanceRenderTests` (the page before and after a stage advance). The real run
  reports 1 quest script instance, 2 fragments queued, 1 alias filled, 1 native call with 0
  unimplemented, 5 `unresolvedReference` binding skips, 1 journal row with 1 objective and 2
  paragraphs, and 14,917 changed pixels on the stage advance — with the advanced page
  byte-identical to a page walked straight to that stage.
* The honest number is the one fault. A headless session loads no cell, so the fragment
  script's five object properties keep their compiler defaults and calling a method on one is
  a call on `None` — `typeMismatch(expected: "Object", actual: "None")`. It is pinned as
  exactly one fault of exactly that kind rather than tolerated as a threshold, and the
  synthetic gate, which does attach a cell, faults zero times.
* **Coverage headline, 2026-08-03, against `Skyrim.esm`.** 1,811 QUST records decode with 0
  failures and 53 skipped subrecords, all three of them the fields xEdit marks unused. 5,220
  stages, of which 726 carry journal text; 5,294 log entries, 771 with CNAM text; 1,452
  objectives over 1,808 targets; 12,891 aliases. Quest scripts: 856 of 1,811 quests (47%)
  carry a fragment table, 5,108 fragments over 847 distinct QF scripts and 259 distinct
  function names. Alias fills: 1 of the 10 fill types the decoder models is implemented, and
  it covers 2,687 of 12,891 aliases (21%) — `unique actor` at 2,900 is the largest gap.
  Conditions: the registry answers 36.2% of the 11,427 conditions quests demand, over 90
  distinct raw indices, with `GetItemCount` (raw 71, 2,136 uses) the hottest miss. Journal
  quests are a minority of the corpus by design: 1,271 of the 1,811 records are type 0, which
  keeps them out of the journal entirely.
* **Journal UI: the `quest_journal.swf` Quests page (issue #184, roadmap 13.5)**: quests are
  now visible to the player. The movie was already open — it has been the in-game system menu
  since issue #231 — but only its System page had ever been driven, and `swf-as2-scope.md`
  named the Quests page the deferred phase-4 contract that would land with its data. It
  lands: `World > Quests & Journal` starts a quest, sets a stage, shows an objective, and the
  vanilla page fills with the plugin's own title, objective line and journal paragraphs.
* Measuring that contract needed two additions to the committed probe, for a structural
  reason worth recording: an AS2 class publishes its methods on a prototype, and a CLIK list
  inherits most of its contract from a base class the movie never registers, so neither is
  reachable from a display-node dump. `openskycli swf action-run --dump-class` prints a
  registered class's constructor and prototype, `--dump-proto` walks a node's whole prototype
  chain. Together they reported `QuestJournalBase.PAGE_QUEST`, `QuestsPage`'s thirty methods,
  and the list base's `EntriesA` / `entryList` / `iSelectedIndex` / `InvalidateData` /
  `ClearList` / `SetEntry`.
* Two details would not have been right if they had been reasoned about instead of driven.
  `InvalidateData` rebuilds only as many entry clips as there are rows, so an emptied list
  keeps showing the previous quest's first objective until `ClearList` hides the surplus —
  and it hides them rather than blanking them, which is why the frame readout counts visible
  clips only. And an objective's display state rides on plain `completed` and `failed`
  booleans on the row: publishing them is what moves the entry clip off its `Normal` frame,
  which `swf quest-journal --objective-state` demonstrates one state at a time.
* Which string table a journal field lives in is measured rather than assumed:
  `swf quest-journal --text` resolves each field out of all three tables and prints what each
  answered. On vanilla `Skyrim.esm` the quest `FULL` and the objective `NNAM` come from
  `.strings` and the stage `CNAM` paragraph from `.dlstrings`, matching the short-name versus
  body-text rule the records page already states.
* Alias text substitution ships with its syntax confirmed from observed data rather than from
  memory: `<Alias=QuestNameLocation>` is a resolved vanilla string, and the Creation Kit
  documents the family under text replacement. An unresolvable tag survives exactly as
  written, because a visible `<Alias=Prisoner>` says "this fill is missing" where deleting it
  would leave a sentence with a hole in it. The M13 target quest carries no tags, so this is
  machinery for the corpus rather than for the gate.
* `J` in world mode is the first key that opens a menu from gameplay. It is wired as an
  accelerator for the panel's own Open control, not a behaviour of its own, which is what
  keeps it inside the app-ui rule against unadvertised keystrokes.
* The real-data gate reports 0 faults, 0 unimplemented opcodes and 0 unhandled invokes of 52
  on the driven page, at 506 draws and 375,575 changed pixels on bring-up. 81 names remain
  unresolved and are listed with their counts; two of them shape the frame rather than the
  data — with no `textField` an entry clip cannot draw its own row text, and with no `height`
  a field keeps its authored size, so a long journal paragraph overlaps the objective list
  beneath it. Both are AS2-runtime gaps, not journal ones.

## 2026-08-02

* **Quest alias resolution (issue #183, roadmap 13.4)**: a running quest now knows which world
  references its aliases stand for. `QuestAliasState` is the eighth `WorldStateComponent`,
  keyed by the same QUST `ReferenceKey` the quest state uses but kept as a slot of its own,
  because the two have different lifetimes: stages survive a `Stop` and the alias table does
  not. The Creation Kit is explicit that "the aliases are not actually 'filled' until the
  quest starts running", so `startQuest` fills, `stopQuest` clears, and a start-up stage does
  both on the same rule.
* The fill pass is a pure function of a record plus a `FormIDResolver`, which is what made
  every documented rule testable on its own: aliases fill in list order (there is no priority
  between fill *types* — the priority is positional), a non-optional alias that will not fill
  refuses the quest start with `QuestError.aliasFillFailed` and writes nothing, a Force Into
  Alias target takes the value of the *last* source that fills it, and reuse of one reference
  across two aliases of one quest is refused unless the second says Allow Reuse.
* The honest half is which failures are the game's and which are OpenSky's. Specific
  Reference (ALFR) is the only fill type implemented, and an unimplemented one is a counted
  skip that never fails a start — refusing a quest because OpenSky cannot run a Find Matching
  Reference search would dress an engine gap as game semantics. The reuse refusal is likewise
  not a start failure: the wiki says the rule "is not required for all fill types" without
  saying which, and enforcing it would refuse thirteen quests `Skyrim.esm` ships that way.
  Location aliases, "Reserves Reference" and any liveness check on a filled reference are
  recorded deferrals rather than guesses.
* The sweep puts numbers on each of those: 12,891 aliases across 1607 quests, 2688 filled, no
  quest blocked from starting. The biggest deferrals are Unique Actor (2900 aliases, 22.5%),
  Location Alias Reference (2036, 15.8%), From Event (1771, 13.7%) and aliases with no fill
  subrecord at all (1678, 13.0%).
* Three consumers were waiting on the table and now read it through one `Sendable`
  `QuestAliasResolution` seam shaped like the globals and quest seams. Condition run-on 5
  (Quest Alias) resolves live, taking its alias index from CTDA parameter #3 and its quest
  from a new `ConditionContext.aliasQuest`, because a CTDA never names one — the record it
  came from does. The CIS1/CIS2 name override resolves to the named alias's ID for a filled
  alias and stays a reason-tagged `unresolvedParameter` for an empty one. Alias-typed VMAD
  object properties bind to the filled reference, so the `aliasObject` binding skip now means
  "unfilled quest alias" and nothing more.
* Alias scripts are the one part of a quest's script set that is not keyed by the quest: a
  `ReferenceAlias` script runs on the reference in its alias, so its instance is keyed there
  and `questAliasInstanceKeys` remembers which quest owns it so a `Stop` still retires exactly
  its own. Fills travel in their own additive `QALS` save chunk rather than as new fields on
  `QSTS`, because `QSTS` entries carry no per-entry length and an appended field would make an
  older build misparse the whole chunk instead of skipping the new part.
* `World > Scripts > Quests` gained the alias half: filled-alias and alias-instance counts, the
  wire-up fill-failure count, the newest fill, and an inspector that lists every alias a quest
  declares with its fill type, its Optional flag and the reference in it — so an empty alias
  and an unimplemented fill type are told apart on screen rather than both reading as blank.

* **Quest script instances, the `Quest` natives and stage fragments (issue #322, roadmap
  13.3)**: quests are scriptable. At session wire-up every quest the #182 state reports as
  running gets its VMAD scripts and its generated `QF_` fragment script instantiated, keyed
  by the QUST record's session-stable `ReferenceKey` plus the script name — the same shape
  a placed reference uses, so `PSCR` persistence, `firedOnInit` and the update timers all
  applied with no change. Quest instances belong to no cell and are in no cell's attached
  set, so nothing a cell does can reach them; `Stop` is the only thing that retires one.
* The `Quest` native class is new: `IsRunning`, `IsCompleted`, `GetCurrentStageID`,
  `IsStageDone`, `Start`, `Stop`, `CompleteQuest`, `SetCurrentStageID`, the three objective
  setters, and the `GetStage`/`GetStageDone`/`SetStage` wrapper spellings shipped
  `Quest.psc` declares. Every one runs through `QuestRuntime`, so the stage and objective
  rules stay in item 13.2 and the natives add none of their own; `Reset`,
  `IsStarting`/`IsStopping` and the alias getters are left to the unimplemented tally
  rather than stubbed, because OpenSky cannot compute them honestly yet.
* Setting a stage looks the stage up in the #181 fragment table and enqueues its fragment
  functions on the normal event queue, so budget bounding, per-instance serialization and
  global order apply to fragments like every other event. The deviations are stated rather
  than hidden: `SetStage` and `Start` are latent in the real engine and immediate here, a
  fragment runs on the transition into a stage only, and a shut-down stage keeps its
  instances alive so the fragment it just queued still runs.
* One general fix fell out of this: a method call on a receiver that has a script instance
  dispatches under the script the function is *declared* in, so `resolveScript` now loads a
  script's ancestors with it. Without the parent chain every inherited native — the whole
  `ObjectReference` family included — arrived under the child script's name and missed the
  registry. Headless native coverage over the vanilla corpus moved from 18 to 47 of 508
  referenced natives, and 108 calls moved out of the unimplemented tally into honest
  "needs a world" failures.
* Wiring: the provider seam gained `QuestDataProviding`, so a session finally builds a
  `QuestStore`; that also gave the four quest condition functions the index they had been
  missing, and `World > Runtime State > Conditions` no longer reports "unresolved quest".
  `World > Scripts` gained a Quests section showing running quests, scripted quests, quest
  instances, fragments queued and the newest fragment.
* Evidence: `PapyrusWorldQuestTests` and `PapyrusNativeQuestTests` over synthetic fixtures,
  including a save taken mid-quest restoring into a fresh runtime with equal instance
  states, and the env-gated `QuestScriptRealDataTests`, which starts the census-chosen
  target quest `MGRArniel01` against the real install and runs its stage-10 fragment with
  zero faults and zero unimplemented natives.

* **Quest runtime state, its mutation API, the `GetStage` family and the `QSTS` save chunk
  (issue #182, roadmap 13.2)**: quests now have session state. `QuestRuntimeState` is one
  more `WorldStateComponent`, keyed by the QUST base record's session-stable
  `ReferenceKey` the same way a GLOB override is, so the whole M10 substrate absorbed it
  without a change: the journal records a `SetStage` exactly as it records a `Disable()`,
  `snapshot()` orders it, and the save writes it as one more additive chunk. Its two sort
  invariants — reached stages ascending and unique, objectives by index with untouched
  entries dropped — are what make two stores that reached the same end state encode
  byte-identically.
* The semantics came from the Creation Kit wiki rather than from memory, and two of them
  are not what an intuition about "current stage" would produce. The current stage is the
  *highest* reached, so setting stage 30 after stage 60 leaves it at 60; and a stage is
  done only if it was explicitly visited, so reaching 60 says nothing about 10, 30 or 50.
  That is why the component stores a set of visited stages rather than a high-water mark,
  and why `setStage` is idempotent for free. Completing a quest deliberately does not stop
  it, because `CompleteQuest()` is documented as flagging completion and nothing else.
* `QuestRuntime` is the headless mutation API beside the store, following the M12 inventory
  precedent: the store stays generic and record-blind, and this layer holds the `QuestStore`
  every mutation validates against. Unknown quest, unknown stage, unknown objective and
  mutating a stopped quest are typed `QuestError` failures that write nothing, never clamps
  — each is a caller bug that a silent no-op would hide inside a quest that simply never
  advances. Stage record flags are honoured because they are plain data: a `startUpStage`
  starts the quest and is the only way to advance a stopped one, a `shutDownStage` stops it.
  A start-game-enabled quest reports running straight off its DNAM flag with no state
  stored at all; vanilla's story-manager and seven-day start machinery is recorded as
  deferred rather than half-implemented.
* Four condition functions came off the #251 demand list with the state to answer them:
  `GetQuestRunning` (56), `GetStage` (58), `GetStageDone` (59) and `GetQuestCompleted`
  (543), reading a `QuestResolution` seam on `ConditionContext` shaped exactly like the
  globals seam. A QUST parameter naming no quest is the reason-tagged `unresolvedQuest`
  with its own tally bucket, never a throw and never a compare against zero.
  `GetQuestCompleted` implements the behaviour the 1.9.32 patch fixed rather than the
  documented bug where it always returned 0. Re-running the real-data sweep moved
  condition coverage of `Skyrim.esm` from 22,470 of 83,759 conditions (26.83%) to 35,460
  (42.34%): the two stage functions alone are 14.6% of every condition in the game, which
  is why quest state was the largest single thing the evaluator could not answer.
* The `QSTS` chunk is additive like `INVN` and `SPWN` and for the same reason — a component
  kind inside `RDLT` is versioned by `formatVersion`, so putting quest state there would
  force every older build to refuse every save with a started quest. Older builds skip it
  by its declared length, saves predating it restore every quest from its baseline, and a
  session that touched no quest writes bytes identical to what the encoder produced before
  the chunk existed. It carries no cell byte, because a quest belongs to no cell.
* No sidebar surface yet, deliberately: nothing in the app session builds a `QuestStore`,
  so quest conditions evaluated in `World > Runtime State > Conditions` honestly report
  `unresolved quest` for now. The journal UI (#184) is the milestone's visible consumer and
  wires the store in; alias fill is #183, quest script instances and stage fragments are
  #322, and HUD quest markers stay undriven.
* **QUST record decode and quest VMAD fragments (issue #181, roadmap 13.1)**: quests are
  now decoded records rather than a record type nothing reads. QUST is the most
  order-dependent layout in the format — a marker subrecord opens a group and every
  following subrecord belongs to it until the next marker — so `Quest` keeps explicit
  open-group state across three stacked sequences (stages with their journal log entries,
  objectives with their compass targets, and alias definitions) instead of the flat field
  switch every other record decoder uses. Two separator fields carry the rest: `NEXT`
  splits the quest's own dialogue conditions from its story-manager conditions, and `ANAM`
  ends the objective run and opens the alias run, which is also what disambiguates the two
  meanings of `NNAM` and of `QSTA`. Inside an alias the field names shadow quest-level ones
  outright — `FNAM`, `CTDA`, `KSIZ`/`KWDA`, `COCT`/`CNTO` all mean something else there —
  so alias fields are routed to the open alias before the quest-level switch ever sees
  them. An alias's "fill type" is not written down anywhere: the Creation Kit implies it
  from which of a dozen mutually exclusive subrecords appear, so each slot decodes into its
  own property and `Alias.fillType` reports the choice afterwards rather than the parser
  guessing intent mid-stream. Every failure costs one subrecord and is counted in
  `QuestTally`; only a non-QUST record throws.
* The QUST tail of `VMAD` graduated from "recorded and skipped" to decoded. A quest's stage
  scripts are not attached scripts — the Creation Kit compiles them into one generated
  `QF_<editorID>_<formID>` script with functions named `Fragment_<n>` numbered in authoring
  order, and this table is the *only* record of which stage and log entry a numbered
  fragment belongs to. The alias-script sections next to it restate their own version and
  object format, which are honoured rather than assumed. A malformed tail rewinds and falls
  back to the old recorded skip, so a quest with a broken fragment table still delivers its
  primary scripts. INFO, PACK, PERK and SCEN keep the skip unchanged.
* The vanilla sweep decoded all 1811 QUST records in `Skyrim.esm` with zero throws: 5220
  stages, 5294 log entries, 1452 objectives, 12,891 aliases, and 856 fragment tables
  holding 5108 stage fragments and 2149 alias script sections, with no tail lost. The 53
  skipped subrecords are exactly the vestigial SCHR/SCTX/QNAM trio xEdit marks unused. What
  actually proves the grouping is right is not the totals but three link invariants that
  cross the group boundaries: every objective target names an alias its own quest declares,
  every fragment names a stage its own quest declares, and every alias script section names
  its own quest — zero misses on all three, which could not hold if a marker were being
  grouped under the wrong parent.
* The same sweep is the milestone's target-quest evidence, written to gitignored
  `logs/quest-census.log`. 62 quests need no condition function outside
  `ConditionFunctionRegistry.standard`, show journal text, and carry stage fragments; the
  cheapest is `MGRArniel01` (0006A086) at 2 stages, 1 objective, 1 forced-reference alias
  and no conditions at all. Quest conditions overall are 11,427 over 90 distinct raw
  indices, 32.7% of which the registry can already answer, so the shortlist is a real
  constraint rather than a formality.
* The M11 VMAD census moved with it. Alias scripts are ordinary script entries and are now
  counted and PEX-bound alongside the primary list, raising scripts to 19,936 and
  properties to 51,145, and the `QUST fragments` skip bucket is empty. `QuestStore` indexes
  the top group the way `GlobalStore` does; quest *state* stays with the runtime (#182).
* **M12 milestone acceptance (issue #180)**: the first repeatable gameplay loop runs end to
  end and has a sidebar path. `M12AcceptanceTests` walks grant, take, transfer, equip, buy,
  sell, drop, save and load in one scripted run over a synthetic plugin, asserting the
  accounting at every step rather than only that the call returned: after the grant — the
  one step that creates items, and it says so — nothing is created or destroyed, gold is
  conserved across every trade, and a brand-new store restored from a real save file is in
  the identical end state, allocator position included. `M12AcceptanceRenderTests` supplies
  the pixel evidence: a taken cell comes back byte-identical to a cell that never held the
  item, a dropped one byte-identical to a cell whose plugin placed it, and an equipped
  actor's silhouette changes with re-equipping its own outfit piece as the control. The new
  `World > Inventory & Equipment` destination covers the three things the milestone left
  without a surface — dev item grants, `XOWN`/`XRNK` ownership reporting for the crosshair
  target, and the inspected actor's equipped set with its appearance skips. Those skips are
  new accounting: `AppearanceSkip` previously reached a log line only for actors that failed
  to render at all, which made a masked or unrenderable equipped piece indistinguishable
  from an equip that silently did nothing. Budgets extend the shipping validators rather
  than adding a second mechanism. Take, drop and equip stay under
  `World > HUD & Interaction > Items` and buying and selling under `World > Container Menu`;
  the acceptance record names all three paths rather than duplicating a control. See
  [inventory and equipment gate](/engine/inventory-equipment.md).

* **M12.2.3 container and barter menus with GMST pricing (issue #179)**: vanilla
  `containermenu.swf` and `bartermenu.swf` are both driven end to end — one bridge, because
  the two movies are two skins on one `ItemMenu` subclass sharing the list components
  `inventorymenu.swf` imports. Each comes up with 0 faults, 0 unimplemented opcodes and 0
  unanswered engine calls (44 and 50 invokes), publishes a real two-sided inventory into
  `EntriesA`, and settles one transaction from each side. The price formula is quoted from
  UESP "Skyrim:Speech" and evaluated from the load order's own `fBarterMin` and
  `fBarterMax` at a fixed Speech of 15, which resolves from `Skyrim.esm` to a factor of
  3.105 locally. Buying and selling go through a new `InventoryRuntime.exchange`, so the
  item and the gold move together or not at all and both land in the world-state journal;
  a merchant with no gold buys nothing and still sells everything. The merchant itself is a
  container reference nominated from the new `World > Container Menu` sidebar destination,
  which is the seam a faction-driven merchant system replaces later. See
  [container and barter menus](/engine/barter.md).

## 2026-08-01

* **System-menu keyboard repaint (issue #300)**: system-menu keys now enter the live SWF
  through `Renderer.updateSWFRuntime`, so the ActionScript selection mutation and the GPU
  command stream synchronize as one operation. The old raw-runtime path moved the movie's
  internal selection but left the last planned frame on screen until an unrelated renderer
  call happened to flush it. A synthetic Metal-gated pixel test pins the bridge itself: a
  down key is consumed and immediately changes the rendered frame. See
  [system menu](/engine/system-menu.md#vanilla-presentation-layer).

* **M12.2.2 `inventorymenu.swf` bring-up and the inventory data contract (issue #289)**:
  the vanilla inventory menu opens, lists what the player carries, filters by category and
  navigates — with zero faults and zero unanswered engine calls.

  The interesting finding was not in the ActionScript. `inventorymenu.swf` brought up clean
  on the first probe — 0 faults, 0 unimplemented opcodes — and still had no list, because it
  **places three characters it never defines**: `ItemCard_mc`, `InventoryLists_mc` and
  `BottomBar_mc` come from sibling movies under `interface\inventory components\` through
  `ImportAssets2`, and only *font* imports had ever resolved. Those placements instantiated
  nothing, so the menu was 11 display nodes and an empty screen. The milestone's largest
  piece turned out to be a format-layer one: `SWFMovieImportMerger` merges a source movie's
  characters, linkage names and `DoInitAction` blocks into the importer under a uniform id
  offset. Uniform, because shifting the whole source id space by one number means there is
  no remap table to get wrong — and getting one id wrong is a silently wrong movie rather
  than an error. Afterwards the same movie is 373 nodes and 16 registered classes.

  Two contract details cost a measurement each and are worth recording. `InvalidateListData`
  is a `GameDelegate` callback the movie registers for *itself*, so invoking it on a display
  path finds nothing and lands in the unhandled count; and it resets `iSelectedIndex` to -1
  as it rebuilds, so a selection written before the rebuild is silently discarded. Publishing
  therefore writes rows, invalidates, then selects.

  One deviation is deliberate and measured. Up and down go through the movie's own CLIK
  focus path and the movie owns the row selection, but **category changes are engine-driven**:
  focusing the category list and sending a key moves nothing, because the movie routes left
  and right through `InventoryLists_mc`'s own panel-state codes rather than through focus,
  and nothing drives that transition without a live `InputDelegate`. The engine changes
  category and republishes instead.

  Real-install gate: 373 nodes, 0 faults, 0 unimplemented opcodes, **0 unhandled of 46
  bridge calls**, 142,741 changed pixels on bring-up. The 53 remaining missing names are all
  CLIK cosmetics; none is a data API. Two probes were promoted to `openskycli` rather than
  thrown away — `swf action-run` (the per-menu bring-up probe the docs had been asking for
  since 8.3) and `swf inventory-menu` — because the real-data XCTest host is unreliable here
  and the next menu will want both. See [inventory menu](/engine/inventory-menu.md) and
  [SWF container](/formats/swf.md).

* **M12.2.1 equipment runtime and actor visual refresh (issue #178)**: equipping now
  changes what an NPC is wearing on screen.

  ARMA `DNAM` is decoded — it was deliberately skipped since M5.2 with a note to restore it
  "when equip-slot priority resolution lands". The first reading of it here was wrong and
  the correction is the useful part of this entry. Priority looked like a visibility rule:
  when two armatures claim a slot, hide the lower one. Probing the install killed that.
  `OrcishCuirassAA` is priority 5 over `body|forearms|calves`; `OrcishBootsAA` is priority
  10 over `feet|calves`. They share the calves slot, so hiding the loser would delete the
  Orcish cuirass entirely — one armature covers the torso *and* the calves. Vanilla draws
  both. The Creation Kit wiki says the same thing once read precisely: priority
  "determine[s] the order of the ArmorAddons", naked body 0, torso 5, gloves over sleeves
  10. So OpenSky sorts worn parts by ascending priority and hides nothing on that basis;
  hiding stays the equipped-slot mask's job, which has an ARMO's own `BOD2` behind it.

  `EquipmentCatalog` and `EquipmentRuntime` (`opensky/Inventory/`) are the runtime.
  Occupancy has two disjoint halves because the game does: biped slots from ARMO
  `BOD2`/`BODT`, and hands from the WEAP `DNAM` animation type. There is no biped bit
  meaning "right hand" — slot 39 is the shield's *armour*, not the hand holding it.
  Equipping displaces everything overlapping in either half, computed whole before anything
  is written, so a refused equip leaves the store untouched and an accepted one is a single
  journal entry however much it displaces. Equipping what the owner does not hold, or
  something with no slots at all, are typed refusals rather than accommodations.

  Visual resolution takes an optional equipped set that *replaces* the `DOFT` chain, not
  merges with it — the baseline equipped set already is the default outfit, so merging
  would re-dress an actor the moment anything undressed it. Everything downstream is
  untouched: same masking, same ARMA selection, same reason-tagged skips. Refresh is the
  M10 `noteStateMutation` cell rebuild, no patching path.

  The hand attachment needed a mechanism that did not exist. `RenderScene` bakes placement
  transforms into draw instances at build time and cell scenes are built on the streaming
  queue, so a weapon cannot be a placement with a fixed transform and follow a hand. The
  one per-frame transform channel that already exists is GPU skinning, so `RigidAttachment`
  rewrites a weapon model as a skinned mesh with exactly one bone named after the
  attachment node, and the pose the actor's clip already computes moves it — no new
  per-frame code and no second update path to keep in sync. Bone names came from
  `openskycli skeleton` over the vanilla rig, never from memory: `Weapon` (bone 43) parents
  to `NPC R Hand [RHnd]`, and the matching NIF node is spelled `WEAPON`, so the bind lookup
  folds case. A mid-clip swap resumes rather than restarts, because the animation clock is
  renderer-owned and a rebuild never touches it.

  Verified on the install: Heimskr resolved before and after an equip that swaps his monk
  robes for an iron cuirass and puts a sword in his hand — robes gone, cuirass on, uncovered
  skin back, weapon at the rig's hand node. Frames in gitignored `logs/`.

* **M12.1.3 pickup, containers and drop (issue #177)**: items now exist in the world loop.
  The six carryable families — `MISC`, `WEAP`, `AMMO`, `ALCH`, `INGR`, `BOOK` — joined
  `ModelBase.supportedTypes`, so a loose item reference resolves a model, a collision shape
  and a new `.take` interaction instead of counting as an unsupported base. `ARMO` stayed
  out on purpose: its world model is `MOD2`/`MOD3` and body pieces resolve through `ARMA`
  addons rather than a single `MODL`, which is the arbitration #178 owns.

  `WorldItemRuntime` and `ContainerSession` (`opensky/Inventory/`) are the headless,
  menu-free operations above `InventoryRuntime`: take, drop, and a container session with
  `contents`, `take`, `takeAll` and `deposit`. Every world change is one `WorldStateStore`
  write, so the journal, the per-cell dirty counts, the cell rebuild and the save see it
  without this layer arranging any of them. Ordering inside each operation puts the
  throwing inventory arithmetic first, so a take that would overflow the player's stack
  leaves the item lying in the world rather than deleting it into nowhere, and a transfer
  that cannot complete writes nothing at all. A container's `isOpen` is set by the session
  rather than toggled by the activation bridge: one activation is one door swing, but a
  container's open state is the lifetime of a session and only the session knows that.

  Drop needed genuinely new machinery, and it is one more component rather than a list
  beside the store. `ReferenceSpawnState` (`opensky/World/SpawnedReference.swift`) holds a
  base, a cell, a placement, a scale and a stack count under a generated `ReferenceKey`, so
  the M10 store, journal, snapshot and save absorb it unchanged. It carries its own cell
  instead of reading `ReferenceStateDelta.cell`, which records where the *last* mutation
  happened and would let a moved item strand in a cell it is no longer in.

  A spawned object is addressed by a FormID synthesized from the key's sequence into the
  `0xFF` mod index. That index is safe by construction, not by convention: a plugin's
  records are numbered by its load-order position and that index is one byte, so no plugin
  record can carry `0xFF`. A sequence past `00FFFFFF` is dropped and counted rather than
  aliased. `effectiveReferences` folds spawns into the input set *before*
  `applyRuntimeState` runs, so exactly one set of rules governs authored and spawned
  placements — the same pass moves or hides them, the same instance resolution draws them,
  the same collision build makes them solid, and a dropped item's mesh and collision shape
  cannot disagree. Taking a spawned object back resets its whole delta rather than marking
  it deleted, so no tombstone accumulates in every later save.

  The `SPWN` save chunk is additive for the reason `INVN` is: a component kind inside
  `RDLT` is versioned by `formatVersion`, so an older build would refuse every save
  containing a dropped item instead of loading the rest of the world without it. An object
  whose only delta is its spawn writes no `RDLT` entry at all. `World > HUD & Interaction`
  gains an `Items` section — take, search, take all, close, drop — with the acceptance
  record in [interaction](/engine/interaction.md#verification) and a ledger row in
  [sidebar acceptance](/tools/sidebar-acceptance.md#acceptance-ledger). See
  [interaction](/engine/interaction.md#world-items),
  [runtime state](/engine/runtime-state.md#spawned-references--objects-the-running-game-placed)
  and [OpenSky save container](/formats/opensky-save.md#spwn-entry-layout).

* **Separator-led sound paths (issue #247)**: `SoundRecordStore` now accepts the
  separator-led `\Data\Sound\...` form authored by Bethesda as Windows root-relative,
  while retaining the drive or volume `:` rejection and the VFS rejection of `.` and
  `..` components. A read-only `Skyrim.esm` probe found 4951 `SNDR ANAM` entries: the old
  policy retained 4641 and dropped 308 separator-led entries plus two genuine `C:` paths.
  The 308 entries represent 291 distinct filenames. After the fix, 4949 entries
  canonicalize and 4930 resolve through the VFS; 19 name absent development assets. A
  synthetic ESM fixture pins the separator-led path through descriptor resolution. See
  [sound records](/formats/sound.md#resolution-and-paths).

* **M12.1.2 inventory state component and accounting (issue #176)**: added inventory to the
  runtime state system as the fifth `WorldStateComponentKind`. `ReferenceInventoryState`
  (`opensky/Inventory/InventoryComponent.swift`) holds an owner's *entire* effective
  inventory — stacks of `(base item FormID, count)` plus the equipped set — rather than a
  difference against the plugin baseline, because a CONT whose `CNTO` list routes through
  an LVLI has no stable "minus one iron sword" representation while its resolved list is
  perfectly stable. The first mutation materializes the baseline into the component; an
  untouched owner keeps no component and re-derives. `WorldStateStore` itself needed no
  change at all, which is the extension point M10.1.2 was designed for.

  `InventoryBaselineResolver` re-derives baselines and caches nothing, the same rule
  `ReferenceState` follows for placements: a container from its `CNTO` list, an actor from
  the default outfit its resolved template chain supplies (reusing `ActorTemplateResolver`
  rather than repeating template resolution), the player and generated owners from nothing.
  Leveled entries expand **deterministically** — `LeveledList.deterministicEntry` plus the
  `useAll` bundle flag, the policy the bind-pose milestone already uses — with a visited-set
  cycle guard and a depth cap; rolling against player level needs a player level no
  milestone has yet. Three more v1 approximations are recorded rather than hidden:
  `chanceNone` is ignored, `NPC_` carries no decoded `CNTO` list so an actor baselines to
  its outfit and not its loot, and a form no index describes stays as a plain weightless
  stack instead of vanishing. An actor's outfit is baselined as *worn*, because otherwise
  every NPC would start naked; slot arbitration stays with #178.

  `InventoryRuntime` is a thin `@MainActor` layer beside the store rather than methods on
  it — the store knows keys and components and deliberately not records, while inventory
  needs item weights and baselines. `transfer` computes both resulting inventories before
  writing either, so a transfer that cannot complete writes nothing and the total across
  owners is conserved. Over-removal is `InventoryError.insufficientCount`, not a clamp.
  Gold is an ordinary `MISC` stack with no separate currency field, defaulting to `Gold001`
  `Skyrim.esm:0000000F` — confirmed with `openskycli record Gold001` against the local
  install, not from memory — and settable, because a total conversion need not use
  Skyrim.esm's gold.

  Serialization is the one place the component model bends. Inventory is a component kind
  in the store and is nevertheless **not** written inside `RDLT`: an `RDLT` component kind
  is versioned by `formatVersion`, so carrying it there would force every older build to
  refuse every save that has one. It travels in the additive `INVN` chunk instead, `RDLT`
  omits the component and omits an entry whose only component was inventory, and the
  decoder merges the two back into one delta per reference. An older build therefore reads
  exactly the bytes it would have written itself, and a pre-`INVN` save loads with every
  owner re-deriving from plugin data. `WorldStateComponentKind.saveTag` became optional to
  express that.

  UI is deliberately deferred: `World > Runtime State`'s journal readout already prints the
  component kind, so inventory mutations surface there with no code change, and a dedicated
  panel belongs with its first visible consumer (#177, #289, #179).

  Evidence: `make check`; `make test`. Four new synthetic suites — component invariants and
  arithmetic, baseline derivation against a synthetic plugin, the accounting API including
  transfer conservation and its all-or-nothing failure, and the `INVN` chunk including the
  older-build tag-rename case. Plus `make realtest
  T='InventoryBaselineRealDataTests/sweepsEveryContainerBaseline()'`: 436 CONT and 5118
  NPC_ baselines resolved from Skyrim.esm with zero invariant violations, and the default
  gold form confirmed on the data as `Gold001` `0000000F`, value 1, weight 0. See
  [runtime state](/engine/runtime-state.md) and
  [OpenSky save container](/formats/opensky-save.md).
* **Non-positional ambience beds (issue #236)**: `WorldAudioSoundDirector` now starts
  each resolved ambience entry through `WorldAudioEngine.playNonPositional`, wiring it
  directly to the descriptor's resolved vanilla category submix. Ambience therefore has
  no fixed start position, panning or distance attenuation, and it is exempt from the
  positional FIFO budget and cell purge. The director remains the lifetime owner and
  retires its source ids on context changes and user controls. The former equal-weight
  per-entry gain split is gone; the category factor is applied once at the shared submix,
  while each player node carries only source and fade gain. Synthetic offline tests pin
  the category mixer connection, non-positional routing, unity source gain and survival
  across distant listener-cell movement. See
  [world SFX + ambience](/engine/world-sfx.md) and
  [world audio playback](/engine/audio.md).
* **M12.1.1 item and container record decode (issue #175)**: decoded the seven carryable
  base families — MISC, BOOK, ALCH, INGR, WEAP, AMMO and the inventory half of ARMO —
  plus CONT contents and reference-level ownership, and indexed them behind
  `ItemDefinitionStore`, the read-only unified item view the inventory runtime (#176) will
  resolve through. Three shared helpers keep the seven decoders from repeating themselves:
  `ObjectBounds` (OBND), `KeywordList` (KSIZ/KWDA) and `InventoryItemFields` (the common
  EDID/FULL/MODL/icon/sound run), with `ItemValue` for the 8-byte value+weight DATA.
  `Container` **composes** `ModelBase` rather than replacing it, so the cell builder and
  interaction path that already consume CONT keep working unchanged and only gain the
  contents.

  Two design calls worth recording. First, containers are indexed *apart* from items: a
  CONT has no gold value and no weight, so forcing it into `ItemDefinition` would have
  meant two dead fields on every container; `container(_:)` sits beside `definition(_:)`
  instead. Second, stackability is deliberately provisional — v1 stacks by base FormID and
  the doc says so, because tempering, enchanting and charge level will each make two
  instances of one base FormID distinct and turn `stackKey` into a compound key.

  Two byte-layout traps are handled by payload size rather than by the plugin's form
  version, because an SSE-only engine still has to read classic-era mod records: WEAP CRDT
  puts its SPEL link at 0x10 in the 24-byte SSE form and 0x0C in the 16-byte classic one,
  and AMMO DATA gained a trailing weight float in SSE. Both are cited to xEdit's `IsSSE`
  branches. Advisory counts (KSIZ for KWDA, COCT for CNTO) are recorded but never used to
  size a read, so a stale count in a modded plugin cannot truncate a list. Effects decode
  as MGEF links only; magic semantics stay out of scope.

  Evidence: synthetic-fixture unit tests for every family covering the wrong-type,
  truncated-field and empty-record cases, plus `ItemDefinitionStoreTests`. The env-gated
  `InventoryRecordRealDataTests` swept Skyrim.esm on 2026-08-01 and decoded **6930 items
  with zero throws and zero skips** (ARMO 2762, WEAP 2484, BOOK 821, ALCH 363, MISC 371,
  INGR 94, AMMO 35) plus 436 containers holding 9597 CNTO entries with 0 COCT mismatches;
  7765 placed references carry XOWN and 118 carry XCNT. The layout invariant that matters
  is that **all 9597 CNTO targets resolve to a record whose type is in the set xEdit
  constrains the slot to** — that would not hold if item and count were being read in the
  wrong order. Decoded output reaches both dev surfaces through
  `RecordTextDump.itemSummary`, verified by dumping `IronSword`, `SkillSmithing1`, `Wheat`,
  `IronArrow` and `BarrelFood01` through `openskycli record`. Full layouts and the dated
  sweep table: [record decoders](/formats/records.md).

* **M11 Papyrus world interaction — milestone acceptance (issue #174)**: M11 set out to
  make vanilla scripts respond to interaction and mutate persistent world state, while
  leaving the quest runtime to M13. It landed the PEX container decoder (#167), bounded
  interpreter (#168), VMAD decoder and binding bridge (#169), native dispatch and M11.1
  census (#170), engine-loop world runtime (#171), `OnActivate` and core
  `ObjectReference` natives (#172), trigger volumes and trigger events (#173), persistent
  update timers (#277), the `World > Scripts` destination (#278), and this overall gate
  (#174). The acceptance surface stays at `World > Scripts`, beside the world state it
  explains, rather than under Developer: pause, step and burst are verification controls,
  but the instances, events and native tally are live properties of the running world.
  The rejected alternative was a new milestone-only panel, which would duplicate the
  permanent surface and leave no durable path after acceptance. The animation boundary is
  also deliberate: `PlayAnimation`-family calls remain `deferredAnimation` deviations
  until M14 instead of pretending a no-op is implemented. The dated honest coverage
  headline is **18 of 508 distinct natives referenced by vanilla scripts implemented
  (3.5%)**, with 18 deferred animations in the 2026-07-30 corpus acceptance run.

  Evidence: `M11AcceptancePanelTests` drives the real sidebar model and registry-built
  panel on one provider set, reads all four accessibility readouts, and exercises
  pause/step/burst/reset; `M11AcceptanceEngineTests` activates through a real
  `CellStreamer`, then saves and restores world state, activation metadata, a script
  variable and a pending timer into a fresh `PapyrusRuntime` through `OpenSkySaveStore`;
  `M11ScriptedWorldAcceptanceTests` pins use key -> dispatch -> native -> delta -> rebuild;
  and `CellStreamingFlyPathTests` pins the new average-and-p95 script budget, its
  reason-tagged error and zero-sample behavior. The env-gated
  `M11AcceptanceRealDataTests` swept 25 Whiterun-area cells, attached 28 instances, drained
  to zero pending events, and pins 5 typed faults, 9 unknown-native calls and 0 deferred
  animations without a crash or hang. It selected VMAD-bound `TrapLinker`
  (`Skyrim.esm:000D97F5`) and ran its retail `defaultActivateToggleLinkedRefOnce` PEX: the
  authored link is an invisible `XMarker`, so the exact retail bytecode runs against an
  in-code visible linked-reference proxy rather than making a false claim about the game
  asset. One use-key dispatch makes 3 native calls with no activation fault or unknown
  call, writes 2 world-state deltas, removes 1 reference from the rebuilt draw set and
  changes 10 pixels. The capture remains at gitignored
  `logs/m11-acceptance-visible.png`. A 6,645-frame Debug fly run measured the attached VM
  update at 0.024 ms average, 0.035 ms p95 and 1.266 ms maximum; the default 0.5 ms
  average-and-p95 ceiling is over 14 times the observed p95 and about 1.5% of a 30 fps
  frame. See [Papyrus virtual machine](/engine/papyrus-vm.md),
  [PEX](/formats/pex.md), [VMAD](/formats/vmad.md), and the
  [sidebar acceptance ledger](/tools/sidebar-acceptance.md).

## 2026-07-31

* **World > Scripts destination (issue #278)**: a new sidebar destination
  (`Destination-scripts`, M11.2.5) gives the in-world Papyrus VM the same kind of live
  panel `World > Runtime State` gives object references — instance counts, a recent-event
  tail, scheduler pause/step/burst controls, and ranked native-tally coverage, all sourced
  through one `ScriptsSnapshot` seam from
  `PapyrusWorldRuntime.scriptsSnapshot(target:targetDescription:)`
  (`opensky/Papyrus/PapyrusWorldScriptsSnapshot.swift`) and the `ScriptControlProviding`
  protocol `GameViewController` conforms to. The key decision is where VM pause lives:
  `PapyrusWorldRuntime.isPaused` gates only `advance(delta:gameClock:)`, returning a zero
  `PapyrusTickReport` and accumulating nothing while set; `stepFixed(gameClock:)` keeps
  running so the panel's step and 20-tick burst controls still work while paused. This
  pause is kept independent of `Renderer.worldSimPaused` rather than reusing it — the
  rejected alternative was routing the panel's pause through the existing
  `MenuModeController`-owned `FrameSimClock`, which `World > Runtime State` already
  established a precedent against: a verification panel must not fight the owner of
  world-sim pause. The two gates compose instead of conflicting. `lastTickReport` retains
  the last report from a tick that actually stepped, and a bounded eight-entry
  `recentEvents` ring with a dropped-event counter backs the events section. Evidence:
  ScriptsPanelTests, DestinationRegistryScriptsTests, PapyrusWorldPauseTests, all green.
  See [Papyrus VM](/engine/papyrus-vm.md).

* **Update timers (issue #277)**: `Form.RegisterForUpdate`, `RegisterForSingleUpdate`,
  `RegisterForUpdateGameTime`, `RegisterForSingleUpdateGameTime`, `UnregisterForUpdate`
  and `UnregisterForUpdateGameTime` now reach a real timer instead of returning a declared
  default, and `OnUpdate` / `OnUpdateGameTime` fire through the world event queue at
  `activationDepth: 0`. `PapyrusUpdateTimerRegistry`
  (`opensky/Papyrus/PapyrusWorldUpdateTimers.swift`) is a fixed-step peer of
  `PapyrusScheduler` rather than an extension of it — a timer carries an interval and a
  slot, never a suspended continuation — and gives each script instance four independent
  slots: {real, game-time} x {repeating, single-shot}. Registering a slot replaces
  whatever it held; the Creation Kit wiki states this for the real-time family only
  ("Subsequent calls to `RegisterForUpdate` will override previous ones … It does not
  interfere with updates registered via `RegisterForSingleUpdate`", confirmed on
  `RegisterForUpdate - Form` via a `web.archive.org` snapshot of `ck.uesp.net`) and OpenSky
  extends it to the game-time family by symmetry — one of six wiki-ambiguous edges the
  implementation resolves and records as a deviation. The other five:
  `UnregisterForUpdate()` and `UnregisterForUpdateGameTime()` each clear both slots of
  their family rather than only the repeating or only the single-shot one, since the wiki
  never says which; a non-finite, zero, or negative interval clamps to zero, firing on the
  next fixed step; a non-persistent instance's pending timers drop on cell unload, the same
  simplification issue #285's trigger-volume purge already applies; a due timer fires at
  most once per fixed step with a repeating timer re-anchoring to now rather than queuing
  one catch-up per elapsed interval, capped further at 24 game hours of forward
  contribution per step — engine policy against a console clock scrub, since without it one
  `SetGameHour` jump from `World > Runtime State` could burst-fire a month of queued
  timers; and OpenSky pauses game-time timers exactly when it pauses real-time ones,
  because both families only advance through `PapyrusWorldRuntime.advance(delta:
  gameClock:)` and a paused frame delivers a zero delta — matching the identical
  menu-mode sentence both `OnUpdate - Form` and `OnUpdateGameTime - Form` state. Real-time
  slots reuse the scheduler's whole-fixed-tick arithmetic; game-time slots consume capped,
  never-negative deltas sampled from `GameClock.totalGameSeconds`, the same policy
  `RendererGameClock.consumeElapsedGameHours()` uses elsewhere. Pending timers of
  persistent instances now persist across a save in a new additive `PTMR` chunk
  (`opensky/Formats/Save/OpenSkySaveDecoderTimers.swift`), sized and shaped like `PSCR`:
  one entry per armed slot, a tagged reference key plus script name completing the
  instance key, the slot as its stable raw-value byte, and the interval and remaining
  delay as `Float64` bit patterns in the slot's own unit (seconds or game hours). Storing
  remaining delay rather than an absolute deadline means a restored timer re-anchors
  against the load-time clock, so the gap between save and load never counts toward it.
  The chunk costs no `formatVersion` bump and an empty timer list writes nothing, so a
  session that armed no timer produces the bytes it always did. Evidence:
  `PapyrusWorldUpdateTimerTests`, `PapyrusWorldUpdateTimerClockTests`,
  `PapyrusWorldUpdateTimerPersistenceTests`, and `OpenSkySaveTimerTests` (round trip,
  determinism, absent-chunk and empty-list equivalence, truncation and bogus-count
  rejection, an unknown slot byte rejected, non-finite and negative durations normalising
  to zero, unknown-chunk skipping, and a live runtime's timers surviving a save and
  restore), all green. Stated limit: a non-persistent instance's timers are not carried
  across cell unload, matching how its other transient state already behaves. See
  [Papyrus virtual machine](/engine/papyrus-vm.md) and
  [OpenSky save container](/formats/opensky-save.md).

* **Trigger volumes fire OnTriggerEnter and OnTriggerLeave (issue #173)**: walking into
  an authored volume now reaches script code. Both authoring sources land in one
  immutable per-cell `TriggerVolumeSet` on `CellScene`: SkyrimLayer 12 NIF bodies, which
  the static collision build previously dropped as non-player-solid, and `XPRM`
  primitives on the REFR itself. `NIFCollisionFilter.isTriggerVolume` names layer 12
  specifically rather than negating `isPlayerSolid`, because layer 15 and the
  no-collision flag also fail that test; `CellTriggerBuilder.swift` collects as a
  satellite of `CellCollisionBuilder.swift` so the solid loop and its
  `filteredBodyCount` accounting are untouched, and the mesh pass reuses the same
  build-queue-confined `NIFCollisionLibrary` cache so no NIF decodes twice. Only `box`
  and `sphere` primitives become volumes — `portalBox` is occlusion room-portal
  geometry, `line` is not a volume, `none` is no shape — and the exclusions are counted
  rather than dropped silently. The median-split AABB BVH moved out of
  `StaticCollisionWorld.swift` into `BoundsSpatialIndex`, which indexes a flat
  `[ModelBounds]`, so both spatial sets share one implementation and one deterministic
  sort order; `StaticCollisionWorldTests` passing unchanged is what pins the extraction
  as behaviour-preserving. Box, sphere and capsule narrowphases are exact for rigid
  transforms with uniform scale, while convex hulls and triangle soups fall back to a
  documented conservative world-AABB test that deliberately over-reports.
  `CellStreamer` tests the player capsule against the resident set once per rendered
  frame rather than per 120 Hz physics substep, because triggers are gameplay-rate and
  the substep loop is a hot path, gated to walk mode exactly as the interaction ray is;
  the authoritative feet position and capsule arrive from `WalkController` as a
  defaulted `PlayerCapsuleState` parameter, so no existing call site changed. Diffing
  that occupancy against the previous frame makes enter and leave edge events: entering
  fires once, dwelling fires nothing, leaving fires once, and a teleport that clears a
  volume between two frames fires enter followed by leave through a bounded swept
  sampling of the travel path that costs a normal walking frame no extra queries.
  Leaving walk mode freezes occupancy instead of clearing it, so switching to fly inside
  a volume does not fabricate a leave. On cell unload the containment policy is explicit
  rather than silent: `emitCellDetached(_:)` releases containment before the detach
  retires instances, which is the only ordering that lets a surviving persistent script
  clean up. The honest limit is that `detach` purges a retired instance's queued events,
  so a non-persistent instance never receives its leave no matter the ordering; both
  outcomes are tested. `PapyrusWorldRuntime.queueOnTriggerEnter/Leave` mirror
  `queueOnActivate` at activation depth 0 with the player as `akActionRef`, iterating
  `instancesByKey.keys.sorted()` so dispatch is deterministic, and
  `PapyrusWorldStateBridge.handleTriggerTransition(_:)` is the streamer-to-VM seam.
  On the parser side, `XPRM` decodes into `PlacedReference.primitive`: a 32-byte struct
  of half-extents, Creation Kit wireframe colour, one unknown float and the shape enum.
  The bounds are half-extents pre-`XSCL`, confirmed by xEdit's `aScale = 2` on the
  bounds floats and UESP's "Bounds / 2" label. `XPRM` does not repeat, so decode follows
  the `XTEL` policy rather than `XLKR`'s: any length other than 32, or a type outside
  xEdit's closed 0...4 enum, throws `ESMError.malformed` instead of shifting fields. A
  `Skyrim.esm` sweep pins the layout — 13668 subrecords on 13668 of 693333 references,
  all 32 bytes, box 10163 / sphere 137 / portal box 3135 / line 233, no `none` and
  nothing outside the enum, every colour channel inside 0...1, 129 zero half-extent axes
  because a degenerate axis is legal, and the unknown float taking exactly the four
  values UESP independently lists (0.15, 0.2, 0.25, 1.0), which is the strongest
  available confirmation of field order. Neither citation pins which axis a sphere's
  radius reads from, so the data decided it: all 137 spheres store the same value in all
  three axes, and the sweep now asserts that so a data set breaking the assumption fails
  loudly rather than misplacing volumes. Adding the case pushed
  `PlacedReference.init(record:)` past the body-length and complexity limits, so the
  optional subrecords moved into a nested `Optionals` accumulator and the new types into
  `PlacedReferencePrimitive.swift`. The verification surface is
  `World > World > Triggers`, reporting resident volume counts split by authoring
  source, the excluded, degenerate and unkeyed sources that would otherwise truncate
  silently, the walk-mode occupancy gate, and a rolling `TriggerEventLog` tail of enter
  and leave events cleared by `TriggerLogClearControl`. NPC and actor occupancy stays
  deferred to M16; the overlap source here is the player capsule only. See
  [Static collision world](/engine/collision-world.md),
  [Papyrus virtual machine](/engine/papyrus-vm.md),
  [Record decoders](/formats/records.md) and
  [NIF Havok collision](/formats/nif-collision.md).

* **Linked worktrees share the vendored ffmpeg (issue #275)**: a linked git worktree
  started with no `.vendor` at all, and Xcode resolves a build phase's declared inputs
  before running any phase, so the missing `$(SRCROOT)/.vendor/ffmpeg/embed-inputs.xcfilelist`
  failed the build during planning, before the `check` phase's actionable "run `make
  bootstrap`" message could run. `tools/ffmpeg/link-vendor.sh` now symlinks a linked
  worktree's `.vendor` to the main checkout's, found through
  `git rev-parse --git-common-dir`, and writes empty placeholder `.xcfilelist`s when the
  shared prefix has no `lib/` yet so Xcode finishes planning and the `check` phase wins the
  race as intended. `tools/vendor-ffmpeg.sh` now always builds into that shared prefix, and
  `make vendor-link` runs the linker as a dependency of `build`, `cli`, `test`, `test-one`,
  `test-ui`, and `install`, so a fresh worktree needs no manual `make bootstrap`.
  `make vendor-prune` (`tools/ffmpeg/prune-vendor.sh`) converts older worktrees that still
  hold their own full copy into symlinks, refusing to act unless the shared prefix is
  complete. [`docs/decisions/ffmpeg-audio.md`](/decisions/ffmpeg-audio.md) corrects the
  previous, wrong claim that a missing prefix left Xcode's declared build-phase paths
  harmlessly absent. Remaining gap: a checkout that has never had a `make` target run in it
  and is opened straight in Xcode.app still fails, since `make` is what creates the symlink
  and the placeholders.
* **A script visibly changes the world (issue #172)**: the player's use key now
  reaches script code, and script code now writes the world. `CellStreamer.onInteraction`
  became a `CallbackFanOut<InteractionEvent>`, so the new
  `PapyrusWorldStateBridge.handleInteraction` subscribes beside the world sound
  director rather than replacing it; it maps the event's load-order-relative
  `FormID` to a `ReferenceKey` through the streamer, writes
  `ReferenceActivationState.activated(by:togglesOpen:)` — its first production
  caller — and queues one `OnActivate` per attached script with the activator as
  `akActionRef`. `togglesOpen` is set only for a door-style `open` action, and an
  event for a reference no resident cell knows is dropped rather than recorded
  under a guessed identity. The player's session-stable identity is
  `ReferenceKey.player`, defined as `.generated(0)`, the sentinel
  `GeneratedReferenceAllocator` already reserved; the vanilla `Skyrim.esm:000014`
  reference was rejected because OpenSky decodes no record for it and it would be
  wrong for a load order without that plugin. Natives reach the engine through the
  new `PapyrusWorldBridge` protocol, exposed to the nonisolated native bodies as
  `PapyrusNativeContext.world`, which took the standard registry from 22 to 37
  entries across three new families: `ObjectReference`
  (`Enable`, `Disable`, `IsEnabled`, `Delete`, the three position getters,
  `SetPosition`, `Activate`, `GetLinkedRef`), `GlobalVariable`
  (`GetValue`, `GetValueInt`, `SetValue`, `SetValueInt`, through
  `Global.ValueType.coerce`), and `Game.GetPlayer`. Every mutation is one
  `WorldStateStore` write carrying the reference's resident `CellSceneLocation`,
  so a scripted change rebuilds one cell instead of every resident one, and a
  headless runtime with no world behind it fails with a reason rather than
  guessing. Script-driven activation chains are capped at
  `PapyrusWorldRuntime.maximumActivationDepth` of 8 and tallied. `PlacedReference`
  learned the repeating `XLKR` subrecord that `GetLinkedRef` follows, in both its
  8-byte keyword-plus-ref and 4-byte ref-only forms, with a null keyword slot
  decoding as untagged; a wrong-size payload costs one link instead of throwing.
  An env-gated sweep of `Skyrim.esm` found 12,477 links on 11,287 references, all
  8 or 4 bytes, with 10,244 untagged and all 56 distinct keyword slots being
  `KYWD` records — which is what pins the field order. Stated gaps: `XESP`
  enable-parent chains are still undecoded so `Enable` and `Disable` act on the
  receiver alone, `TranslateTo` and spline motion are not installed rather than
  stubbed, `abFadeIn`/`abFadeOut`/`abDefaultProcessingOnly` are accepted and
  ignored, `Global.isConstant` is recorded but not enforced, and `Delete` writes
  its delta with no reference counting behind it. The M11.2 gate is one chain in
  `M11ScriptedWorldAcceptanceTests`: a synthetic cell where a lever's compiled
  `OnActivate` bytecode really runs `Self.GetLinkedRef()` and then `Disable()` on
  what came back, driven by a real `CellStreamer` raycast and use key, ending in a
  real `CellSceneBuilder` rebuild whose `runtimeDisabledSkipCount` of 1 is the
  device-free evidence that the door left the drawn set. Also covered by
  `PapyrusWorldActivationTests` (including the `activationCount` and
  `lastActivator` save round trip), `PapyrusWorldActivationSeamTests`,
  `PapyrusNativeObjectReferenceTests`, `PapyrusNativeObjectReferenceLinkTests`,
  `PapyrusNativeGlobalVariableTests`, `PapyrusNativeGameTests`,
  `PlacedReferenceLinkedRefTests`, and the env-gated
  `PlacedReferenceLinkedRefRealDataTests`. See
  [Papyrus virtual machine](/engine/papyrus-vm.md),
  [interaction](/engine/interaction.md), [runtime state](/engine/runtime-state.md),
  and [record decoders](/formats/records.md).

## 2026-07-30

* **Papyrus VM in the engine loop (issue #171)**: the main-actor
  `PapyrusWorldRuntime` now owns the M11.1 `PapyrusRuntime` for a session and
  runs it once per drawn frame. `Renderer.onWorldUpdate` fires from
  `updateWorldSimFromWallClock()` in `draw(in:)`, immediately after the game
  clock advances and gated through a `FrameSimClock`, so a menu-paused frame
  delivers a delta of exactly zero instead of branching around the call.
  `advance(delta:gameClock:)` accumulates wall time into whole 1/30 s steps,
  runs at most 4 per frame and clamps the accumulator afterwards, while
  `stepFixed(gameClock:)` gives offscreen renders and tests one deterministic
  step. Events go through one FIFO queue with global order preserved and
  per-instance serial delivery around a latent suspension, drained under a
  `PapyrusTickBudget` of 32 events and 100,000 instructions with carry-over
  reported in `PapyrusTickReport`. `PapyrusScheduler` now counts whole ticks
  since enqueue rather than accumulating a `realSeconds` double, so
  `Utility.Wait(1.0)` wakes on exactly the 30th step instead of the 31st, and
  gained an `onResume` seam. `CellStreamer` announces `onCellAttached` and
  `onCellDetached` without depending on the VM, distinguishing a first
  integration from a world-state rebuild, a staged coverage cell promoted at
  commit, and an interior rebuild; `Renderer.onFrame` became a
  `CallbackFanOut<SIMD3<Float>>`, fixing the last-writer-wins hazard between
  the streaming and HUD wiring. The script library loads lazily through
  `PapyrusWorldRuntime.scriptProvider` and `PapyrusRuntime.register(_:)`,
  wired to a `PexScriptLoader` over the install's VFS by the new
  `ScriptDataProviding` protocol, with failures remembered in
  `unresolvableScripts`. Instance state persists in the new additive `PSCR`
  save chunk (no `currentVersion` bump, still 1), sorted by
  `PapyrusInstanceKey` for byte-identical re-encoding, with a non-finite float
  normalized to zero where a corrupt `CLOK` is still rejected; a load restores
  Papyrus last, after the world state and the clock, so no script re-runs its
  `OnInit`. Stated simplifications: object and array values are not
  persistable, persistent instances are never retired, `firedOnInit` survives
  retirement, a latent call on a retired instance faults on wake, and a
  reference with several scripts binds object properties to the lowest script
  name. Covered by `PapyrusWorldRuntimeTests`, `PapyrusWorldLifecycleTests`,
  `PapyrusWorldEventQueueTests`, `PapyrusWorldBindingTests`,
  `CallbackFanOutTests`, `CellStreamerPapyrusTests`, the Metal-gated
  `RendererWorldSimTickTests`, and `OpenSkySavePapyrusTests`. Documented in
  [Papyrus virtual machine](/engine/papyrus-vm.md),
  [OpenSky save container](/formats/opensky-save.md),
  [Cell streaming](/engine/cell-streaming.md),
  [Runtime reference identity and world state](/engine/runtime-state.md),
  [Game clock](/engine/game-clock.md) and [Menu mode](/engine/menu-mode.md).
* **Papyrus native dispatch and M11.1 acceptance (issue #170)**:
  `PapyrusNativeRegistry` now dispatches case-insensitive script/function
  pairs through one `.standard` installer and exposes `.empty` for isolated
  hosts. Its 22 entries cover the world-independent `Debug`, `Utility`, and
  `Math` foundation plus three explicitly deferred `ObjectReference`
  animation functions; unknown or invalid calls log and tally the reason, then
  return the declared Papyrus default. `PapyrusScheduler` advances
  `Utility.Wait` and `Utility.WaitGameTime` from injected fixed steps and
  `GameClock` samples, preserves registration order for ties, ignores backward
  clock scrubs, and caps one forward tick at 24 game hours. Seeded random
  functions and bounded debug logging keep the headless result deterministic.
  `PapyrusTallySnapshot` exposes uncapped totals with capped name tables and
  stable rankings for unknown natives, native failures, deferred animations,
  and fault kinds. Synthetic gates pin native values and failures, declared
  fallback defaults, suspension and resume, same-tick wake order, scrub
  policy, typed call-site resolution, and a deterministic M11.1 snapshot.
  The env-gated retail corpus gate decoded 14,302 scripts and resolved 65,477
  call sites naming 508 distinct native pairs; 18 are implemented, an honest
  coverage headline of 3.5%. It drove 577 zero-argument lifecycle entry points
  to terminal outcomes: 240 completed, 337 typed faults, no pending
  continuations, 457 unknown-native calls, and 18 deferred animations. M11.1
  is headless by issue definition, so its ledger record names
  `PapyrusTallySnapshot` and defers the sidebar path to M11.2. Documented in
  [Papyrus virtual machine](/engine/papyrus-vm.md),
  [Papyrus compiled scripts](/formats/pex.md), and
  [Papyrus attachment data](/formats/vmad.md).

* **VMAD decode and script binding (issue #169)**: `ScriptData` decodes the
  common ESM `VMAD` header, script list, statuses, every scalar and array
  property kind, and both eight-byte object word orders with typed,
  bounds-checked failures. Fragment tails on `INFO`, `PACK`, `PERK`, `QUST`,
  and `SCEN` and quest-alias objects skip safely into ranked tallies.
  `PlacedReference`, `PlacedActor`, `ActorBase`, and `ModelBase` now forward
  attachment fields into the shared accumulator. `AttachedScript.binding`
  follows the PEX inheritance chain and applies values through the issue #168
  initial-values seam using the decoded automatic backing-variable name,
  while direct object values travel through
  `FormIDResolver` -> `ReferenceKey` -> caller-owned opaque handle. Missing,
  manual, removed, incompatible, alias, and unresolved values retain their
  compiler defaults with reason-tagged diagnostics. Synthetic models cover
  every value type, both object formats, version-dependent statuses, typed
  malformed cases, an `XXXX`-expanded field above 64 KiB, record forwarding,
  and backing names deliberately unlike `::Property_var`. The env-gated
  retail `Skyrim.esm` sweep decoded all 16,133 VMAD fields over 869,687
  records into 17,407 scripts and 46,493 properties with no failure, tallied
  12,399 alias values and 6,988 fragment sections, and sampled 32 live
  normalized reference keys. Its PEX probe loaded 4,071 distinct scripts and
  observed 46,263 automatic attachments: all used the conventional name and
  every stored name selected a real variable, while implementation remains
  driven by PEX metadata. Documented in
  [Papyrus attachment data](/formats/vmad.md).

* **Papyrus interpreter (issue #168)**: `PapyrusRuntime` and the satellite
  interpreter files under `opensky/Papyrus/` execute all 36 Skyrim PEX opcodes
  headlessly over typed booleans, 32-bit integers, binary32 floats, strings,
  opaque object handles and reference-semantic arrays. Calls use an explicit
  frame stack with a 256-frame default cap rather than Swift recursion; the
  shared one-million-instruction budget, bounded inheritance walks and
  100,000-element array cap make loops, hostile call graphs and allocation
  requests terminate as typed `PapyrusFault` values. Instances keep private
  variables per declaring script, accept an injectable initial-values table for
  compiler-generated property backing variables, and resolve functions by
  derived/parent active state before derived/parent empty state.
  `GotoState` changes later lookup without ending the current function.
  Automatic and handler-backed properties share the same frame machinery.
  Native and otherwise external calls route through the bounded
  `PapyrusRecordingNativeDispatch`; its suspension result retains the frames,
  pending destination and remaining budget for a single-use resume. The
  runtime-owned `PapyrusTally` keeps opcode, native, suspension and fault
  evidence across invocations. Synthetic `PexFixture` models cover every
  opcode's happy path, the coercion and fault matrices, all state priorities,
  injected initialization and a suspend/resume round trip without a compiler
  or game data. Documented in
  [Papyrus virtual machine](/engine/papyrus-vm.md).

* **PEX container decode (issue #167)**: `PexFile` and the bounded big-endian
  decoder under `opensky/Formats/PEX/` turn Skyrim compiled Papyrus scripts
  into typed headers, resolved strings, optional debug information, user flags,
  objects, variables, automatic and handler-backed properties, states,
  functions, all six value kinds, and all 36 Skyrim opcodes. Unknown opcode
  bytes remain countable values instead of rejecting a script; malformed
  framing, strings, indices, object spans and call argument counts throw typed
  `PexError` values. `PexScriptLoader` adds the pure `scripts\NAME.pex` path
  policy, injectable byte loading and VFS archive enumeration.
  `PexInventory` keeps uncapped totals with bounded name tables and stable
  rankings for opcodes and external object/function calls, sizing the virtual
  machine and native registry from the installed corpus. The env-gated
  `PexRealDataTests` sweep on the 2026-07-30 retail install decoded all 14,302
  scripts: 56,474 functions, 310,731 instructions, 130,349 external calls,
  zero decode failures and zero unknown opcodes. It also confirmed that the
  base-game, DLC and Creation scripts report PEX 3.2 while retaining the
  Skyrim layout the UESP page labels 3.0/3.1; newer Fallout 4 structures remain
  rejected and out of scope. Documented in
  [Papyrus compiled scripts](/formats/pex.md).

## 2026-07-29

* **M10 mutable world foundation — milestone acceptance (issue #166)**: M10 set out to make
  the world mutable, persistent, and inspectable, and this gate closes it by proving the
  whole of it through one sidebar destination. The milestone delivered session-stable
  `ReferenceKey` identity over plugin and generated references (#158), the `WorldStateStore`
  of typed component deltas with a bounded change journal and a deterministic snapshot
  (#159), snapshot application during a cell build plus streamer-driven rebuilds so a
  mutation reaches the screen (#160), the `.osav` native save container (#161), the
  `World > Runtime State` destination and the M10.1 acceptance (#162), decoded CTDA
  conditions (#163), the timescale-driven `GameClock` (#164), the GLOB runtime globals layer
  and its value-lookup seam (#165), and the condition evaluator with its function registry
  and tally (#251). The acceptance item extended `World > Runtime State` with three sections
  — Time, Globals and Conditions — rather than adding destinations, because all three
  inspect and mutate the same runtime world state the destination is already named for; the
  destination's overridden-ness became the union of dirty references, overridden globals, and
  a non-default timescale, and its Reset all clears all three. Four decisions each had an
  obvious wrong answer. Pause is a readout rather than a checkbox, because
  `Renderer.worldSimPaused` is owned by `MenuModeController` and a panel toggle would be
  overwritten on the next menu transition, so `World > System Menu` keeps the toggle and the
  Time section only reports what it did. Timescale is not a clock property but the `TimeScale`
  GLOB written through `WorldStateStore.setGlobal`, which is why the timescale and not
  elapsed time is what marks the Time section overridden — a clock that has advanced is a
  world that has been played — while the five projected time globals store no override at
  all, so scrubbing the clock does not reroll weather every tick. The journal tail is one log
  rather than three: the component ring and the globals ring are interleaved by the monotonic
  `sequence` they share, which reproduces exact causal order, and clock scrubs appear there
  because a `GameHour` write journals on the globals ring even though it moves the clock. And
  per-condition reasons come from the single-condition entry point, because
  `ConditionEvaluator.evaluate(_ list:)` returns only a flattened `failures` array;
  `RuntimeStateConditionRunner` evaluates each condition once and recombines the booleans
  with the evaluator's own OR grouping, since evaluating both ways would count every
  condition twice in the tally and draw twice from the `ConditionRandom` stream, making
  `GetRandomPercent` disagree with itself between the verdict and the reasons.
  `RuntimeStateConditionRunner.combine` is pinned against
  `ConditionEvaluator.evaluate(_ conditions:)` across all eight truth-table shapes. Evidence:
  `M10AcceptanceTests` drives mutate reference, mutate global, scrub clock, save, and load
  into a fresh instance through the real sidebar and registry-built panels, reading every
  readout back by accessibility identifier; `M10AcceptanceEngineTests` repeats the round trip
  with no fakes and asserts the journal-independent snapshot equality the gate names, since
  `WorldStateSnapshot.==` deliberately excludes `sequence` and the saved store's snapshot
  (`sequence == 6`) compares equal to the restored one (`sequence == 1`). The `CLOK` and
  `GVAR` chunks carrying the clock and the globals stayed additive and deliberately did not
  bump `OpenSkySaveFormat.currentVersion`, so an older build skips an unknown chunk by its
  declared length and loads the rest. `M10AcceptanceWeatherTests` pins weather and time
  synchronization: `TimeScale` 3600 — one game hour per real second — over 90 steps of 0.5
  real seconds elapses 45 game hours from 08:00 on the vanilla start date to 05:00 on 19 Last
  Seed 4E 201, and with `WeatherSystem.rerollGameHours` at 6 the seven boundaries inside that
  run bound where a weather change may land. `M10AcceptanceRealDataTests` (env-gated on
  `OPENSKY_DATA_ROOT`, `make realtest`) ran the same shape against the retail install: 664
  GLOB records decoded from `Skyrim.esm`, `TimeScale` plugin default 20 with a session
  override of 3600, a pool of 84 selectable weathers in Tamriel, 45.0 game hours elapsed, an
  end state of `05:00 19 Last Seed, 4E 201` with the `GameHour` projection reading 5.0, and
  the observed weather change landing at exactly game hour 6.0. That real-data half needed
  one correction worth recording: "the weather changed" is not by itself proof that a reroll
  fired, because Tamriel's authored chances are lopsided enough that every automatic pick
  across the run can return the same weather and a reroll that reselects the showing weather
  is by design a no-op, so the test forces a contrasting weather, resumes automatic selection
  with the counter at zero, and asserts the cadence structurally. The milestone's honest
  coverage headline stands as measured on 2026-07-29 against the retail Special Edition
  install: 22,470 of 83,759 conditions (26.83%) name a function the registry implements, and
  those five functions are 5 of the 244 distinct raw indices present in `Skyrim.esm`, whose
  range is 0 to 726. Documented in
  [runtime reference identity and world state](/engine/runtime-state.md),
  [conditions](/formats/conditions.md) and
  [sidebar verification convention](/tools/sidebar-acceptance.md).

* **CTDA condition evaluator (issue #251)**: `ConditionEvaluator` in `opensky/World/`
  turns the decoded conditions from #163 into answers. One condition is
  `functionReturn <operator> comparisonValue` compared as `Float`, with exact
  equality because no open source documents a tolerance — an invented epsilon would
  be an undocumented behavior difference hiding inside an otherwise faithful
  comparison. A use-global right-hand side resolves through the #165
  `GlobalResolution.comparisonValue(_:)` seam, and a global nothing defines is a
  reason-tagged false rather than a compare against zero. OR grouping follows the
  Creation Kit wiki's rule that the flag replaces the operator *between* condition N
  and N+1, so consecutive OR-joined conditions form one disjunction block, blocks
  combine with AND, and the wiki's own `A AND B OR C AND D` evaluates as
  `(A AND (B OR C) AND D)`; a trailing OR flag has no following operator to replace,
  so the block simply ends, which is the conservative reading of a rule that does not
  cover that case. Run-on resolution is live for subject, target and reference (the
  `swapSubjectAndTarget` flag applied there) and lazy, so `GetCurrentTime` still
  answers in a context with nothing bound; every other run-on type is a reason-tagged
  false in its own bucket rather than an error. Nothing throws: a condition OpenSky
  cannot answer is false plus a machine-readable `ConditionFailure`, and
  `ConditionTally` — capped name tables with uncapped totals, one bucket per reason,
  ranked accessors — borrows the registry and coverage-tally pattern wholesale from
  the AS2 runtime's `AS2Natives` and `AS2Tally`, which makes the missing coverage a
  measurable result and adding functions later purely additive. Five functions are
  registered, the ones the engine can answer honestly from state it owns:
  `GetCurrentTime`, `GetIsID`, `GetGlobalValue`, `GetRandomPercent` and
  `GetDayOfWeek`. Two open questions were settled by evidence rather than by
  argument. `GetRandomPercent`'s index is xEdit's 77, not the 76 the older gib.me
  list implies: stored index 76 is absent from `Skyrim.esm` entirely while 77 carries
  1,203 conditions with zero parameter words in every case and comparison values
  spanning 0.0 to 100.0, which is exactly a no-parameter percentage signature. And
  `GetDayOfWeek` is anchored on the vanilla start date, since UESP `Skyrim:Calendar`
  documents the 17th of Last Seed as a Sundas and the Creation Kit maps return 0 to
  Sundas; the earlier clock-epoch anchor put the vanilla start on Tirdas and was
  wrong by two days. The extended `ConditionRealDataTests` sweep over the retail
  install reports the honest headline: 22,470 of 83,759 vanilla conditions (26.83%)
  name an implemented function, from 5 of the 244 distinct indices present, with the
  remaining 61,289 conditions ranked by index in the gitignored
  `logs/condition-sweep.log`. Inspector exposure belongs to the M10.2 acceptance
  gate, issue #166. Documented in [conditions](/formats/conditions.md) and
  [runtime reference identity and world state](/engine/runtime-state.md).

## 2026-07-28

* **Game clock + calendar (issue #164)**: `GameClock` replaces the scrubbed time-of-day
  float — one `Double` of game seconds since the calendar epoch, advanced per frame as
  wall delta times the `TimeScale` global (read through the #165 seam, vanilla default
  20, clamped 0-10000) and derived into hour/day/month/year over the UESP-cited Tamriel
  calendar (17th of Last Seed, 4E 201 start). Authority rule: the clock owns time — the
  five vanilla time globals project from it on read via `GlobalResolution(clock:)`, and a
  `setGlobal` on one of them redirects into the clock, journalling through the globals
  ring without storing an override. `Renderer.timeOfDay` became a projection of the
  clock, menu pause freezes game time through the existing `FrameSimClock`, the weather
  runtime now consumes real elapsed game hours (the `accumulateGameHours` wrap heuristic
  is deleted), offscreen/CLI renders hold a fixed clock, and the clock persists in the
  additive `CLOK` save chunk (absent chunk restores the vanilla start). New page
  [engine/game-clock.md](/engine/game-clock.md).
* **GLOB records + runtime globals (issue #165)**: `Global` decodes the GLOB record — EDID,
  the FNAM type character (`s` short, `l` long, `f` float), FLTV, and the 0x40 constant
  header flag — with the layout's one trap handled explicitly: FLTV is a float32 whatever
  FNAM declares, so `GlobalValue` carries the number together with its declared type and
  coerces on every write, rounding half away from zero for the two integer types. An
  unreadable or undocumented FNAM leaves xEdit's Float default in place rather than costing
  the record its value. `GlobalStore` indexes the top group by FormID, by editor ID
  case-insensitively, and by session-stable `ReferenceKey`. Above it, `WorldStateStore`
  gains a globals map beside its reference deltas — typed mutation, reset to the plugin
  default, its own bounded journal window sharing the component log's sequence counter, and
  a separate `onGlobalMutation` callback, because a global changes a number rather than a
  scene and must not drag a cell rebuild behind it. Globals ride the snapshot and persist
  through a new additive `GVAR` save chunk, which needs no `formatVersion` bump. The lookup
  seam is `GlobalResolution`: override first, plugin default otherwise, nil for a FormID
  nothing defines, with a `comparisonValue` entry point shaped for the CTDA operand the
  #251 evaluator will hand it and a `floatValue(editorID:)` one for the #164 clock. The
  first consumer is climate weather selection, which now honours the CLMT `WLST` chance
  global; neither UESP nor xEdit documents what that global means, so the chosen semantics
  (a resolving global replaces the static chance) are flagged as a choice. Documented in
  [record decoders](/formats/records.md),
  [runtime reference identity and world state](/engine/runtime-state.md),
  [OpenSky native save container](/formats/opensky-save.md) and
  [weather runtime](/engine/weather.md).
* **Shared CTDA condition decode (issue #163)**: `Condition` and `ConditionList` in
  `opensky/Formats/ESM/Records/Condition.swift` decode the 32-byte `CTDA` payload —
  comparison operator and flag bits out of the packed first byte, a comparison value that
  is a float or a `GLOB` FormID depending on the use-global flag, the raw on-disk function
  index, both function parameters kept raw behind typed accessors, run-on type, reference,
  and parameter #3 — plus the `CITC` count and the `CIS1`/`CIS2` string overrides that
  attach to the preceding condition. Interpreting the function index and evaluating the
  result stay with the evaluator (issue #251); this is decode only. `MUST` is the first
  consumer: `MusicTrack` now exposes `conditions` and `declaredConditionCount` instead of
  skipping the fields, and every other condition-bearing record type adopts the same
  accumulator as it lands. `ConditionRealDataTests` swept the shipped `Skyrim.esm` and
  decoded all 83,759 conditions across 32,501 records with nothing skipped and nothing
  thrown, which settled two ambiguities the open references leave open: `CITC` counts one
  condition run rather than every condition in the record (all 142 disagreeing records are
  `PACK`, where the remaining conditions belong to nested package data), and the reference
  word is zero in vanilla whenever the run-on type is not Reference, so xEdit marking it
  ignored is mod tolerance rather than observed behavior. Documented in
  [conditions](/formats/conditions.md) and
  [music records](/formats/music.md).

* **Runtime State verification surface and M10.1 state round trip (issue #162)**: the
  `World > Runtime State` panel is now the durable acceptance surface for the whole M10.1
  runtime-state line: Inspect reads the live store's resident/dirty counts, allocator
  position, and change-journal tail; Change disables, enables, and nudges a typed-FormID
  target; Reset clears one reference or every reference back to plugin data; Save/Load write
  and read a named slot through `OpenSkySaveStore`, surfacing a failed load's typed error
  message verbatim. `M10StateAcceptanceEngineTests` proves the engine half with real types
  throughout: mutating two references in a resident cell, evicting and reloading that cell
  by walking away and back, saving the store's snapshot to a real `.osav` slot, and
  restoring it into a brand-new `WorldStateStore` produces an identical snapshot, allocator
  position included, and a `CellSceneBuilder` fed the restored state drops the disabled
  reference and moves the nudged one exactly as the original build did.
  `M10StateAcceptanceTests` drives the panel end to end against a fake provider, and
  `M10StateAcceptanceRealDataTests` ran green against the real install (`make realtest`): a
  ten-plugin load order fingerprinted with `skyrim.esm` first, a four-delta snapshot
  round-tripped through a real slot file and verified against that fingerprint, and a
  changed load order refused on load. Documented in
  [runtime reference identity and world state](/engine/runtime-state.md) (save/load section
  plus the acceptance record), [OpenSky native save container](/formats/opensky-save.md)
  (the new `OpenSkySaveStore` slot-store section), the
  [sidebar verification convention](/tools/sidebar-acceptance.md) ledger, and
  [main-app UI framework](/tools/app-ui.md).

* **Door motion and close SFX (issue #234)**: accepted player door transitions now publish
  typed `motionStarted`, `closed`, and `cancelled` animation boundaries while retaining
  the placed interaction across the asynchronous destination build. The world-audio
  director starts `DOOR BNAM` as a positional loop, stops that exact source on completion
  or failure, and plays `DOOR ANAM` only on a successful close. The same close event
  consumes `CONT QNAM` when container animation gains a producer; runtime-state rebuilds
  remain silent. Offline audio tests prove loop/close/cancellation source lifetime, and
  streamer tests prove the success and failure event sequences. Documented in
  [record decoders](/formats/records.md) and
  [world SFX + ambience](/engine/world-sfx.md).

* **GMST-backed movement tuning (issue #63)**: a strict decoder now derives GMST DATA type
  from the EDID prefix (`s`, `i`, `f`, or `b`) and rejects wrong sizes, invalid Booleans,
  unknown prefixes, duplicate required fields, and trailing string bytes. The targeted
  store walks official masters, installed `Skyrim.ccc` entries, and starred active
  `plugins.txt` entries; later valid values win by EDID. `WalkController` receives one
  immutable configuration, so real scenes use `fMoveCharWalkBase = 100` from `Skyrim.esm`,
  the documented absent-record fallback `fMoveCharRunBase = 370`, and an explicit 32-unit
  step fallback because no Skyrim SE step GMST identifier was confirmed. Synthetic scenes
  and the walk benchmark inject their historic 180/360/32 configuration explicitly.
  `openskycli gmst movement` and `World > World > Camera` report every value and source.
  Documented in [game settings](/formats/gmst.md), [terrain walk mode](/engine/walk-mode.md),
  and [CLI dev tool](/tools/cli.md).

* **Vanilla sound-category taxonomy (issue #235)**: `SNCT` now decodes editor and
  localized names, hierarchy links, flags, and static/default volume values.
  `SoundRecordStore` follows each `SNDR.GNAM -> SNCT.PNAM` chain with cycle protection and
  maps the four vanilla menu-visible categories: Effects, Voice, Music, and Footsteps.
  The audio graph keeps its existing master x category x source x fade gain model while
  the World > Audio panel exposes the four authored category controls; SFX and ambience
  now use descriptor-authored routing with an Effects fallback for absent or malformed
  metadata. A read-only Skyrim.esm probe found 18 categories, 13 direct GNAM targets, and
  exactly four menu-visible nodes. Documented in [sound records](/formats/sound.md),
  [world audio playback](/engine/audio.md), and
  [world SFX + ambience](/engine/world-sfx.md).

* **Real vanilla system menu (issue #231)**: `World > System Menu` now loads
  `quest_journal.swf`, not Skyrim's `startmenu.swf` title screen. The bridge opens the
  measured `PageArray[2]` System page, seeds the page/index/focus state normally supplied
  by the engine-backed tab group, and routes panel and keyboard events through the movie.
  Its rows are `$QUICKSAVE`, `$SAVE`, `$LOAD`, `$INSTALLED CONTENT`, `$SETTINGS`,
  `$CONTROLS`, `$HELP`, `$QUIT`; activating Settings opens the original `$Gameplay`,
  `$Display`, `$Audio` panel through the named `SystemPage.SETTINGS_CATEGORY_STATE`.
  The real-data gate reports 0 faults (159 before issue #136), 0 unimplemented opcodes,
  0 unhandled invokes of 36, 572 draws, 361,540 changed pixels over empty, and an
  11,951-pixel System-to-Settings transition. Captures remain in ignored `logs/`.
  Documented in [system menu](/engine/system-menu.md) and
  [AS2 runtime](/engine/as2-runtime.md).

* **Visible driven start menu (issue #230)**: `startmenu.swf` reaches its populated `Main`
  state through `InitExtensions`, which installs the shared `MovieClip.Lock` helper.
  OpenSky's `Stage` omitted the Scaleform GFx `visibleRect` and `safeRect` objects that
  helper reads; their `undefined` values coerced to zero, so `MenuHolder.Lock("BR")` moved
  the holder from `(1280, 720)` to `(0, 0)` and left its negative authored children outside
  the viewport. `Stage` now exposes separate, full-frame rectangles with pixel-space `x`,
  `y`, `width`, and `height` fields. Synthetic tests pin both objects and their independence,
  while the real-data acceptance gate now requires the driven frame to change pixels. The
  measured menu remains at 0 faults, 0 unimplemented opcodes, 89 draw calls, 0 skipped
  items, and 0 unhandled invokes of 36; its `$NEW`, `$LOAD`, `$CREDITS`, `$QUIT` state now
  changes 5,522 pixels over empty. Documented in
  [system menu](/engine/system-menu.md) and [AS2 runtime](/engine/as2-runtime.md).

* **Faster actor streaming through system LZ4 (issue #56)**: a cold Debug fly-path
  time profile found actor body and FaceGen model loads spending most sampled queue time
  decompressing DDS payloads through the clean-room Swift LZ4 loop. `LZ4` now parses the
  standard frame descriptor, sends independent raw blocks to Apple's
  `COMPRESSION_LZ4_RAW`, and retains the existing Swift decoder for linked blocks whose
  matches need prior output. The `BD` block maximum and BSA decompressed size still bound
  every decode; corrupt blocks and output overflow remain typed failures. A real archive
  sweep found 64,601 independent and 1,036 linked compressed entries across the two mesh
  and nine texture archives. The unchanged 35-cell benchmark kept exact 55 = 28 rendered
  plus 27 disabled and 0 failed actor accounting while average/p95/max fell from
  577.33/3093.60/7218.41 ms to 378.44/2224.46/4427.78 ms. The default actor p95 gate is
  back to 3000 ms. Synthetic tests cover both decoder paths, linked cross-block matches,
  corrupt independent data, and size overflow. Documented in
  [BSA archive](/formats/bsa.md), [actor records](/formats/actors.md),
  [cell streaming](/engine/cell-streaming.md), and [CLI dev tool](/tools/cli.md).

* **Walk-path CLI cleanup (issue #49)**: `bench --walk-path` now rejects the sustained-only
  `--frames` option and every fly-only footprint/build/update budget instead of parsing and
  ignoring them. The walk benchmark configuration no longer carries an unread worldspace
  editor ID, and the shared REFR record dump renders both the reference and teleport poses
  as `(x, y, z)` tuples. Synthetic dump coverage and probe-level usage checks pin the
  behavior. Documented in [CLI dev tool](/tools/cli.md).

* **Stable walk-path timing policy (issues #48 and #244)**: the production route keeps its active-
  physics average at one 30 fps interval in every build and keeps Release p95 at the same
  33.33 ms ceiling. Debug p95 may occupy two intervals (66.67 ms) because the synchronous
  offscreen benchmark includes debug-runtime and scheduler variance; an explicit
  `--budget-ms` remains strict for both metrics. This preserves the shipping performance
  claim and catches sustained Debug regressions without making an occasional second-interval
  tail fail the local probe. The derived `physicsRender` now filters every per-frame timing
  array and drops the full-run `FrameStats` window summaries, whose 120-frame windows cannot
  truthfully describe the active-only sample. Synthetic tests pin Debug, Release, override,
  rejection, and filtering behavior. Documented in
  [terrain walk mode](/engine/walk-mode.md) and [CLI dev tool](/tools/cli.md). This also
  resolves the Debug-only p95 failure reported separately in issue #244.

* **Fail-loud collision partition accounting (issue #46)**: broadphase partitioning now
  returns cached leaves together with a decode-failure count. A wholly degenerate geometry
  contributes no logical shape or estimated bytes, while an invalid leaf in a large
  triangle soup increments the failure count without discarding valid sibling leaves.
  `world-grid` acceptance therefore exposes both post-decode geometry loss paths. Documented
  in [Static collision world](/engine/collision-world.md); synthetic tests cover the
  production empty-geometry build and the mixed valid/invalid partition boundary.

* **Native save container (issue #161)**: `.osav`, OpenSky's own save format, lives in
  `opensky/Formats/Save/`. It is not Bethesda's `.ess` and is not derived from it, so
  [OpenSky save container](/formats/opensky-save.md) is the specification rather than a
  reverse-engineering note; OpenSky never writes an `.ess`, and read-only import of one
  stays a separate far-future item. A short header carries the `OSAV` magic, a
  `formatVersion`, and a length-delimited metadata block holding the creation timestamp and
  the writing build's version — the timestamp is injected by the caller so the encoder never
  reads the clock, and trailing metadata fields a newer build adds are skipped rather than
  mistaken for the next structure. Everything after that metadata is deterministic:
  `OpenSkySaveEncoder` writes entries in the `WorldStateSnapshot`'s canonical `ReferenceKey`
  order and components in ascending on-disk tag order, so two sessions that reached the same
  end state through different mutation orders produce byte-identical tails. The body is a
  load-order fingerprint — per plugin the on-disk name plus the three TES4 HEDR statistics,
  which the Creation Kit rewrites on every edit and which therefore answer "is this the same
  plugin" without hashing archives — followed by tagged, length-prefixed chunks: `GALC` for
  the `GeneratedReferenceAllocator` position and `RDLT` for one delta per dirty reference.
  The two tolerance rules point in opposite directions on purpose: an unknown chunk is
  skipped by its declared length, while an unknown component kind is rejected, because a
  missing chunk is a degraded but honest world and a delta that quietly lost components is a
  wrong one. `SaveReader` bounds every read and turns each underlying failure into
  `OpenSkySaveError.truncated(context:)` naming the structure, every declared count is
  checked against the bytes remaining before storage is reserved, each chunk payload decodes
  through its own cursor so a corrupt inner count cannot walk into the next chunk, and a
  boolean byte must be exactly 0 or 1. Fingerprint verification is kept out of decoding so a
  save can be inspected on a machine with no game install. `OpenSkySaveIO` writes to
  `~/Library/Application Support/OpenSky/Saves/` — never the repo, never the game install —
  through a temp file beside the destination, an explicit `synchronize()`, and a `rename()`,
  so a crash mid-write leaves the previous save intact rather than a file of zeroes.
  Encoding goes through a new `BinaryWriter`, the deterministic little-endian counterpart to
  `BinaryReader`, which future format writers share. Documented in
  [OpenSky save container](/formats/opensky-save.md); the 61 tests use synthetic in-code
  fixtures only, across `OpenSkySaveRoundTripTests`, `OpenSkySaveCorruptionTests`,
  `OpenSkySaveEntryCorruptionTests`, `OpenSkySaveFingerprintTests` and `OpenSkySaveIOTests`.

## 2026-07-27

* **Streaming integration for mutated references (issue #160)**: cell streaming now honours
  `WorldStateStore` end to end. A `WorldStateSnapshot` travels into every cell build, through
  `CellSceneProvider.buildCell(at:state:)`, `CellBuildRunning.enqueue(_:state:)` and the two
  `CellSceneBuilder` entry points, and is applied at one point per build in
  `opensky/World/CellSceneBuilderRuntimeState.swift`: runtime-disabled and runtime-deleted
  references are skipped exactly as initially-disabled ones are, landing in the new
  `runtimeDisabled` / `runtimeDeleted` buckets and in the load summary line, and a
  `ReferenceTransformOverride` replaces the record placement and scale before both instance
  resolution and collision placement, so a moved object's mesh and its collision shape cannot
  disagree. Placed actors run the same visibility check through `ReferenceState`, which means
  a runtime enable now overrides the record's `initiallyDisabled` flag. `GameViewController`
  owns the session `WorldStateStore` and wires it to the streamer, so every dispatched build
  snapshots the live store on the main thread instead of seeing the plugin baseline, and each
  built `CellScene` records the `stateSequence` it was built from. A journalled mutation calls
  `CellStreamer.noteStateMutation(in:sequence:)`, which queues a rebuild of the affected cell;
  `CellStreamCore` grew a `rebuilding` set so the cell stays resident and keeps rendering its
  old scene until the replacement integrates. Staleness is one comparison —
  `CellScene.stateSequence` against the newest mutation sequence for the cell — which resolves
  the mutation-during-an-in-flight-build race without losing or double-applying anything, and
  works around the runner's pending-coordinate dedupe by holding the rebuild request
  streamer-side. An unattributed mutation conservatively rebuilds every resident cell, and an
  interior rebuild re-runs its door transition with no camera so the player is not teleported.
  Documented in [Runtime reference identity and world state](/engine/runtime-state.md) and
  [Cell scene build](/engine/cell-scene.md); tests in
  `openskyTests/CellSceneBuilderRuntimeStateTests.swift`,
  `openskyTests/CellStreamerRuntimeStateTests.swift`, `openskyTests/CellStreamCoreTests.swift`,
  `openskyTests/WorldStateStoreTests.swift` and `openskyTests/WorldStateJournalTests.swift`.
* **Mutable world-state store (issue #159)**: `WorldStateStore`
  (`opensky/World/WorldStateStore.swift`) is the one place runtime deviations from plugin
  data live. State is typed component deltas keyed by `ReferenceKey` — enable state,
  transform override, activation, runtime deletion — behind a `WorldStateComponent`
  protocol and an erased `WorldStateComponentValue`, so M12 inventory and actor values can
  be added without reshaping the store. It tracks dirty references globally and per
  `CellSceneLocation` (now `Hashable`), resets per component or wholesale by re-deriving the
  baseline from the #158 index rather than caching it, logs every mutation to a bounded
  4096-entry ring journal with monotonic sequence numbers, and produces an `Equatable`
  `WorldStateSnapshot` ordered by `ReferenceKey` so identical end states compare equal
  regardless of mutation order. The store is `@MainActor` and lock-free — the snapshot is
  the only value that crosses to the build queue — and it now owns the
  `GeneratedReferenceAllocator` that #158 left homeless. No operation throws: an unknown key
  is runtime state, not malformed input. Documented in
  [Runtime reference identity and world state](/engine/runtime-state.md); tests in
  `openskyTests/WorldStateStoreTests.swift` and
  `openskyTests/WorldStateJournalTests.swift`.

* **SWF focus-path filter (issue #229)**: `routeToMenuHandler` in
  `opensky/Formats/SWF/Runtime/SWFRuntimeFocus.swift` filtered the focus chain to clips that
  define `handleInput` before handing it to the movie. Vanilla nests a list under a plain
  holder clip (`startmenu.swf`: `Menu_mc` -> `MainListHolder` -> `List_mc`), and the movie's
  own `handleInput` forwards down `pathToFocus[0]`, so the raw chain handed it `MainListHolder`,
  which defines no `handleInput`, and the key was dropped. A new `definesHandleInput(_:)`
  helper deduplicates the predicate between the menu-handler search and the filter. Arrow keys
  now drive the `startmenu.swf` list. Test in
  `openskyTests/SWFRuntimeFocusPathTests.swift::theFocusPathDropsHolderClipsWithoutHandleInput`.

* **WMA streaming decode overload (issue #218)**: `WMADecoder` gained a streaming
  static overload `decode(packets:parameters:onChunk:)` that hands each non-empty PCM
  chunk to a callback instead of accumulating the whole file, and the existing
  accumulating `decode(packets:parameters:) -> DecodedAudio` now delegates to it so the
  two share one decode loop. A vanilla music track decodes to roughly 37 MB, so the
  accumulating overload is a memory hazard for whole-corpus sweeps and playback; the
  streaming overload makes the bounded-memory path the obvious choice rather than the
  careful one. The corpus sweep (`openskycli audio sweep`) and the playback streamer
  (`AudioSourceStreamer`) already decode packet-by-packet over the lazy
  `XWMFile.packet(at:)` source and are unchanged — forcing them through the `[Data]`
  overload would buffer every packet's bytes and regress their footprint. Tests in
  `openskyTests/WMADecoderTests.swift` cover the empty-input contract (callback never
  fires) and the non-empty-chunk invariant over garbage payloads; real-PCM behaviour
  stays a probe under `make probe`, as no game audio enters the repository.

* **World audio acceptance gate (M9.2.4, issue #157)**: the M9 gate is closed by
  four changes on one branch. `World > Audio > Output` gained per-category mute
  and solo, generated as `Audio<Category>MuteControl` and
  `Audio<Category>SoloControl` in
  `opensky/Shell/Sections/AudioOutputSection.swift`, backed by
  `WorldAudioEngine.soloedCategory`, `isMuted(_:)`, `setMuted(_:for:)` and the
  single gain function `audibleVolume(for:)` every path reads. The two filters
  are independent and both must pass, so soloing a muted category leaves it
  silent, and unmuting restores the level the slider was left at.
  `AudioStatsLabel` grew a routing line that reads `Mute: none  Solo: none` at
  defaults, and either filter counts as a destination override, so
  `Destination-audio-OverrideIndicator` lights up and the reset clears both.
  Second, the per-frame audio work is now measured: `Renderer.lastAudioUpdateMS`
  feeds `OffscreenBenchResult.audioUpdateMS`, and
  `CellStreamingFlyBenchmarkConfiguration.audioUpdateBudgetMS` (CLI
  `--audio-budget-ms`, default 0.5 ms) is enforced on both `bench --fly-path`
  and `bench --walk-path` through
  `CellStreamingFlyBenchmarkError.audioUpdateExceeded`. Measured on the real
  install (Debug, walk path, 814 active-physics frames, engine attached, no live
  sources): average 0.005 ms, p95 0.014 ms, max 0.028 ms against the 0.50 ms
  budget, so the budget is reasoned headroom over a measured floor, bounded by
  `WorldAudioEngine.maxConcurrentSources` of 8. Third, the evidence:
  `openskyTests/M9AcceptanceTests.swift` drives the whole gate sentence through
  the real app shell with no game data, `WorldAudioTransitionAcceptanceTests`
  runs one synthetic exterior to interior and back sequence proving the ambience
  bed, the music state and the door SFX all react to the same
  `apply(transition:)` (the interior coverage
  `openskyTests/CellStreamerAmbienceTests.swift` explicitly did not claim), and
  the env-gated `M9AudioAcceptanceRealDataTests` reports against the user's
  install into gitignored `logs/m9-audio-acceptance.log`. Fourth, that real-data
  run found issue #246 and it is fixed here. Acceptance record and ledger row:
  [audio](/engine/audio.md), [sidebar acceptance](/tools/sidebar-acceptance.md).
* **Vanilla music tracks resolve to the shipped file (M9.2.4, issue #246)**: no
  vanilla music track could load at all, for two independent reasons confirmed
  against the shipped install. All 269 archive entries under `music\` are
  `.xwm`, with no loose `Data/music`, while all 242 distinct `MUST` `ANAM` and
  `BNAM` filenames in `Skyrim.esm` name a `.wav`, so the authored name resolved
  for nothing; 234 of them resolve once the `.xwm` sibling is tried, and 8 exist
  under neither name because they are leftover development tracks that must keep
  failing. Separately, `canonicalMusicPath` rejected any path with a leading
  separator as absolute, and 209 of the 242 are authored `\Data\Music\...`, so
  only 33 tracks survived canonicalization before playback was ever attempted.
  The fallback lives at the load site, `MusicRecordStore.loadAudioFile(at:load:)`,
  so it can be conditioned on the authored name genuinely not loading rather than
  guessing for every track: the authored key is tried first,
  `shippedAudioSibling(of:)` swaps only a final non-`.xwm` extension, and a track
  absent under both names rethrows the authored path's typed error so a missing
  file is still reported as missing. On the real install the route exterior
  playlist went from 5 resolvable tracks to 61, all loading.
  `SoundRecordStore.canonicalSoundPath` needs no extension rule (`sound\` ships
  5,978 `.wav`) but has the same leading-separator defect, dropping 310 of 4,951
  track entries; that is filed as issue #247 rather than folded in here. Details:
  [music playlists](/engine/music.md), [MUSC/MUST records](/formats/music.md).
* **What the M9 gate does and does not prove (M9.2.4, issue #157)**: the
  evidence is deterministic. `M9AcceptanceTests`, `AudioPanelMuteSoloTests`,
  `WorldAudioEngineMuteSoloTests`, `WorldAudioTransitionAcceptanceTests`,
  `AudioPanelTests`, `DestinationRegistryTests` and `AppSidebarModelTests` pin
  the control-to-provider-to-readout path and the accessibility-id contract,
  `CellStreamingFlyPathTests` pins the audio frame budget, and the env-gated
  `M9AudioAcceptanceRealDataTests` proves the ambience, sound and music records
  behind the Whiterun route resolve to files the archives really ship. None of
  that is a sound. The audible half of the gate is a human step — the routes
  written down in [world SFX + ambience](/engine/world-sfx.md) and
  [music playlists](/engine/music.md), plus the mute and solo pass in
  [audio](/engine/audio.md) — and nothing in the repository records that anyone
  has performed it, so the milestone should be read as behaviour proven at the
  seam and still awaiting one listening session. Vanilla effects and ambience
  are `.wav`, which no decoder here reads yet, so parts of that session cannot
  pass until a PCM `.wav` reader lands. Related issues filed while doing this
  work: #244 (walk-path p95 exceeds the 33.33 ms frame budget in Debug; resolved by the
  build-aware timing policy above), #245 (resolved by applying the active-physics
  frame mask to every per-frame metric), #246 (fixed here) and #247
  (`canonicalSoundPath` leading-separator rejection).

## 2026-07-26

* **Skills rewritten against the skill-authoring best practices**: the six skills in
  `.AGENTS/skills/` were audited against Anthropic's skill-authoring guidance and
  reworked. All six were renamed to gerund form (`commit` ->
  `committing-and-landing-work`, `format-parser` -> `implementing-format-parsers`,
  `docs-wiki` -> `writing-wiki-docs`, `probe` -> `probing-real-game-data`, `app-ui` ->
  `building-app-ui`, `delegate` -> `delegating-to-subagents`), and every `description`
  was rewritten in third person because that field is injected into the system prompt
  and drives skill selection. The `docs-wiki` description had advertised "todo hygiene",
  a topic its body never covered. Machine-specific and third-party state that three
  skills asserted in the present tense with no date — missing TCC permissions, the
  suspended CI, UESP's HTTP 403, the `TES5Edit` default branch — moved to the new
  [local environment](/tools/environment.md) page, where each entry carries an
  observation date and the condition that retires it; `AGENTS.md` "Gotchas" now keeps
  only durable repo facts plus a pointer. `probing-real-game-data` had contradicted
  itself, ranking `Renderer.renderOffscreen` first in a list and then declaring the CLI
  "first-choice, not a fallback" four lines later; the CLI promotion is now scoped to the
  hang case it was written for. `building-app-ui` dropped from 115 lines to a navigation
  overview, since its panel base-class walkthrough, spacing scale, and
  `CollapsibleSectionView` internals were already in [app-ui](/tools/app-ui.md);
  that page and [sidebar acceptance](/tools/sidebar-acceptance.md) gained `## Contents`
  lists, and the reference cycle between them was cut so they read in one direction.
  Skills now use repo-relative doc paths, because the bundle-absolute `/tools/...` form
  is ambiguous outside `docs/` against the repo-root `tools/` directory.
* **Music verification surface (M9.2.3, issue #156)**: `World > Audio` gains a
  fourth section, `Music` (`opensky/Shell/Sections/AudioMusicSection.swift`),
  so the playlist director is reachable without a CLI command. It carries the
  `AudioMusicEnabledControl` toggle, an `AudioMusicTypeControl` picker offering
  `None (automatic)` ahead of the sorted MUSC editor ids, an
  `AudioStopMusicControl` button, and the `AudioMusicStatsLabel` readout showing
  the derived state, the playing playlist and track, and any error. Forcing a
  playlist is panel-local state (nothing on the provider records it), so the
  section reports itself overridden on a force or a disabled director while the
  static mirror the `audio` destination unions in judges only the toggle;
  resetting the destination re-enables music, stops it so the precedence chain
  resolves again, and the shell's cached-panel reset returns the picker to
  automatic. Accessibility ids are pinned in `AudioPanelTests` because
  `make test-ui` is blocked on this machine. Acceptance record and ledger row:
  [music playlists](/engine/music.md),
  [sidebar acceptance](/tools/sidebar-acceptance.md).
* **Music selection + director (M9.2.3, issue #156)**: the runtime that turns
  the MUSC/MUST records into playing music. `MusicCatalog.swift` is pure value
  logic: a `MusicContext` from the streamer resolves through the
  `CELL.XCMO -> REGN.RDMO -> WRLD.ZNAM` precedence chain into a `MusicSelection`
  carrying the winning playlist, its ordered playable tracks, an advance policy
  derived from the MUSC flags (`Plays One Selection`, `Cycle Tracks`,
  `Maintain Track Order`), and the crossfade duration (`WNAM`, else two seconds,
  else zero for `Abrupt Transition`). Palettes expand depth-bounded and
  cycle-safe; silent and unplayable tracks are filtered; an unordered playlist is
  shuffled deterministically from a context-derived seed rather than from
  `Hasher`. The three states the milestone names are derived, not authored:
  `interior` from the cell type, `town` from the `MUSTown` editor-id convention,
  `exploration` as the catch-all — limits written down in the doc.
  `WorldMusicDirector` owns the non-positional music sources (nothing else will
  retire them), crossfades on a selection change with the stage-2 recipe,
  advances the playlist when the engine retires a finished stream, and keeps the
  SFX director's three invariants (single apply path, remembered desired state,
  live-source-derived readout). `CellStreamerMusic.swift` emits the context from
  the same two sites as the ambience emission, `CellScene` now carries the cell
  and worldspace music links, and the renderer's paused-aware audio tick drives
  the director. `AudioControlProviding` gained the music members the panel stage
  binds to. See [music playlists](/engine/music.md); covered by
  `MusicCatalogTests`, `WorldMusicDirectorTests` and `CellStreamerMusicTests`.
* **Non-positional playback + gain ramps (M9.2.3, issue #156)**: the audio
  engine primitive a music crossfade needs. `playNonPositional(fileData:)` /
  `(buffer:)` start a source with the file's own channel layout wired straight
  into `categoryMixers[category]` — no mono downmix, no panning, no distance
  attenuation. Routing is explicit (`AudioRouting` on `ActiveAudioSource`),
  and a non-positional source is exempt from both the FIFO source budget
  (which now counts positional sources only) and the cell purge, so a music
  bed survives an effect burst and the world streaming around it. The category
  factor moved to whichever stage applies it once: player node when positional,
  submix when not. `WorldAudioEngineFades.swift` adds `GainFade` plus
  `fadeSource(id:to:overSeconds:)`, `fadeOutAndStopSource(id:overSeconds:)` and
  `advanceFades(deltaTime:)`, advanced from the renderer's paused-aware frame
  delta (now threaded through `updateAudio(deltaTime:)` into
  `tick(listenerCell:deltaTime:)`) rather than any wall clock, so fades are
  deterministic and freeze in menu mode. The fade factor is folded into the
  node-volume product, so a slider move mid-crossfade cannot stomp a ramp; the
  documented invariant is now master x category x source x fade. Snapshot rows
  gained `isPositional`, `fadeGain` and `isFading`. See
  [world audio playback](/engine/audio.md); covered by
  `WorldAudioEngineNonPositionalTests` and `WorldAudioEngineFadeTests`
  (offline manual rendering, explicit deltas).
* **Music records (M9.2.3, issue #156)**: added the MUSC/MUST format layer that
  the music director builds on. `MusicType` decodes the playlist flags,
  priority, ducking and fade duration plus the ordered MUST link list;
  `MusicTrack` decodes the track type tag, duration, fade-out, track and finale
  filenames, cue points, loop data and palette children. The three world links
  that select a playlist are now decoded too: `CELL.XCMO`, `WRLD.ZNAM`, and
  `REGN.RDMO` (previously skipped). `MusicRecordStore` indexes both record types
  eagerly, expands a MUSC into its ordered tracks, and canonicalizes ANAM/BNAM
  filenames under the `music\` root — a separate rule from the `sound\` root
  `SoundRecordStore` applies. The store is exposed through `AudioDataProviding`
  so the director stage can pull it. See [music records](/formats/music.md);
  covered by `MusicRecordTests`, `MusicRecordStoreTests`, plus the new field
  cases in `CellRecordTests`, `RegionRecordTests` and `RecordDecoderTests`.
* **Agent instruction surface rightsized**: root `AGENTS.md` cut from 285 lines /
  16.6 KB to 180 / 9.8 KB, applying Anthropic's context-engineering guidance for
  Claude 5 generation models (spend tokens on gotchas, not on what the file tree and
  `make help` already say; disclose progressively through skills instead of
  front-loading). Removed: the repo tree, the make-target list, the
  reverse-engineering section (verbatim in the `format-parser` skill), the generic
  Swift conventions, and the per-skill "Core:" restatements that made every skill
  rule readable twice in two phrasings. Fixed a drift that had made the contract
  wrong: the quoted SwiftLint thresholds claimed "type body ≤250" and "identifiers
  ≥3 chars", but `tools/lint/.swiftlint.yml` configures neither
  `type_body_length` (SwiftLint default warns at 200) nor a 3-char minimum
  (`identifier_name.min_length` is 2, with a one-character allowlist) — prose now
  points at the config instead of copying it. New nested `openskyTests/AGENTS.md`
  (plus `CLAUDE.md` symlink, matching `openskycli/`) takes the test-writing rules
  that were reachable only by loading the `probe` skill: the `@MainActor`
  requirement, env gating, `make realtest` versus `xcodebuild test`, and the
  synthetic-fixture helpers. `probe` shrank to the genuinely task-scoped parts.
* **Two prose rules became gates**: new `tools/lint/no-game-content.sh` is the single
  source of truth for the game-content rules and runs from both the pre-commit hook
  (staged files) and `make lint` via `make no-game-content` (the whole tracked tree,
  which also catches a blob arriving by merge or rebase). It now rejects any tracked
  raster image outside `opensky/Assets.xcassets/`, since a frame OpenSky renders
  embeds the user's game assets — previously documented only in prose and violated
  by earlier milestones. New `.githooks/commit-msg/20-no-ai-trailers.sh` rejects
  `Co-authored-by:`, `Generated-by:`, `AI-Generated-by:`, `Assisted-by:`, and
  `Model:` trailers, which the harness's own default appends. Stale
  `AGENTS.md "Git workflow"` comments in four hook scripts now point at the `commit`
  skill.
* **World SFX + ambience (M9.2.2, issue #155)**: the world sound director
  wires the M8 interaction-event seam to one-shot SFX and the streaming
  cell lifecycle to a positional ambience bed. Door open SFX plays under
  `.effects` on use-key activation; per-cell ambient SNDR set plays under
  `.ambience` and follows exterior region areas (`REGN.RDSA`) or interior
  acoustic spaces (`CELL.XCAS -> ASPC.SNAM` + the `ASPC.RDAT` interior-only
  region borrow). The director subscribes to the existing
  `CellStreamer.onInteraction` and a new `onAmbienceContextChanged`; the
  M11 Papyrus OnActivate subscriber will join alongside, not replace.
  Verification: `World > Audio > SFX & Ambience` (independent enable
  toggles, force-stop button, last-SFX + current-bed readout) plus
  `ModelBaseSoundTests`, `RegionRecordTests` (RDSA), `CellRecordTests`
  (XCAS), `AcousticSpaceRecordTests`, `AmbienceCatalogTests`,
  `WorldAudioSoundDirectorTests` (offline render), `CellStreamerAmbienceTests`,
  extended `AudioPanelTests`. Probe against Skyrim.esm: 45 ASPC, 53 REGN with
  sound area, 687 RDSA entries; RDSA.Chance pinned at 0.01-1.0 (issue #237
  closed); all 497 activator/door/container sound references target SNDR
  directly. Decoders: `ModelBase.Sounds` (DOOR SNAM/ANAM/BNAM, ACTI SNAM/VNAM,
  CONT SNAM/QNAM — QNAM, not ANAM, is the close-sound field),
  `Region.SoundEntry` (12-byte RDSA struct under type-7 RDAT),
  `Cell.acousticSpace` (XCAS), new `AcousticSpace` (ASPC, with the `RDAT`
  FormID-vs-area-header collision handled). Doc: [world SFX + ambience](/engine/world-sfx.md),
  [acoustic space](/formats/acoustic-space.md); records / weather / index
  updated. Door close SFX (needs animation event), AudioCategory rename
  (provisional taxonomy), and non-positional ambience bed (current stopgap is
  positional-at-listener) filed as #234 / #235 / #236. The mandatory acceptance
  record (sidebar path, `Destination-audio`, the three section control ids, the
  `AudioSfxStatsLabel` readout, and the covering tests) is written in both places
  the convention requires: the surface section of
  [world SFX + ambience](/engine/world-sfx.md) and a new row in the
  [acceptance ledger](/tools/sidebar-acceptance.md).

* **Ambience beds loop, and the toggle toggles (M9.2.2, issue #155)**: review
  of the world sound director found two functional gaps. A bed source had no
  loop path, so it played through once and the engine retired it while the
  panel still reported a bed as current; `AudioPlayRequest.loops` now starts a
  continuous source whose streamer resets the decoder and rewinds at end of
  file (a pass that decoded nothing ends instead, so an undecodable file cannot
  spin the decode queue). The `ambienceEnabled` checkbox set a flag without
  acting on it; both the checkbox and a context change now run one
  `applyAmbienceState()` path, so unticking retires the playing bed and
  re-ticking restarts the bed the last context resolved. The readout is derived
  from live engine sources, so it reports `none` once nothing is playing.
  `WorldAudioEngine.playPositional` returns the new source id rather than
  leaving the caller to guess it from `sources.last`. Tests:
  `WorldAudioDirectorAmbienceTests` (new suite, fixtures shared through
  `WorldAudioDirectorFixtures`), `WorldAudioEngineTests`
  `loopingSourceKeepsPlayingPastItsMaterial`, and the pure rewind policy in
  `AudioSourceStreamerTests`. Docs: [world SFX + ambience](/engine/world-sfx.md),
  [audio engine](/engine/audio.md).

* **M8 milestone acceptance (M8.5.3)**: the interaction + UI shell milestone is
  accepted end to end from the main app alone. What M8 delivered, in the order
  the gate walks it: a screen-space UI layer with a glyph atlas and localized
  strings (M8.1), engine-owned menu mode with a world-sim pause (M8.1.2), a SWF
  presentation layer that renders vanilla movies (M8.2) and runs their
  ActionScript (M8.3), walk-mode interaction targeting driving the real
  `hudmenu.swf` (M8.4), and the system menu with its settings placeholders
  (M8.5.1). The acceptance flow is one session with no CLI and no keystroke-only
  path: select `World > World` and switch `CameraMovementModeControl` to Walk,
  move to `World > HUD & Interaction` and A/B the live HUD with
  `HUDCrosshairControl`/`HUDLayerEnabledControl` while `HUDElementsStatsLabel`
  and `HUDTargetStatsLabel` report the movie and the selected target, pause from
  `Developer > UI Lab` with `UIMenuPushControl` (`UIMenuStatsLabel` reads
  `World sim: paused`), change `World > Environment > Sun shadows` while paused,
  then resume with `UIMenuPopControl` and find the setting and both overrides
  still in place. `World > System Menu` is accepted as the second, gameplay-facing
  pause. The evidence is the new `M8AcceptanceTests`, which drives that exact
  sequence through the destination registry's own panel factories, the real
  `AppSidebarViewController` (selection callback and override dots), and the real
  `MenuModeController`, reading every readout back out of the built view
  hierarchy by accessibility identifier; the shared `FakeWorldProviders` fixture
  now runs menu mode on that controller instead of a stored snapshot, so a pushed
  menu reports the pause the engine would. Per the
  [sidebar verification convention](/tools/sidebar-acceptance.md), no A/B capture
  was produced: the deterministic suite is the gate, and a rendered frame would
  embed the user's Bethesda assets. One honest gap is recorded rather than papered
  over — no readout names the camera's movement mode, so walk mode is proven by
  the selector state plus the sidebar override dot. `make test-ui` stays blocked
  on this machine (TCC), which is why the gate is a unit-level test.
  See [screen-space UI](/rendering/ui.md) and
  [sidebar acceptance](/tools/sidebar-acceptance.md). Closes #150.
* **Sidebar verification convention (M8.5.2)**: the standing obligation to record
  a milestone's main-app acceptance surface now has a format and one home.
  [sidebar acceptance](/tools/sidebar-acceptance.md) defines the fixed record —
  sidebar path, `Destination-<id>`, the control ids exercised, the readout id
  that proves the change, the deterministic tests that cover it, and an optional
  local A/B note — and carries the ledger of every recorded surface, backfilled
  from the six different phrasings the records had been scattered across
  (`World > Environment` for M3 distant LOD through M7.6, `Developer > UI Lab`
  for M8.1.4/M8.2.5/M8.3.3, `World > HUD & Interaction` for M8.4.2/M8.4.3,
  `World > System Menu` for M8.5.1, `World > Audio` for M9.1.3). Milestones
  predating the rule and surfaces with no recorded path are listed as not
  recorded rather than reconstructed. The evidence bar is stated explicitly:
  the existing deterministic suite — panel geometry and accessibility-id
  assertions plus `DestinationRegistryTests` and the offscreen acceptance tests
  — is the evidence, and changed-pixel A/B captures are optional, local-only,
  and never committed, because a rendered frame embeds the user's Bethesda
  assets. AGENTS.md, [app-ui](/tools/app-ui.md), and the `app-ui` skill now
  point at the convention instead of restating a rule with no format. Docs only
  — no behavior change. Closes #149.
* **System menu (M8.5.1)**: `World > System Menu` adds the Resume / Settings /
  Quit selector and the two settings placeholders the milestone names. The
  selector (`opensky/UI/SystemMenuModel.swift`) is toolkit-free and movie-free,
  so it works with no install; opening it pushes `SystemMenu` onto the engine
  menu stack, which makes `GameViewController` the first real
  `MenuInputConsumer` and pauses world simulation through the existing
  `onModeChange` wiring. Cancel is Resume, vertical moves wrap, and the menu has
  no opening keystroke because `Esc` already releases mouse capture in gameplay.
  Settings surfaces the located data root read-only (resolved once and cached)
  and a master volume that writes through the same `AudioControlProviding` seam
  as `World > Audio`; M9 binds the per-category volumes behind it.
  The vanilla `startmenu.swf` presentation layer returns here after its 8.3.3
  rejection, and two of the three blockers are gone: the 35 `callDepthExceeded`
  faults were retired by issue #136, and `_root.CodeObj` turned out not to be a
  host object at all — the movie's own `StartMenu` constructor creates it, and
  all 16 names on it are Bethesda.net login calls. Measured against the install:
  bring-up 0 faults, 0 unimplemented opcodes, 152 draw calls, 4,285 changed
  pixels; after `SetPlatform`, `InitExtensions`, and `sendMenuProperties` the
  engine-pushed list reads back `$NEW`, `$LOAD`, `$CREDITS`, `$QUIT` with 0
  unhandled invokes of 36. Two gaps stay open and recorded: the populated `Main`
  state stages off the viewport (0 changed pixels), and arrow keys are consumed
  without effect because the focus chain starts at a holder clip with no
  `handleInput`. `Renderer.startSWFRuntime` gained a `prepare` hook because
  bring-up makes 24 `myLog` calls before the old post-start hook could answer
  them. Scope finding: `startmenu.swf` is the title screen and has no
  `$SETTINGS`; the in-game system menu is `quest_journal.swf`.
  See [system menu](/engine/system-menu.md), [menu mode](/engine/menu-mode.md),
  [AS2 runtime](/engine/as2-runtime.md), [screen-space UI](/rendering/ui.md),
  and [Main-app UI framework](/tools/app-ui.md). Refs #148.
* **Sound descriptor records (issue #154)**: `SNDR` now exposes ordered track names,
  category and output-model links, looping mode, signed frequency controls, priority,
  variance, and static attenuation. `SOUN SDSC` resolves through a typed record store to
  canonical `sound\...` VFS paths, discarding unsafe tracks and distinguishing missing
  marker from missing descriptor errors. Decoders skip malformed optional structures;
  synthetic fixtures cover all layouts and resolution failures. This change supplies
  records for later playback wiring; it does not add runtime source integration. See
  [sound records](/formats/sound.md).
* **HUD authored samples hidden by default**: the installed `hudmenu.swf`
  initializes with raw font markup under
  `/HUDMovieBaseInstance/RolloverInfoInstance` and
  `Dialogue Line 1Dialogue Line 2` under
  `/HUDMovieBaseInstance/SubtitleTextHolder`. HUD initialization now hides both
  engine-driven fields until real item or subtitle data exists.
  `World > HUD & Interaction > Elements > Authored placeholder text` preserves
  an explicit inspection toggle, defaults off, and participates in reset and
  override provenance. Synthetic bridge and panel tests cover both states; the
  environment-gated installed-movie acceptance test guards the clean default.
  See [screen-space UI](/rendering/ui.md) and
  [Main-app UI framework](/tools/app-ui.md). Refs #147.
* **HUD acceptance surface (M8.4.3)**: `World > HUD & Interaction` now exposes
  the live vanilla HUD as two standard inspector sections. **Elements** A/Bs the
  layer, crosshair, actor meters, compass, selected-target marker, activation
  prompt, and centered 50...200 percent presentation scale; its defaults
  participate in section, destination, and Reset-all override provenance.
  **Target** reports the exact walk-mode REFR/base, action/name, ray distance,
  placed/hit positions, prompt, camera heading, and marker headings, without a
  synthetic preview that could mask a targeting failure. Crosshair and compass
  use observed movie setters; meter visibility uses the observed installed
  `Health`, `Magica`, and `Stamina` clips. The environment-gated acceptance
  built farm cell `(7,-3)`, exact-raycast real door `0001633D` at 83.329315
  units, and sent its live `Open Door` prompt to the installed HUD: prompt
  off/on changed 4,069 pixels at 1280x720 with zero skipped items. Local A/B
  inspection confirmed prompt placement and stable compass/crosshair; frames
  remain gitignored. See [interaction targeting](/engine/interaction.md),
  [screen-space UI](/rendering/ui.md), and
  [Main-app UI framework](/tools/app-ui.md). Refs #147.
* **Vanilla gameplay HUD (M8.4.2)**: the app now loads and starts
  `Interface\hudmenu.swf` as the default SWF layer, validates its observed
  `/HUDMovieBaseInstance` entry points, and drives the vanilla crosshair, full
  static health/magicka/stamina meters, camera compass, selected-target marker,
  and interaction prompt through direct engine-to-movie calls. Target callbacks
  remain state-only; one frame-hook batch synchronizes the changed runtime.
  UI Lab movie selection temporarily overrides the HUD, and choosing `None`
  restores it. Synthetic AS2 tests cover the typed contract, while a Metal-gated
  acceptance test proves a path-targeted movie call changes pixels and then
  settles deterministically. A real-install 1280x720 offscreen probe changed
  1,783 pixels for a prompt plus marker with 208 draws, zero skipped items, and
  zero runtime faults; its statistics remain gitignored. See
  [AS2 runtime](/engine/as2-runtime.md),
  [interaction targeting](/engine/interaction.md), and
  [screen-space UI](/rendering/ui.md). Refs #146.
* **Indexed global SWF mouse handlers** (issue #133): `onMouseMove`,
  `onMouseDown`, and `onMouseUp` no longer trigger a full display-tree walk on
  every pointer event. Each runtime maintains a weak candidate index from
  direct and inherited AS2 property mutations plus mouse `CLIPACTIONS`,
  preserves the former highest-depth-first display order, and removes dead or
  detached clips during dispatch. See [AS2 runtime](/engine/as2-runtime.md).
* **Dev-shell override provenance and Reset all** (issue #143): every mutable
  `PanelSectionViewController` now reports `isOverridden` and implements
  `resetToDefaults()` against its live provider. A `Theme.gold` dot and Reset
  control stay in each overridden section header even while collapsed, and the
  existing 2 Hz `InspectionTicker` republishes their state without another
  timer. Sidebar dots aggregate the same provider-backed state for
  `World > World`, `World > Environment`, `World > Audio`, and
  `Developer > UI Lab`; `DestinationOverrideActions` live beside each registry
  descriptor so unopened panels remain lazy. `View > Reset all overrides`
  reaches every destination and resyncs cached panels, removing persisted
  shadow-quality, time-of-day, and LOD override keys while preserving section
  collapse state. UI Lab is now the normal three-section composition
  `UI foundation` / `SWF movie` / `SWF runtime`; its existing control ids stay
  stable. New chrome ids are `PanelSection-<id>-OverrideIndicator`,
  `PanelSection-<id>-ResetControl`, `Destination-<id>-OverrideIndicator`, and
  `ResetAllOverridesCommand`. See [Main-app UI framework](/tools/app-ui.md).
* **Walk-mode interaction targeting (M8.4.1)**: F now activates the exact object under a
  finite 192-unit camera ray instead of selecting a nearby door. Resident collision BVHs
  provide broadphase candidates; exact triangle, convex, box, sphere, and capsule tests
  select the first solid hit before interaction metadata lookup, so walls occlude targets.
  Streamed scenes retain localized FULL names, ACTI RNAM overrides, typed actions, and the
  record flags that suppress manual interaction. Target changes and use-key actions publish
  engine values for the HUD and later Papyrus bridge. Existing XTEL doors consume the same
  selected event path for interior/exterior transitions. See
  [interaction targeting](/engine/interaction.md). Refs #145.

## 2026-07-25

* **World audio playback engine + `World > Audio` (M9.1.3)**: an `AVAudioEngine`
  graph turns the framed + decoded `.xwm` work of 9.1.1/9.1.2 into audible,
  positioned sound. One `AVAudioEnvironmentNode` does the 3D mixing over mono
  player-node inputs (stereo sources are downmixed — the environment node passes
  stereo through unspatialized); provisional category submixes (music, effects,
  ambience — renamed once 9.2.1 decodes `SNDR`/`SDSC`) and the main mixer as
  master volume multiply as effective gain = master x category x source. The
  world-to-listener conversion is written down in `opensky/Audio/AudioSpace.swift`
  and the doc: Z-up native units -> Y-up meters via `(x, y, z) -> (x, z, -y)`
  times 0.0142875. Streaming: `AudioSourceStreamer` confines each non-Sendable
  `WMADecoder` to one serial decode queue, schedules 16-packet (~0.75 s) chunks
  at most 3 ahead, and runs no OpenSky code on the audio render thread. Budget:
  8 concurrent sources, FIFO eviction, finished-stream retirement and a
  3-ring cell purge on the renderer's `updateAudioFromWallClock()` tick (own
  `FrameSimClock`, gated on `worldSimPaused`). The decoder-side extradata policy
  the container parser declined now lives in `AudioCodecParameters(xwm:)`:
  empty `cbSize` extradata becomes ffmpeg's synthesized six-byte WMAv2 block
  (byte 4 = 31, per `libavformat/xwma.c`). With it, `openskycli audio sweep`
  now decodes the whole vanilla corpus streaming: 269/269 decoded, 869,476,352
  frames, 0 frame-count mismatches against `dpds`, 0 failures. New sidebar
  destination `World > Audio` (Output + Sources sections, ids
  `AudioEnabledControl`, `AudioMasterVolumeControl`,
  `Audio<Category>VolumeControl`, `AudioFileControl`,
  `AudioPlaySelectedControl`, `AudioStopAllControl`, `AudioStatsLabel`,
  `AudioSourcesStatsLabel`) triggers a positional source ~10 m ahead of the
  camera. Deterministic coverage renders the graph offline: channel balance for
  known poses, distance attenuation, the volume product, master-zero silence,
  cap eviction and cell purge, with no device and no audible playback. See
  [World audio playback](/engine/audio.md).
* **`.xwm` (xWMA) container framing added** (`opensky/Formats/XWM/`): Skyrim SE's music
  is Microsoft's xWMA — a RIFF form carrying a WMAv2 stream in `nBlockAlign`-sized
  packets. `XWMFile` frames and validates it and deliberately decodes nothing: it
  publishes the WAVEFORMATEX codec parameters, the `dpds` decoded-packet-cumulative-size
  table and the encoded payload (whole or per packet) so the WMA decoder from M9.1.1 can
  be dropped in behind it without the parser changing. Every byte offset is cited to
  MultimediaWiki's Microsoft xWMA page, FFmpeg's `libavformat/xwma.c` (read as
  documentation, never transcribed — copying it would import its license) and Microsoft's
  WAVEFORMATEX and RIFF documentation. Only `wFormatTag 0x0161` is accepted; WMA Pro and
  WMA Lossless are recognized and declined as `unsupported`. A missing `dpds` chunk and a
  `dpds`/packet-count mismatch are reported rather than rejected, because both are legal
  containers, while a misaligned or duplicated table is malformed. New `openskycli audio
  info` and `audio sweep` subcommands expose it; the sweep is gated in `tools/probe.sh`
  in the same shape as the `lod` and `swf` sweeps and streams file by file, holding only
  counts, since an unbounded audio sweep is the shape that has run this machine out of
  memory before. Vanilla evidence: 269 files, 269 framed, 0 unsupported, 0 failed, all
  stereo WMAv2, 0 packet-table mismatches, 347.0 declared minutes. The tally carries a
  `decoded` column that stays 0 until the decoder lands, so the probe's grep does not
  have to change then. See [xWMA container](/formats/xwm.md).
* **ffmpeg vendored for audio decode (M9.1.1)**: OpenSky's first external native
  dependency. `tools/vendor-ffmpeg.sh` (run by `make bootstrap`, also `make ffmpeg`)
  builds ffmpeg 8.1.2 from source into the gitignored `.vendor/ffmpeg` prefix, configured
  `--disable-everything --disable-gpl --disable-nonfree --disable-autodetect
  --disable-avformat --enable-decoder=wmav2 --install-name-dir=@rpath`. That yields three
  dylibs totalling 1.2 MB with no third-party dependencies, and the script proves the
  claim rather than trusting the flags: it compiles a probe that asserts
  `avutil_license()` is `LGPL version 2.1 or later` and that the configuration string
  enables no GPL, nonfree or `--enable-lib*` component, then rejects any `otool -L` entry
  outside `@rpath`, `/usr/lib` and `/System`. This corrects the 2026-07-20 premise: the
  Homebrew ffmpeg installed here is `--enable-gpl --enable-version3` and linking it would
  have relicensed a redistributed OpenSky as GPLv3. Linkage is a system-library module map
  (`tools/ffmpeg/module.modulemap`, `import CFFmpeg`) with `SWIFT_INCLUDE_PATHS` on both
  project configurations and link flags on the app and `openskycli` targets; the three
  dylibs are embedded in `opensky.app/Contents/Frameworks` at build time, so the installed
  app is self-contained. A missing prefix fails the build with a message naming
  `make bootstrap` rather than a raw linker error. `opensky/Audio/WMADecoder.swift` is the
  whole C boundary: container-supplied `AudioCodecParameters` in, interleaved 32-bit float
  `DecodedAudio` out, `WMADecoderError` for every failure, and every ffmpeg allocation
  owned by one private holder whose deinit is the only place anything is freed. Probe
  evidence (never committed): a synthetic 440 Hz sine decoded to 1.9969 s against a 1.999 s
  container, and one real `.xwm` from the player's install to 105.55791383 s against
  105.557914 s, both 44,100 Hz stereo. Decision: [ffmpeg for audio
  decode](/decisions/ffmpeg-audio.md). Refs #151.
* **Merged PRs backfilled into the milestones that shipped them**: all 107 merged PRs
  were assigned to a milestone and added to the roadmap board, so M1-M7 stopped being
  empty number-holders and became a queryable record of how each finished milestone was
  actually built. Milestone boundaries came from the acceptance PRs themselves rather
  than from guesswork — PR numbers are chronological, and each milestone closes with its
  own gate PR (#8 for M1, #21 "complete milestone 2", #35, #45, #59, #78, #94), so the
  ranges between those gates are exact. That rule also assigns the cross-cutting tooling
  and docs PRs to the milestone they were done in service of, which is the honest answer
  to "what did M6 cost" — the toolchain work was part of the milestone, not free. The
  in-flight M8 got the same treatment (30 merged, 7 open), so the board now reads as
  shipped work behind the current milestone and planned work ahead of it. Counts per
  milestone: M1 8, M2 13, M3 14, M4 8, M5 8, M6 11, M7 15, M8 30. Fifteen open issues
  stay unmilestoned by choice — they are standing infrastructure items (#70-#73 and
  peers), not roadmap steps.
* **Roadmap migrated out of `docs/todo.md` into GitHub issues and milestones**: the
  roadmap had grown into a 460-line file that was simultaneously a task tracker, a
  handoff note, a machine-quirks list, and a milestone history, and every one of those
  jobs was done better somewhere else. Worse, it was a checklist a human had to hand-edit
  in the same commit as the work, which is exactly the kind of rule a machine should be
  enforcing — the `format-parser` skill even carried a "delete it there in the same
  commit" clause to compensate. Open work now lives in GitHub: eighteen milestones where
  milestone `#n` is OpenSky milestone `Mn` (`M18+` is `#18`), and 71 issues (#145-#215),
  one per numbered roadmap item, each carrying its own acceptance gate. M1-M7 are closed
  milestones that hold that numbering identity and, after the backfill described below,
  the merged PRs that built them. The milestone
  description now carries what the roadmap's prose preamble carried — goal, spec
  references, and the legal notes on SWF, Havok, and `.ess` — so the context travels with
  the work instead of sitting in a file nobody opens mid-task. Labels `roadmap`,
  `acceptance-gate`, `format-parser`, and `app-ui` make the cross-milestone slices
  queryable. The `OpenSky roadmap` project board holds all 88 open issues and groups on
  the built-in `Milestone` field, so it needed no custom fields; it is a view over the
  issues, never the source of truth. The non-issue-shaped content moved to AGENTS.md
  under "Roadmap and open work": how a fresh session picks up work from `gh` rather than
  a doc snapshot, and the machine quirks (case-insensitive APFS volume, Xcode 26 without the Metal Toolchain,
  CI suspended on Actions quota). `docs/` is now knowledge only, which is what OKF wanted
  it to be — `docs-wiki` and `format-parser` were updated to say so, and an item is
  closed by its PR (`Closes #NNN`) rather than by editing a checkbox. The ~40 historical
  `[todo](/todo.md)` links in this log now dangle, which is fine and deliberate:
  `tools/check-docs-links.sh` skips this file for exactly this reason, since append-only
  history may reference docs that existed when the entry was written, and rewriting those
  links would have rewritten the history they date-stamp. The four dangling `/todo.md`
  links outside this log were repointed at whatever actually owns the question — issue
  #72 for the string-decode and language-setting notes in
  [records](/formats/records.md) and [strings](/formats/strings.md), issue #73 for the
  plugins.txt note in [VFS](/formats/vfs.md), and the M3 milestone name in
  [distant LOD](/engine/distant-lod.md). `ci.yml` now cites issue #70 rather than the
  deleted file.
* **Always-on frame HUD and the View-menu commands that go with it**: the frame and
  scene numbers were readable only while the `World` inspector was the frontmost
  destination, so a stutter noticed while flying around under `Environment` or `UI Lab`
  could not be read without changing destination first. A small `FrameHUDView` overlay now
  sits in the top-trailing corner of the game slot in every destination that shows the
  game view — fps, frame milliseconds, GPU or `n/a`, draw calls, drawn and culled
  instances, resident cells and process footprint — reading the same
  `FrameStatsProviding` and `SceneStatsProviding` snapshots the `World` panel reads, so
  the two surfaces cannot quote different numbers, and refreshing on the shared 2 Hz
  `InspectionTicker`. It is an AppKit view rather than a render pass on purpose: it needs
  no shader work, and it must stay out of `Renderer.renderOffscreen`, which feeds
  `openskycli screenshot`, the bench loop and every offscreen evidence capture. Chrome
  encoded into the scene pass would burn itself into those images; an overlay view cannot,
  because the offscreen path never touches the view hierarchy. The HUD hides itself, and
  stops its ticker, whenever a full-content destination covers the game view, so a hidden
  HUD costs nothing. `View` gains `Show Frame HUD` (Option+Command+H, checkmarked, the
  choice persisted under the `frameHUD.visible` default) and `Hide Inspector`
  (Option+Command+I), which drives the `.viewport` content kind that the retired
  `Viewport` row used to be the only way to reach. Both validate on the shell:
  `Hide Inspector` greys out on a destination that has no inspector column, rather than
  silently doing nothing.
* **`Viewport` becomes the `World` destination**: the first sidebar row was not a
  destination at all — it rendered no content of its own, showed no numbers, and its only
  effect was to collapse the inspector column, so the app opened on a view that gave a
  first-time user no hint that any controls existed. It is now `World`
  (`Destination-world`, the launch default), a `worldInspector` panel composed of three
  sections over the provider seams landed earlier today: `Camera` (live position, yaw and
  pitch in degrees, exterior cell, a fly/walk selector that gives the `G` key a visible
  settable surface, and a "Copy pose" button that puts the shared
  `cameraPoseDescription` on the pasteboard so a bug report can carry an exact camera),
  `Frame` (fps, average and worst frame milliseconds, CPU encode, GPU or `n/a`), and
  `Scene` (draw calls, drawn and culled instances, resident cells, process footprint).
  The `Frame` readout distinguishes "measuring" — no 30-frame window has closed yet —
  from a genuine zero, which the raw `.empty` snapshot would otherwise render as 0 fps.
  The `.viewport` content kind stays as the mechanism for hiding the inspector column,
  now with no sidebar row using it; the View-menu command that drives it lands
  next. `Destination-viewport` is retired in favour of
  `Destination-world` in both the unit-pinned id contract and the UI tests.
* **Live frame, camera and scene stats seam**: the frame timing the engine already
  measures left `FrameStats` only as one os_log line per 120-frame window, which is the
  milestone 2.9 fps gate and therefore not something a UI readout may reset or re-window.
  `FrameStats` now runs a second 30-frame window in parallel and publishes it as
  `FrameStatsSnapshot` (fps, average and worst frame milliseconds, CPU encode, optional
  GPU milliseconds, sample count), with its own `sampleTimestamps` correlation pair so a
  reader never moves the log window's boundary. Only the published snapshot crosses
  threads, behind an `OSAllocatedUnfairLock`; the accumulators stay confined to the render
  callback, which is what makes a 2 Hz poll from the main thread safe while frames are
  recording. Three provider protocols join the existing `*ControlProviding` family:
  `CameraControlProviding` (pose, exterior cell, settable fly/walk mode — the `G` key
  becomes an accelerator rather than the only affordance — and a `cameraPoseDescription`
  formatted once in a protocol extension so two readouts of one camera cannot disagree),
  `FrameStatsProviding`, and `SceneStatsProviding` (draw calls, drawn and culled
  instances, resident cell count, process footprint). `GameViewController` conforms in the
  new `GameViewControllerWorldStats.swift`, degrading to documented empty snapshots when
  there is no renderer or streamer. This is the seam only; the World panel and the frame
  HUD that consume it land next.
* **Dev-shell framework: spacing scale, component vocabulary, lazy panels, id
  convention**: follow-up to the shell bug fixes, aimed at the destination count the
  roadmap implies (five more named in `todo.md`). Panel spacing was one 8pt constant
  applied between a checkbox and its own slider as much as between two subsystems, so
  the column read as loose floating blocks; `PanelMetrics` now carries `rowSpacing`
  (6, inside a group), `groupSpacing` (12, a section's own stack) and `sectionSpacing`
  (18, between sections), with `PanelComponents.group([...])` binding related controls
  at the narrow step. Structure comes from the step between sections rather than
  uniform air. Five sections each hand-rolled `NSButton(checkboxWithTitle:)` plus
  target/action/id — the reason id conventions drifted — so `configureCheckbox`,
  `configureButton`, `group` and `separator` joined `PanelComponents`, and the doc now
  carries a factory inventory table instead of a prose list. The hand-pinned
  `heightAnchor` constants in `WeatherSection`/`PrecipitationSection` are gone; they
  defeated intrinsic sizing and were part of what kept collapsed space alive.
  `ShellContentViewController` built every world inspector at launch and kept them
  hidden; panels are now built on first reveal and cached by destination id, matching
  the existing `fullContent` strategy (`inspectorPanelsAreBuiltOnFirstReveal`).
  Finally the drifted accessibility ids (`LOD*Field`, `LODApplyButton`,
  `LODResetButton`, `LODStatusLabel`, `TimeOfDayLabel`) were renamed to the documented
  `*Control` / `*StatsLabel` convention in one pass, before the id surface grows
  further; toolbar items stay `*Button` as documented window chrome.
* **Dev-shell UI fixes + framework invariants**: three defects in the app shell, each
  fixed at the framework level so future panels inherit the fix. (1) Collapsing a panel
  section left a blank block as tall as the section. `CollapsibleSectionView` pinned its
  content as an ordinary subview (`content.bottom == self.bottom`) and only set
  `isHidden`; Auto Layout reclaims a hidden view's space only for an `NSStackView`'s
  *arranged* subviews, so the section kept its expanded height and the column reserved it.
  The view is now a stack with header + content arranged. The real gap was the test:
  `collapsibleSectionTogglesContent()` asserted `isHidden` and nothing about geometry,
  which is why this shipped — `collapsedSectionOccupiesOnlyItsHeader()` now pins collapsed
  height == header height and a strictly shrinking scroll document, and was confirmed to
  fail against the old behavior. (2) The sidebar toggle moved when clicked:
  `.sidebarTrackingSeparator` pins items to the split divider, so the toggle lived inside
  the sidebar region and slid left as it collapsed. Dropped it; the toggle is now a custom
  item with id `SidebarToggleButton`, and a View menu supplies Hide Sidebar (Ctrl+Cmd+S),
  the app's first View menu. (3) Sun-shadow A/B was the `H` key, advertised only by a hint
  note in the shadow section. It is now a `SunShadowsEnabledControl` checkbox over a new
  `ShadowControlProviding.sunShadowsEnabled` seam; the whole key path (`KeyCode.keyH`,
  `CameraInputState.requestShadowToggle`/`consumeShadowToggle`, the `RendererMovement`
  consumption) is deleted. Not persisted, unlike the quality tier: a shadowless world
  restored on next launch reads as a rendering bug. The general rule — no dev behaviour
  reachable only by an unadvertised keystroke — is now in
  [app-ui](/tools/app-ui.md) and the `app-ui` skill, alongside the layout invariants.
* **AS2 `super` resolution** (issue #136): `super` was derived from the receiver's
  prototype, which never advances as a constructor chain is walked, so the base constructor
  of a three-level hierarchy called itself until the depth cap aborted it — the vanilla CLIK
  shape, since a component extends `gfx.core.UIComponent`, which extends `MovieClip`. A
  frame now carries `basePrototype`, the prototype of the class whose method it is running,
  and `super` walks from there: `new C()` supplies the constructor's own `prototype`,
  `obj.method()` supplies the prototype the method resolved on, and a call through a `super`
  binding supplies the superclass prototype the binding recorded (`AS2Object.superBase`).
  Only a class's own `__constructor__` names its superclass. The base is assigned before
  parameter binding, because `PreloadSuper` builds the `super` register at that moment and
  vanilla constructors call `super()` through the register, not by name. Call parameters
  moved into an `AS2CallSite` value to carry it. Re-measured over the user's own install,
  all 53 vanilla `Interface/*.swf` movies brought up and ticked once: **394 faults to 0**,
  every movie clean (was 26 of 53), `quest_journal.swf` 159 faults to 0. Missing-API hits
  rose 2,527 to 3,754 because constructors now run to their end — `dispatchEvent` (326) and
  `addEventListener` (317 to 109) left the head of the tally, replaced by
  `EventDispatcher`'s own mixin state (`_listeners` 585, `invalidationIntervalID` 521),
  which is phase-4 data. Regression cover is `AS2SuperChainTests`.
* **AS2 interpreter call stack** (issue #132): calling a bytecode function recursed on
  the Swift stack (`callBytecode` -> `run` -> `callOp` -> `call`), so `AS2Limits.callDepth`
  had to be a stack-safety number (64) rather than a policy one, and probes at 128 and 256
  both crashed the test host. Calls now run on the interpreter's own frame stack:
  `AS2Frame` carries its record range, instruction pointer, and an `AS2FrameCompletion`
  saying where its return value goes (the caller's operand stack, or the `new` rule for a
  constructor), and `AS2Interpreter.runFrames` pops and resumes frames in one loop.
  `callDepth` is now a policy limit at Flash's own default of 256. Swift recursion survives
  only where a value is needed synchronously inside a Swift call — a built-in such as
  `Function.prototype.apply`, or a property accessor — bounded by the new
  `AS2Limits.reentryDepth` (32) and its `reentryDepthExceeded` fault.
  Re-measured over the user's own install, all 53 vanilla `Interface/*.swf` movies brought
  up and ticked once, at three caps in one process: 64, 256, and 4,096 produce identical
  faults (394), identical per-movie distribution, and identical missing-API tallies (2,527
  hits, 245 names); only wall-clock changes, and 4,096 completes cleanly where the recursive
  interpreter died at 128. That cap-independence identified the real cause: `super()`
  resolves through the receiver's prototype, which never advances, so a three-level class
  hierarchy recurses forever — the vanilla CLIK shape, filed as issue #136. The frame stack
  did move the distribution on its own (`racesex_menu.swf` 180 faults to 57 at the same cap
  of 64). See [AS2 runtime](/engine/as2-runtime.md).

* **Glyph-atlas eviction** (issue #127): the shared `UIGlyphAtlas` is one fixed-size
  512x512 shelf pack, and nothing ever handed cells back. Rendering all 53 vanilla
  `Interface/*.swf` movies in one process therefore exhausted it after roughly a
  dozen text-bearing movies, and everything after that drew no text at all —
  `interface\quest_journal.swf` rendered 1,535 glyphs alone and 0 late in the sweep.
  Fix: every packed cell now retains the coverage bytes it was rasterized from, and
  `releaseSWFGlyphs(where:)` drops one released movie's glyphs and repacks the
  survivors from that retained coverage (tallest first, ties broken by a total order
  over the key, so the repacked image is deterministic). `Renderer.setSWFMovie` calls
  it for the outgoing package's generation; system-font glyphs are never released.
  Packing + eviction moved to `opensky/UI/UIGlyphAtlasPacking.swift`.
  `lastUIDrawStats` gained `atlasGlyphs`, `atlasOccupancy`, and `atlasPackFailures`,
  all three shown in `Developer > UI Lab`'s stats readout so a user can watch cells
  come back while swapping movies. Verified with `openskycli swf render-sweep` over
  the user's own install: 53 movies, 53 rendered, 0 failed, 13,842 glyphs total, and
  `quest_journal.swf` back to its standalone 1,535 glyphs inside the full sweep.
  See [screen-space UI layer](/rendering/ui.md).

* **AS2 runtime subset** (milestone 8.3, closing 8.3.1/8.3.2/8.3.3): vanilla menus
  now execute their own ActionScript, and one of them runs interactively. Seven
  commits.
  * *Reachability.* `SWFActionParser` frames `ACTIONRECORD`s (byte offsets kept so
    the interpreter can seek to a jump target), `SWFActionName` names 100 opcodes,
    and `SWFClipActions` decodes the `CLIPACTIONS` block that `PlaceObject2`/`3`
    previously flagged and skipped. A shared `SWFTimeline` model replaced the
    frame-1-only view, so sprites keep every frame and every action stream.
    `FrameLabel` (43) and `ExportAssets` (56) decode as well — the latter is the
    linkage-name table `Object.registerClass` needs, without which nothing can be
    instantiated. Observed deviation from the spec's wording: `ActionPush` type 6
    DOUBLE stores its high-order 32-bit word first; reading it as a plain
    little-endian `UI64` yields denormal garbage.
  * *Measurement.* `openskycli swf action-sweep` plus `SWFActionInventory` tally the
    install: 53 movies, 3,414 action blocks, **533,562 action records, 56 distinct
    opcodes, 0 unknown, 0 parse warnings**. `With`, `Try`/`Throw`, `SetTarget`,
    `GetURL` and `WaitForFrame` never appear — no scope chain, no exceptions, no
    external loading. That measurement is what answers the scrapped native-UI
    decision's "full second VM project" objection, and it is recorded in
    [AS2 runtime scope](/decisions/swf-as2-scope.md): the VM is closed and bounded,
    the 3,382-name host API is the open-ended part, and it is phased behind a
    logged no-op plus tally so a menu degrades instead of failing.
  * *Interpreter.* `opensky/Formats/SWF/AS2/` implements all 56 opcodes over an
    ECMA-262-3-style value model, prototype chain, and `DefineFunction2` registers,
    under an explicit step budget, call-depth cap and bounded trace log. Malformed
    bytecode degrades to a recorded diagnostic and aborts one invocation. An
    empty-stack read yields `undefined` rather than faulting: the vanilla compiler
    emits a join-point `ActionPop` reached with an empty stack in 666 of 1,180
    blocks, and Flash behaves the same way.
  * *Dynamic display list.* A mutable display tree (`SWFDisplayObject`,
    `SWFMovieRuntime`) drives `MovieClip`/`TextField`/`Stage`/`Selection`, the
    property surface, and timeline control by frame or label, with registered
    classes constructed on placement. The renderer gained a cheap per-frame update
    path that re-plans draws and text while retaining tessellation, textures and
    the glyph atlas, with headroomed buffers that grow rather than overrun. The
    layer stays driven by an explicit tick, never wall clock, so an unadvanced
    movie still renders byte-identically.
  * *Interaction.* Clip-event dispatch, `Key`/`Mouse` broadcasters, pointer and key
    injection, bounds-level hit testing, focus and `NavigationCode` routing, and the
    `gfx.io.GameDelegate` bridge in both directions with a bounded invoke log.
  * *Acceptance.* `tweenmenu.swf` opens, navigates and closes on the AS2 subset with
    0 faults and 0 unimplemented opcodes: `StartOpenMenuAnim` plus 20 ticks opens it
    (460 changed pixels, `OpenAnimFinished()` back to the engine), arrow keys and
    pointer hover move the selection (`HighlightMenu(n)`, 988-1,863 changed pixels),
    `StartCloseMenuAnim` closes it (24,691 changed pixels, `CloseMenu()`).
    `startmenu.swf` was the nominated target and was rejected on measurement — 35
    `callDepthExceeded` faults, an unreadable `_root.CodeObj` host contract, and
    save-list data that belongs to a later phase. Sidebar path:
    `Developer > UI Lab > SWF movie` to pick the movie, then
    `Developer > UI Lab > SWF runtime` (`PanelSection-swfRuntime`) to start, tick,
    send keys and pointer events, invoke a movie callback, and read movie state,
    invoke log and op tally.
  * *Known ceiling.* Bringing up all 53 movies now registers 305 classes but records
    394 `callDepthExceeded` faults, because the interpreter recurses on the Swift
    stack and the 64-frame cap exists for stack safety — probes at 128 and 256 both
    crashed the test host. The aborted CLIK constructors are why `dispatchEvent`,
    `addEventListener` and `textField` head the remaining missing-API tally. Fixing
    it needs an explicit heap frame stack (issue #132); the per-event global mouse
    tree walk is issue #133.
* **Docs accuracy pass** (issue #124): fixed the twelve inaccuracies a full
  audit of `docs/` found, plus one stale code comment. `index.md` now lists
  [cell streaming](/engine/cell-streaming.md), which had been missing from the
  Engine section. [esm](/formats/esm.md) no longer claims localized strings and
  per-record decoders are unimplemented (both landed in M1); the section now
  names the real container-layer gaps — no `plugins.txt` load order or
  cross-plugin override merge (issue #73), and no ESL 0xFE FormID space.
  [shadows](/rendering/shadows.md) drops the removed `WorldSidebarViewController`
  / `WorldDestination` / `WorldSidebar` names for `AppSidebarViewController`,
  `DestinationRegistry`, `AppSidebar`, and `Destination-<id>`; its ring-regrow
  pointer now names `Renderer.swift`'s scene-swap extension rather than
  `RendererRings.swift` (sizing only); and its argument-table totals are scoped
  to the slot the shadow pass itself claims, with the running totals left to
  [Metal 4 renderer](/rendering/metal4-renderer.md). Those totals are refreshed
  to today's 13 buffers / 13 textures / 4 samplers, and both it and
  [sky + water](/engine/sky-water.md) record the real pass order — grass between
  alpha-test and water, then particles, precipitation, the SWF layer, and the UI
  overlay last. [preview-gui](/tools/preview-gui.md) and the matching
  `DestinationRegistry` doc comment now say the covered game view is paused and
  hidden, not drawing at a low rate. [vfs](/formats/vfs.md) describes the ini
  archive lists as a per-key merge of `Skyrim_Default.ini` under `Skyrim.ini`
  rather than either/or. [distant LOD](/engine/distant-lod.md) names the real
  `Apply` button (`LODApplyButton`), and [UI overlay](/rendering/ui.md) spells
  the fragment output as premultiplied. Docs only — no behavior change.
* **SWF static-render acceptance** (milestone 8.2.5, closing M8.2): the app can
  now select and render a vanilla movie without a CLI command.
  `Developer > UI Lab` grew a hosted **SWF movie** section
  (`opensky/Shell/Sections/SWFMovieSection.swift`,
  `PanelSection-swfMovie`): a popup listing `None` plus every
  `Interface\*.swf` in the located install (`SWFMovieControl`), a layer toggle
  bound to `Renderer.swfEnabled` (`SWFLayerEnabledControl`), and a readout
  (`SWFMovieStatsLabel`) showing the decoded `SWFMovieTally` — place/move/
  remove counts, `ShowFrame`s, sprites, clip layers, filters, blend modes,
  `ClipActions`, dangling placements — beside the live `SWFDrawStats`,
  unresolved font names, and any load error. Selecting an entry runs the 8.2.4
  path unchanged (`SWFMovieLoader.load(path:)` -> `Renderer.setSWFMovie(_:)`);
  `None` clears with `setSWFMovie(nil)`. The seam is a new
  `SWFLabControlProviding` + `SWFLabControlSnapshot` (`SWFLabReadout` builds the
  text device-free), implemented in the new
  `opensky/GameViewControllerSWFLab.swift` satellite; the loader and movie list
  resolve once, lazily, because enumerating movies walks every archive index
  and the 2 Hz ticker must not repeat it. A missing install, an undecodable
  movie, and a failing GPU package build all land in the readout instead of
  throwing out of a control action. Framework additions:
  `PanelComponents.configurePopUp(...)` and the hosted-section pattern (a
  direct-content panel adopting a `PanelSectionViewController` under the
  standard collapsible header), both documented in
  [app-ui](/tools/app-ui.md). **Milestone acceptance sidebar path:**
  `Developer > UI Lab > SWF movie`, controls `SWFMovieControl` +
  `SWFLayerEnabledControl`, readout `SWFMovieStatsLabel`.
  Offscreen evidence (`RendererSWFStaticAcceptanceTests`, 480x320, synthetic
  menu-shaped movie): 6 draws / 18 triangles / 4 glyphs / 2 mask draws / 0
  skipped and 103,686 changed pixels over the movie-free baseline; the same
  movie under an alpha-zero CXFORM still encodes its draws and reproduces the
  baseline byte for byte, which is exactly why most vanilla menus are blank at
  frame 1. `swfEnabled = false`, a cleared movie, a re-assigned movie, and
  repeated frames all behave byte-exactly. Vanilla evidence (per-movie
  `swf render-sweep` at 960x600, reproduced through the app's own picker with
  identical numbers): `creationclubmenu.swf` 97 draws / 344,207 changed px,
  `console.swf` 4 / 239,216, `quest_journal.swf` 612 / 237,525,
  `bookmenu.swf` 9 / 57,600, `hudmenu.swf` 185 draws with 24 stencil mask
  draws / 7,637, while `book.swf` and `loadingmenu.swf` encode draws and change
  nothing. Whole-install sweep at 480x320: 53 of 53 rendered, 0 failed, 18
  unchanged frames, 2,296 draws, 697,388 triangles, 6,033 glyphs, 44 mask
  draws, 1 unresolved font name (`Times New Roman`, in `hudmenu.swf`).
  Details in [SWF container](/formats/swf.md) and
  [screen-space UI layer](/rendering/ui.md); frame captures stay under `logs/`
  because a rendered vanilla movie embeds game art.

## 2026-07-24

* **SWF display-list render** (milestone 8.2.4): the display-list control tags
  now decode (`opensky/Formats/SWF/SWFDisplayList.swift`) — PlaceObject (4),
  PlaceObject2 (26), PlaceObject3 (70) with MATRIX, CXFORM/CXFORMWITHALPHA,
  ratio, name, and clip depth; RemoveObject (5) / RemoveObject2 (28);
  ShowFrame (1); SetBackgroundColor (9) — and `SWFMovie` builds a character
  dictionary plus the frame-1 display list from them, freezing the timeline at
  the first `ShowFrame` and expanding DefineSprite (39) nested tag streams into
  their own frame-1 lists. `SWFScene` flattens that into an ordered draw-command
  stream with concatenated transforms and color transforms and begin/end mask
  commands for clip layers. `SWFTransform` / `SWFColorTransform` carry the
  spec's MATRIX and CXFORM algebra; `SWFTextLayout` lays out static-text records
  and edit-text initial content in twips. PlaceObject3 filters and blend modes
  are framed, counted, and not applied; `ClipActions` are recorded and skipped.
  ImportAssets (57) / ImportAssets2 (71) also decode
  (`SWFImportAssets.swift`) because vanilla movies import their fonts by name —
  without that, 523 of the 595 edit texts with content resolve no font at all.
  `SWFMovieLoader` turns a VFS path into a font-resolved `SWFMovieScene` for
  both the CLI and the app. Rendering (`Rendering/RendererSWFMovie.swift`,
  `RendererSWFResources.swift`, `RendererSWFPass.swift`, `swfVertex`/
  `swfFragment`/`swfMaskFragment` in `Shaders.metal`) draws that stream over the
  finished 3D frame inside the scene pass, before the dev UI overlay: one
  256-byte-aligned `SWFDrawUniforms` slot per draw carrying the concatenated
  place -> sprite -> movie -> viewport -> NDC transform, the fill mapping, and
  the CXFORM; shapes from the tessellated per-movie vertex buffer, bitmaps as
  `rgba8Unorm` textures, gradients from a baked ramp atlas, text through the
  shared UI glyph atlas. Clip layers use a counting stencil (increment/decrement
  mask draws, content tests `stencil == active clip count`), so the scene pass
  now uses `depth32Float_stencil8`. Renderer API: `setSWFMovie(_:)`,
  `swfScene`, `swfEnabled`, `lastSWFDrawStats`. The layer is deterministic —
  same movie and viewport give byte-identical frames. Gates: `swf sweep` gained
  display-list tallies and `swf render-sweep` renders every vanilla movie's
  frame 1 (53 of 53, 0 failed, 2,277 draws, 692,328 triangles); both wired into
  `tools/probe.sh`. Notable observation: 1,032 of the 1,902 vanilla frame-1
  draws resolve to alpha 0, because vanilla menus hide frame-1 content and
  reveal it from ActionScript, so a blank frame-1 render is often correct.
  Details: [SWF container](/formats/swf.md),
  [screen-space UI layer](/rendering/ui.md), [CLI dev tool](/tools/cli.md).
* **SWF fonts + static text** (milestone 8.2.3): DefineFont2 (48) / DefineFont3
  (75) now decode through `SWFFontParser.parse(tag:)`
  (`opensky/Formats/SWF/SWFFont.swift`, `SWFFontParser.swift`): flags, name,
  language code, the glyph OffsetTable + CodeTable (8/16-bit codes, 16/32-bit
  offsets), each glyph SHAPE via `SWFShapeDefinition.parseGlyphSegments(_:)`,
  and the optional layout block (ascent/descent/leading, per-glyph advance +
  bounds, kerning) under `FontFlagsHasLayout`. DefineFont3's 20x-resolution
  glyph coordinates are captured by `unitsPerEM` (1024 vs 20480), so a consumer
  scales any glyph by `emPixelSize / unitsPerEM` regardless of version. A
  0-glyph device-font placeholder (its OffsetTable omitted, seen in
  `hudmenu.swf`) returns an empty font rather than over-reading. Companion tags
  DefineFontAlignZones (73), CSMTextSettings (74), and DefineFontName (88) parse
  minimally (`SWFFontCompanionParser`) — retained, hinting parsed-and-ignored.
  DefineText (11) / DefineText2 (33) decode through `SWFTextDefinition.parse`
  (`SWFText.swift`): TEXTRECORD state changes (font/height, RGB vs RGBA color,
  x/y offset) and bit-packed GLYPHENTRY index+advance runs. DefineEditText (37)
  decodes through `SWFEditText.parse` (`SWFEditText.swift`): the 16-bit flag
  word, optional font/class/height, color, paragraph layout, variable name, and
  initial text; HTML fields keep the raw markup and expose a tag-stripped
  `plainText` (full HTML layout deferred to 8.3.x). Glyph shapes convert to a
  CoreGraphics `CGPath` (`SWFGlyphPath.makePath`, even-odd fill, y-flip to CG
  space) and rasterize into the M8.1.1 atlas via a new
  `UIGlyphAtlas.swfEntry(fontKey:glyphIndex:emPixelSize:makePath:)` on a `.swf`
  key namespace that cannot collide with system glyphs; system-font fallback is
  untouched. `Interface/fontconfig.txt` parses via `SWFFontConfig.parse`
  (observed `fontlib` / `map` grammar) and `SWFFontLibrary` resolves a logical
  alias -> fontlib movie -> decoded font. `openskycli swf sweep` gained font,
  text, and fontconfig tallies; vanilla gate: 97 fonts (96 with layout, 54,988
  glyphs, 17,336 kerning pairs, 0 failures), 665 DefineEditText (0 DefineText
  in vanilla), and 20/20 fontconfig aliases resolved against `fonts_en.swf` /
  `fonts_console.swf` / `fonts_cclub.swf`. Reference: Adobe SWF File Format
  Specification v19 chapter 10. Docs: [SWF container](/formats/swf.md),
  [Screen-space UI layer](/rendering/ui.md); tests: `SWFFontTests`,
  `SWFTextTests`, `SWFFontConfigTests`, `SWFGlyphPathTests` over synthetic
  fixtures (`SWFFontBodyBuilder`, `SWFTextBodyBuilder`, `SWFEditTextBodyBuilder`).
* **SWF shapes + bitmaps** (milestone 8.2.2): DefineShape (2) / DefineShape2
  (22) / DefineShape3 (32) / DefineShape4 (83) tag bodies now decode through
  `SWFShapeDefinition.parse(tag:)` (`opensky/Formats/SWF/SWFShape.swift`,
  `SWFShapeParser.swift`, `SWFShapeTypes.swift`): FILLSTYLEARRAY (solid,
  linear/radial/focal gradients, bitmap fills with MATRIX), LINESTYLEARRAY
  (LINESTYLE and DefineShape4's LINESTYLE2), style-change / straight-edge /
  curved-edge records with fill0/fill1 dual fills, extended 0xFF style
  counts, per-version RGB vs RGBA rules, and glyph SHAPE reuse for 8.2.3
  (`SWFShapeDefinition.parseGlyphSegments(_:)`).
  `SWFShapeTessellator.tessellate(_:)` flattens quadratic edges
  deterministically and triangulates per fill via an even-odd/winding
  trapezoid sweep into `SWFShapeMesh` (twip-space triangle list + per-fill
  runs), memoized per character id by `SWFShapeCache` for 8.2.4; stroke
  tessellation is decoded-but-deferred. Bitmap tags DefineBitsLossless (20) /
  DefineBitsLossless2 (36) (zlib; 8-bit colormapped, PIX15, PIX24, ARGB
  premultiplied) and the JPEG family DefineBits (6) + JPEGTables (8),
  DefineBitsJPEG2 (21), DefineBitsJPEG3 (35, zlib alpha plane),
  DefineBitsJPEG4 (90, deblock param) decode to a shared RGBA8 `SWFBitmap`
  via ImageIO/CoreGraphics, with PNG/GIF signature detection per SWF 8+.
  `openskycli swf sweep` now decodes and tallies all shape/bitmap tags;
  vanilla gate: 2,677 shapes (944/1,097/574/62 by version) -> 2,195,435
  triangles, 453 bitmaps (451 `lossless32`, 2 `jpeg`), 0 failures.
  Reference: Adobe SWF File Format Specification v19 chapters 1, 6, 7, 8.
  Doc: [SWF container](/formats/swf.md); tests: `SWFShapeTests`,
  `SWFShapeTessellatorTests`, `SWFBitmapTests` over synthetic fixtures
  (`SWFShapeBodyBuilder`, ImageIO-generated payloads).
* **SWF container parser** (milestone 8.2.1 stage 1): new `opensky/Formats/SWF/`
  decodes the Adobe SWF container that Skyrim's Scaleform UI is authored in.
  `SWFFile.init(data:)` parses the signature/compression (`FWS` raw, `CWS` zlib
  via the existing `Zlib.decompress`; `ZWS`/LZMA declined with
  `SWFError.unsupportedCompression`), the 8-byte header (version, FileLength),
  the bit-packed FrameSize RECT, the 8.8 fixed-point FrameRate, FrameCount, and
  the flat tag stream (RECORDHEADER code/length, long-form `0x3F` escape,
  terminating End tag, trailing bytes ignored). `SWFBitReader`
  (`opensky/Formats/SWF/SWFBitReader.swift`) is a new MSB-first `readUB`/`readSB`
  bit reader — the repo had none. `SWFTagName.name(forCode:)`
  (`opensky/Formats/SWF/SWFTagName.swift`) maps the standard Adobe tag codes for
  a known/unknown tally; Scaleform GFx extension tags (~1000+) are unknown by
  design. Tag bodies stay undecoded — shapes/fonts/text/display list land in
  8.2.2-8.2.4. Reference: Adobe SWF File Format Specification, version 19. Doc:
  [SWF container](/formats/swf.md). Tests: `SWFFileTests`, `SWFBitReaderTests`
  over synthetic fixtures in `openskyTests/SWFFixture.swift`.
* **SWF sweep command** (milestone 8.2.1 stage 2, completes 8.2.1): new
  `openskycli swf sweep`/`swf info` (`openskycli/SWFCommand.swift`) parses
  every archive/loose `interface\*.swf` movie through the production `SWFFile`
  decoder and tallies known vs. unknown tag codes via `SWFTagName.isKnown`.
  `ZWS` (LZMA) movies are counted as accounted-but-unsupported
  (`SWFError.unsupportedCompression`), not a failure; any other thrown error
  is unexpected and exits 1. Gate evidence against the vanilla install: 53
  `.swf` files, 53 parsed, 0 unsupported, 0 failed; 14,477 tags total, 14,477
  known, 0 unknown. Milestone 8.2.1 accepted. `tools/probe.sh` gained a `swf
  sweep` smoke check; doc: [SWF container](/formats/swf.md) "Vanilla sweep
  results", [CLI dev tool](/tools/cli.md).

## 2026-07-23

* App shell restyled with a Skyrim-inspired dark theme (owner request): new
  `opensky/Shell/Theme.swift` (charcoal surfaces, parchment ink, muted gold
  accent + asset-catalog `AccentColor`, uppercase tracked headings in the
  macOS-bundled Futura Condensed Medium with system fallback — no Bethesda
  assets). Dark appearance forced at launch; sidebar group headers and
  destination rows, panel headings/captions/readouts, collapsible-section
  titles, Asset Browser wells, and the in-window startup message all take the
  treatment; inspector-panel slot gets a themed background + gold hairline
  edge. Covered-game behavior reversed (owner decision, was issue #98
  low-rate): a full-content destination (Asset Browser) now hides and pauses
  the MTKView behind an opaque backdrop — the world no longer renders behind
  it; uncovering resumes the loop. Tests: `ThemeTests` (font fallback, heading
  treatment, hairline) + `ShellContentCoverTests` (hidden + paused while
  covered, restored after). Doc: [app-ui](/tools/app-ui.md) theme section +
  updated shell anatomy.
* M8.1 UI shell foundation accepted (item 8.1.4): `Developer > UI Lab` is the
  durable verification surface for the whole foundation. Menu-mode preview
  (Push menu / Pop / Clear buttons, ids `UIMenuPushControl` / `UIMenuPopControl`
  / `UIMenuClearControl`) drives the real `MenuModeController` on
  `GameViewController` with depth-derived names (`UILabMenu1`, `UILabMenu2`, ...)
  and mirrors `isMenuMode` / top menu / stack depth / `isWorldSimPaused` in the
  `UIMenuStatsLabel` readout. Localized-strings preview
  (`UIStringsSampleControl`) renders `UIScene.localizedSample` — invented
  fixture strings through the real `TranslationFile` -> `LocalizedLabels` path —
  covering a wrapped long string, an unwrapped line that clips at the frame
  edge, and the unknown-key token `$OPENSKY_UILAB_MISSING` shown verbatim, at
  the existing 50-200% scale presets; `UIStringsStatsLabel` reports sample key
  count plus merged file/key counts over the located install (vanilla: 0 files,
  per the 8.1.3 probe). Renderer bridge split to
  `opensky/GameViewControllerUILab.swift` (file-size limit). Evidence at
  480x320: localized sample vs empty baseline 88 534 changed pixels, scale 1.0
  vs 2.0 82 710 changed pixels, paused repeat renders byte-identical with
  `animationTime` held at 0 (`RendererUIFoundationAcceptanceTests`).
  Deterministic state/layout tests: `UILocalizedSampleTests`,
  `GameViewControllerUILabTests`, extended `UILabPanelTests` (880 unit tests
  green). Docs: [screen-space UI](/rendering/ui.md),
  [menu mode](/engine/menu-mode.md),
  [UI translation strings](/formats/translation-strings.md).
* Creature `NiSkinPartition` global/local index-space decode (issue #64): SSE
  skin has two influence-index spaces — the top-level `BSVertexDataSSE` stream
  stores skin-instance-global bone ids, the per-partition `Bone Indices` array
  stores palette-local ids. Flattener wrongly remapped the global stream through
  the partition palette, throwing `vertex bone palette index out of range` on
  `SabreCat.nif` (non-identity palette); vanilla bodies survived via identity
  palettes. Now global-stream indices bounds-check against bone count directly;
  local indices still remap through the palette. Retained the global-VB byte
  (`usesGlobalVertexBuffer`); read-only SabreCat probe showed it 0 despite a
  global stream, so stream presence gates the space, not the flag. Split skin
  decode into `NIFModelSkinning.swift` (`InfluenceAccumulator`). Fixtures for
  both spaces + invalid cases. M5.6 fly bench: ACHR `000DC8DE` now renders.
  [nif](/formats/nif.md), [actors](/formats/actors.md).
* Unified sidebar shell (issue #98 PR 2 / #113): one `NSSplitViewController` shell
  (`AppShellViewController` + `AppSidebarViewController` + `ShellContentViewController`
  under `opensky/Shell/`) replaces the segmented World/Asset Browser mode switch
  (`MainViewController` + `WorldSidebarViewController` deleted). Sidebar map — World:
  Viewport, Environment · Developer: UI Lab · Library: Asset Browser; launch selects
  Viewport. `DestinationContent` gains `viewport`; `fullContent` factories now take a
  `FullContentContext` (data root + startup error) and the Asset Browser registers
  through the registry, lazily built + cached forever (`FullContentReloadable` lets a
  Settings reload reach it in place). Library destinations merely cover the always-live
  MTKView, which drops to 10 fps while covered (no hide, no pause) so streaming stays
  warm. `NSToolbar` (`unifiedCompact`): sidebar toggle + tracking separator +
  `Screenshot…` (`ScreenshotCoordinator`), enabled only on world destinations.
  Accessibility ids migrate: `AppSidebar` outline, `Destination-<id>` rows;
  `ModeSwitcher`/`WorldSidebar`/`WorldDestination-<id>` gone; panel/control ids +
  `ScreenshotButton` unchanged — pinned in `DestinationRegistryTests`, new
  `AppSidebarModelTests` covers grouping/order/default. Docs:
  [app-ui](/tools/app-ui.md) shell anatomy as-built,
  [preview-gui](/tools/preview-gui.md) rewritten for the sidebar path.
* UI translation strings (item 8.1.3): parser for
  `Interface/Translations/<name>_<language>.txt` (UTF-16LE + BOM, `$key<TAB>value`,
  CRLF) in `opensky/Formats/Strings/TranslationFile.swift`, and
  `LocalizedLabels` provider (`opensky/GameData/LocalizedLabels.swift`) that
  merges every discovered file and resolves a `$KEY` token, unknown key ->
  token verbatim (vanilla-observable fallback). Keys case-sensitive (Scaleform).
  Discovery added `VirtualFileSystem.fileNames(inDirectory:)` (loose + archive,
  one level). Backbone for HUD (M8.2) and vanilla SWF menus (issue #99); UI Lab
  long-strings preview (8.1.4) is the first visible consumer, so no sidebar
  surface this item. Format + decisions:
  [UI translation strings](/formats/translation-strings.md). Probe: 172 750
  archive entries, zero translation files in this vanilla install (expected).
* CLI target-boundary lint (issue #109): `make cli-boundary`
  (`tools/lint/cli-boundary.sh`) asserts every AppKit/Cocoa/SwiftUI-importing file under
  `opensky/` has a `membershipExceptions` entry for the openskycli target — synced groups
  otherwise pull app-only files into the CLI build (broke `make cli` twice). Wired into
  `make lint` (so `make check` + CI cover it) and pre-commit
  (`.githooks/pre-commit/45-cli-boundary.sh`); pre-push `make cli` stays as backstop.
* `docs/log.md` merge conflicts eliminated (issue #108): root `.gitattributes`
  gives it the built-in `merge=union` driver — parallel PRs prepending entries
  now merge clean, keeping both sides (the resolution that was always done by
  hand). Validated in a scratch repo: two branches adding entries under the
  same new date heading merge without conflict or duplicated heading. Union is
  line-based -> log.md only; `todo.md`/`index.md` see deletions, union would
  resurrect them. After a union merge, scan the top section once — same-line
  edits can still duplicate lines (mechanical dedupe, MD024 catches dup
  headings on next lint).
* `delegate` sub-agent orchestration skill (issue #107): new `.AGENTS/skills/delegate/`
  plus an AGENTS.md Skills bullet. Codifies the fix for sub-agents re-deriving the repo
  context every milestone — map once via one Explore/Plan pass and paste the brief
  (paths + type signatures) into each implementer prompt, sub-agents trust
  `docs/index.md`'s path table over globbing, verify a worktree agent's base is the
  feature branch (not stale `main`) at handoff, restate AGENTS.md criticals per prompt.
  Process-only; no engine change.
* Menu mode (todo 8.1.2): engine-owned menu-mode infrastructure. New
  `opensky/UI/MenuStack.swift` (pure duplicate-free push/pop stack of opaque
  `MenuIdentifier`s; empty = gameplay, non-empty = menu mode; pop-on-empty and
  duplicate-push edge cases decided) and `opensky/UI/MenuMode.swift`
  (`MenuModeController` source of truth, `MenuInputConsumer` protocol,
  `MenuInputEvent`, `InputRoute`). Input-capture switch in
  `opensky/GameMetalView.swift`: menu mode stops feeding `CameraInputState` and
  maps NSEvents to menu events. World-sim pause via new
  `opensky/Rendering/FrameSimClock.swift` (pausable wall-clock delta that keeps
  its mark fresh while paused -> no time jump on resume); `Renderer.worldSimPaused`
  gates the camera/weather/animation/particle/precipitation advance while the
  frame still renders. UI-toolkit-agnostic for the coming SWF menu layer;
  `GameViewController` wires it (no menu opens it yet -- 8.1.4 adds the UI Lab
  trigger). Tests: `MenuStackTests`, `MenuModeControllerTests`,
  `FrameSimClockTests`, Metal-gated `RendererMenuModeTests`. Design:
  [menu mode](/engine/menu-mode.md).
* Main-app UI framework (issue #98, PR 1): shared inspector-panel framework under
  `opensky/Shell/` — `DestinationRegistry` (single registration point, replaces the
  former four per-destination touch-points), `InspectorPanelViewController` /
  `PanelSectionViewController` base classes, `PanelComponents` + `PanelMetrics` control
  vocabulary, `InspectionTicker` readout lifecycle, `CollapsibleSectionView` (persisted
  expand state). The Environment panel (`EnvironmentPanelViewController` + its five control
  extensions) is decomposed into seven standalone sections (shadows, animation, weather,
  particles, precipitation, grass, distant LOD); the old aggregate readout splits per
  section. UI Lab rebased onto the framework. `WorldDestination` enum removed (registry ids
  replace it). New tests: `PanelFrameworkTests`, `DestinationRegistryTests` (pins the
  accessibility-id contract as literals while `make test-ui` is blocked). Guidance +
  placement rules: [app-ui](/tools/app-ui.md) + the `app-ui` skill, referenced from
  AGENTS.md. Provider-protocol + 2 Hz-poll renderer bridge unchanged. The unified-sidebar
  shell redesign follows in PR 2.
* Dev-loop friction fixes from mining past agent transcripts (issue #100).
  Testing: `make test`/`test-one` write fixed result bundles under
  `build/test-results/`; `make test-report` (`tools/test-report.sh`) now names
  failing tests + messages and waits for bundle finalization instead of
  misreporting a half-written `.xcresult`; new `make realtest T='Class/method()'`
  wraps `tools/realtest.sh` (data-root injection + RSS watchdog); `make test-ui`
  (`tools/test-ui.sh`) turns the "enabling automation mode" TCC hang into an
  actionable message; new `make test-perms` (`tools/test-perms.sh`) guides the
  one-time Full Disk Access / Automation grants; pre-push hook now also runs
  `make cli` to catch app/CLI target-membership regressions. Lint: `opening_brace`
  set to ignore multi-line conditions/signatures/headers so SwiftFormat and
  SwiftLint stop fighting; markdownlint MD060 relaxed to `style: consistent`
  (no forced pipe alignment); AGENTS.md gains a strict-lint threshold cheat-sheet.
  Skills: `format-parser` records the UESP-403 curl recipe + xEdit `dev-4.1.6`
  branch; `probe` corrects the `print()`-capture claim and points at
  `make realtest`/CLI-first; `commit` drops the stale `make preview` and adds the
  worktree-holds-main + CI-wait gotchas; `docs-wiki` notes the table/emphasis
  markdown traps. AGENTS.md: explicit rule that rendered game-asset screenshots
  go to `logs/`, never a tracked path. `docs/testing.md` rewritten to match the
  current suite. Report: no committed report — findings live in the PR + filed
  follow-up issues.
* App logo added: original "North Peak" mark (twin peaks + frost north star,
  white on black) as `opensky/Branding/opensky-logo.svg`; `make icon`
  (`tools/gen-appicon.sh`, librsvg) renders the macOS AppIcon set;
  `Contents.json` moved from iOS-universal template to `mac` idiom.
  Rationale + legal: [app logo](/decisions/app-logo.md).
* Docs link check automated (issue #102): `tools/check-docs-links.sh` resolves
  bundle-absolute `[x](/path.md)` links against `docs/`, reports file:line per
  miss, logs to `logs/docs-links.log`. Wired into pre-commit
  (`.githooks/pre-commit/55-docs-links.sh`, runs on any staged docs/ path),
  `make check` (`docs-links` target), and `ci.yml`. Policy: `log.md` skipped —
  append-only history may reference removed docs.
* Roadmap rescoped for the SWF port (issue #99): M8 now phases vanilla SWF UI —
  M8.1 shell foundation (menu mode, strings), M8.2 SWF parse + static render
  (container, shapes/bitmaps, fonts/text, display list), M8.3 AS2 feasibility +
  minimal runtime subset, M8.4 HUD via `hudmenu.swf`, M8.5 system menu +
  acceptance (gate now 8.5.3). M18.F vanilla fonts folded into 8.2.3; downstream
  menu items (M12.5 inventory) retarget vanilla SWF menus. [todo](/todo.md).
* Game-UI direction reversed (owner decision): port vanilla `Interface/*.swf`
  Scaleform UI, rendered via Metal — issue #99. `decisions/ui-approach.md`
  (native Metal/AppKit, no Scaleform) removed; older log/todo links to it are
  historical. M8.1.1 screen-space layer stays as SWF compositing foundation;
  M8.1.x roadmap items rescope under #99.

## 2026-07-22

* M8.1.1 screen-space UI layer -- new `opensky/UI/` subsystem (anchored value-type scene,
  9-point anchors + stack layout, points -> pixels `UIScale` with per-edge snapping,
  CoreText system-font shaping/wrap + shelf-packed r8 glyph atlas with white texel) renders
  as the final draws of the scene encoder: one premultiplied pipeline, triple-buffered
  vertex ring, 4,096-quad hard budget with exact drop count, `lastUIDrawStats`. Drawable +
  offscreen paths share the encode. Renderer API: `uiEnabled`/`uiScene`/`uiScale`.
  `World > UI Lab` sidebar destination adds overlay enable, sample toggle, 50-200% scale
  presets + 2 Hz stats readout (content view now swaps panels per destination).
  `screenshot --ui-sample` CLI flag + probe gate print quad/glyph/dropped/atlas evidence.
  Synthetic gates: 40 layout/text/budget cases; offscreen 480x320 labSample vs empty
  64,567 changed px, scale 1x vs 2x 93,036, disabled + repeat renders byte-identical.
  Real FirstRenderCell 1280x720 A/B: 64,576 changed px at 138 quads / 129 glyphs /
  0 dropped, atlas 512x512; capture visually checked. Full unit suite 0 failed; probe UI
  gate green (walk-bench budget overshoot pre-exists on main, measured UI-independent,
  filed #95). Docs:
  [UI approach decision](/decisions/ui-approach.md), [screen-space UI](/rendering/ui.md),
  [CLI](/tools/cli.md). Next: 8.1.2 menu mode.
* M7.6 living environment accepted -- production exterior runs actor animation, cascaded
  shadows, selected rain, world particles, precipitation + grass together; Chillfurrow Farm
  interior runs 1 animated actor + 1 particle system without precipitation/crash. `World >
  Environment` now gives every M7 system an independent master A/B plus live numeric readout.
  Real exterior A/B: 230,400 all-on/all-off changed px; 408 animation bones, 292 rain,
  350 shadow casters, 450 drawn grass; interior exact-time animation changed 5 px with 12
  particles live. Local captures visually confirmed rainy/overcast vs clear exterior + actor
  pose change. Combined 640x360 fly: 5,530 frames at 13.62 ms avg / 23.64 ms p95 vs 33.33;
  collision 551.25 ms p95 vs 750 (warm repeat 723.09), actors 3,014.79 vs 4,500,
  animation 3.20 vs 4, shadows 7.53 vs 14; full-probe repeats reached
  12.13/12.19/13.20. Peak 879 MiB vs 1,024. Peaks:
  445 animated bones, 1,305 particles/58
  systems, 306 rain, 847 shadow draws, 637 grass/0 drops. M7 leaves [todo](/todo.md); M8
  control convention now separates enable/force/freeze/inspect/reset + requires live state,
  accessibility IDs, layout tests + deterministic A/B evidence. Docs:
  [living environment](/engine/living-environment.md), [CLI](/tools/cli.md).
* M7.5.2 instanced grass + acceptance -- cell builder loads one shared NIF per GRAS type;
  `RenderScene` batches mesh/material instances across resident cells and drops them on cell
  eviction. Dedicated alpha-test pipeline applies fit-to-slope transforms, LAND tint,
  weather-vector wind bend, 70%-range distance fade, stable density thinning, frustum
  culling, and hard 16,384 mesh-instance/frame cap. `World > Environment > Grass` exposes
  enable/density/distance/wind + exact counters. Whiterun 640x360 gate: 126 placements ->
  126 instances in 2 calls/0 drops; on/off 1,015 changed px, windy exact-time pair 44 px
  (wind 0.698); half density drew 67/culled 59, minimum range culled 126. Cross-cell fly:
  peak 11,452 scene instances, 637 visible in 3 calls, 0 drops; 5,420 frames averaged 15.90
  ms / p95 31.50 ms vs 33.33 ms; final/peak footprint 738/889 MB vs 1,024 MB. Synthetic
  suites cover slope fit, cross-cell batch lifetime, hard-budget enforcement + panel layout;
  UI suite pins discoverability identifiers. Evidence stays gitignored. Docs:
  [grass](/engine/grass.md),
  [renderer](/rendering/metal4-renderer.md), [CLI probe](/tools/cli.md). M7.5 leaves
  [todo](/todo.md); integrated M7.6 gate next. `make test-ui` compiled; runner hit this
  machine's known environment TCC accessibility stall before first assertion.
* M7.5.1 GRAS + deterministic placement -- xEdit-cited GRAS decoder reads MODL + fixed
  32-byte DATA (density, slopes, water rule/distance, position/height/color variance, wave,
  flags); LTEX retains repeated GNAM links. Cell-owned CPU placement reconstructs ordered
  LAND BTXT/ATXT coverage, samples renderer-identical terrain triangles/VCLR, filters density,
  slope, water, hidden quadrants, and seeds each candidate from cell/LAND/GRAS/grid through
  SplitMix64. WRLD No Grass suppresses generation; summaries count placements + usable/
  skipped types. Vanilla probe: 27 GRAS, 68 LTEX, 39 GNAM links/0 unresolved; Tamriel (6,-2)
  generated 126 placements across 2 types (56 + 70), zero skipped, identical rebuild. Exact
  Bethesda lattice/PRNG remains undocumented; deviations recorded. Rendering + app controls
  defer to first visible consumer, M7.5.2. Docs: [grass records](/formats/grass.md),
  [placement](/engine/grass.md).
* M7.4.2 precipitation acceptance complete -- `World > Environment > Weather` adds stable
  data-driven Clear/Rain/Snow shortcuts + transition-only pause; Environment panel scrolls so
  all M7 controls remain reachable. Synthetic preset/pause + panel-geometry tests cover state
  and layout. Durable real-data FirstRenderCell gate (640x360): clear/rain 229,507 changed px,
  clear/snow 230,266, rain/snow 132,802, rain/returned-clear 229,507 (each >250); partial rain
  stayed frozen while renderer/particles advanced, clear return drained both precip volumes.
  Local app check: rain visible; snow target stayed blend 0% while paused, resumed to snow
  100% with 768 live particles, then SkyrimClear 100% with rain/snow 0. Evidence stays
  gitignored under `logs/`. Docs: [weather runtime](/engine/weather.md),
  [precipitation volumes](/rendering/precipitation.md). `make test-ui` compiled; runner again
  stopped at environment TCC accessibility loading before first assertion. M7.4 leaves
  [todo](/todo.md); grass next.
* M7.4.1 rain + snow volumes -- renderer-owned camera-following emitters reuse shared M7.3
  deterministic simulator, triple-buffered instances, alpha billboard pass, and generated
  streak/flake masks (no game asset). WTHR Rainy/Snow classification becomes transition-
  blended rain/snow intensity; live weather wind drives drift; full storms darken sky/sun/
  glare up to 35%. One upward camera ray through resident collision BVHs suppresses + clears
  precipitation under triangle/convex/box roofs (curved fallback = AABB). `World >
  Environment > Precipitation` adds enable A/B + type/intensity/live/roof readout; Weather
  popup forces decoded rain/snow. Synthetic math/ray/lifecycle/Metal tests pass. Real
  FirstRenderCell 640x360 scratch probe: `SkyrimOvercastRainFF` 3,452 changed px,
  `SkyrimStormSnow` 681; both captures visually checked, evidence gitignored in `logs/`.
  Docs: [precipitation volumes](/rendering/precipitation.md). Next: 7.4.2 transition/clear
  acceptance.
* M7.3.2 particle playback complete -- cell-owned deterministic CPU simulation for NIF
  box/cylinder/sphere/mesh-origin emitters; capacity/lifetime/variation + ordered
  gravity/wind/scale modifiers; weather vector input; stable exact-time seek. Metal path
  uploads triple-buffered instances, expands camera-facing six-vertex quads, samples effect
  DDS + fog, depth-tests read-only, selects exact alpha/additive-one/additive/multiply
  pipelines from NIF AlphaFunction pairs. `World > Environment > Particles` adds
  enable/freeze/0-200% emit
  controls + live system/emitter/particle readout. Gates: synthetic sim/blend/Metal tests;
  env-gated WhiterunWorld `(4,-2)` `FlamesTall01` + `smoke10` exact-time 512x512 frame
  delta passed with 41,742 -> 78,014 lit pixels + 73,613 changed pixels, numeric/PNG
  evidence in gitignored `logs/`. Docs: [particle playback](/rendering/particles.md),
  [NIF particle systems](/formats/nif-particles.md). M7.3 leaves [todo](/todo.md); M7.4
  precipitation consumes shared playback next. `make test-ui` target compiled; runner
  initialization remains environment-blocked by TCC automation timeout before test start.

## 2026-07-21

* M7.3.1 NIF particle + effect blocks -- static decode of Skyrim particle
  systems into engine types. New parsers (`opensky/Formats/NIF/`):
  `NIFParticleSystem` (NiParticleSystem/BSStripParticleSystem, stream 83 + 100
  NiGeometry layouts), `NIFParticleData` (NiPSysData/BSStripPSysData capacity +
  presence flags + subtexture atlas), `NIFParticleModifiers` (box/cylinder/
  sphere/mesh emitters; age-death, spawn, gravity, rotation, position,
  bound-update, drag, simple-color, scale, wind, inherit-velocity, sub-tex, LOD
  modifiers; unknown types -> `.unsupported`, never throw),
  `NIFEffectShaderProperty` (BSEffectShaderProperty: flags + accessors verified
  bit-by-bit vs nif.xml, source/greyscale textures, falloff, base color, soft
  depth; stream 83/100 byte-identical). `NIFFile.particleSystems()` walks the
  scene graph (NIFModel discipline: depth cap, cycle stack, ref range checks)
  into `ParticleSystemDefinition` with resolved `effectShader` +
  `alphaProperty`. Spec: NifTools nif.xml, cited per file. Docs:
  [/formats/nif-particles.md](/formats/nif-particles.md) + BSEffectShaderProperty
  section in [/formats/nif.md](/formats/nif.md). Tests: `NIFParticleTests` (12)
  plus `NIFEffectShaderTests` (8), synthetic fixtures. Gate passed
  (`ParticleRealDataTests`, env-gated): Whiterun sweep (WhiterunWorld grid +
  Tamriel home cell) = 283 referenced models, 11 particle-bearing, 23 systems,
  23 effect shaders + 23 alpha properties resolved, 0 decode failures
  (`logs/particle-sweep.log`); broader probe: 109 vanilla effect NIFs, 216
  systems, 2347 modifiers, 0 throws. UI deferred to M7.3.2 particles controls
  (first visible consumer).
* Issue #62 tree LOD + configured distances complete. Typed read-only INI layer merges
  Skyrim defaults/prefs/custom files with malformed-value fallback; four validated
  `[TerrainManager]` values drive contiguous L4/L8/L16/L32 selection + tree radius.
  `World > Environment > Distant LOD` exposes only those live settings, applies/rebuilds
  immediately, reports source, and resets to Skyrim INI. Defensive xEdit-cited LST/BTT
  parsers + generated crossed-plane atlas billboards join normal model/texture
  cache/residency/eviction; exact world-space tree radius rejects diagonal overdraw,
  optional malformed blocks degrade with accounting. Tree LOD stays inside resident cells
  until full `TREE` rendering exists -> no near-grid hole. Vanilla Tamriel sweep: 3,060 BTR,
  717 BTO, 34 tree types, 329 BTT/40,839 refs, 0 failed. Whiterun 5x5 offscreen: 121
  terrain/object blocks + 9 available tree blocks/2 radius-valid trees; focused cell: 131
  blocks + 9 tree blocks/35 trees. Both 100% non-background. Docs:
  [INI](/formats/ini.md), [LOD format](/formats/lod.md),
  [distant LOD](/engine/distant-lod.md), [CLI](/tools/cli.md).
* M7.2.3 weather-core acceptance -- M7.2 data-driven weather core complete. Live
  XCLR region feed: `CellScene.regions` carries the built cell's XCLR set,
  `CellStreamer.onCenterRegionsChanged` fires when the resident exterior center
  cell's region set changes, `GameViewController` forwards to
  `WeatherSystem.setRegions` -> region-weighted selection runs live (interior path
  leaves regions unchanged; weather is exterior-only). Sidebar surface finalized:
  `World > Environment > Weather` = weather popup (`WeatherControl`, Auto + 84
  editor-ID-sorted vanilla weathers) + new 0-24 h time-of-day slider
  (`TimeOfDayControl`/`TimeOfDayLabel`, drives `Renderer.timeOfDay` live,
  persisted via `TimeOfDaySettings` UserDefaults trio) + current weather/blend/wind
  readout. Gate passed (`WeatherAcceptanceRealDataTests`, real Skyrim.esm exterior,
  1280x720 = 921,600 px): pairwise forced-weather deltas SkyrimClear/SkyrimCloudy
  585,095 px, SkyrimClear/SkyrimFog 921,600, SkyrimCloudy/SkyrimFog 921,595;
  timed SkyrimClear->SkyrimCloudy transition stepped to 0.45 over 37 monotone
  samples, mid-frame differs from both endpoints (204,770 / 364,563 px);
  SkyrimClear 04:00 vs 13:00 differs 921,600 px. Streamer seam unit-tested
  (`CellStreamerRegionFeedTests`); full suite 741 green. `make test-ui` still
  env-blocked (TCC); accessibility ids recorded for its return. Precipitation
  waits for M7.3 particle playback. Docs: [weather runtime](/engine/weather.md).
  M7.2 leaves [todo](/todo.md); next 7.3.1 NIF particle blocks.
* M7.2.2 weather runtime -- data-driven exterior weather over WTHR/CLMT/REGN.
  Formats grow WTHR DALC (4x 32-byte sunrise/day/sunset/night ambient keyframes:
  six axis colors + specular + scale, xEdit `wbDefinitionsTES5` layout), WRLD CNAM
  climate ref, CELL XCLR region array. `WeatherStore` indexes records once (immutable
  value types, render-thread safe); `WeatherSelection` builds weighted pools per xEdit
  REGN semantics (XCLR region weather areas by priority, Override flag gates climate
  WLST append, fallback WRLD CNAM -> CLMT); deterministic SplitMix64 pick seeded by
  worldspace + reroll epoch. `WeatherSystem` cross-fades from/to weather
  (smoothstepped; Trans Delta read as inverse rate `1/clamp(delta,0.02,0.25)` s --
  unit undocumented in open specs, deviation flagged in doc), rerolls every 6
  game-hours of time-of-day movement (static clock -> static weather), exposes
  force API for UI/tests. `TimeOfDayWeights` blends each weather's four keyframes
  via CLMT TNAM sunrise/sunset windows (defaults 05-07/17-19). Renderer:
  `FrameUniforms.weatherSkyEnabled` + five-color weather sky palette, exterior-only
  application (interior CELL/LGTM lighting untouched), weather fog/ambient/sun tint
  override camera fallbacks, `skyFragment` keeps procedural branch bit-identical
  when inactive. Wind published as `Renderer.currentWind` (velocity-vector blend)
  for M7.3-7.5. Environment panel gains Weather popup (Auto + force) + live
  blend/wind readout; acceptance evidence + docs gate land in 7.2.3. Gates:
  `WeatherRuntimeTests` (20 synthetic), DALC/CNAM/XCLR fixture tests,
  `RendererWeatherTests` offscreen A/B (inactive == baseline bit-identical, forced
  weathers repaint + differ), full suite 739 green; realtest sweep 84 WTHR (83 with
  DALC), 6 CLMT, 317 REGN all resolve. Docs: [weather runtime](/engine/weather.md),
  [weather formats](/formats/weather.md), [sky](/engine/sky-water.md). Next: 7.2.3
  weather-core acceptance.
* M7.2.1 weather records -- WTHR/CLMT/REGN decoders (`Weather.swift`,
  `Climate.swift`, `Region.swift`). WTHR: NAM0 per-time-of-day color layers
  (count from size; 13/14/17-component variants), FNAM fog distances (32 + legacy
  16 byte), 19-byte DATA (wind speed/direction, trans delta, sun glare/damage,
  precipitation + thunder fades, classification flags -> `Precipitation` enum,
  lightning color). CLMT: WLST weather chances, TNAM timing + packed moons byte,
  sun/glare/night-sky paths. REGN: weather data areas only (RDAT type 3 + RDWT),
  worldspace, map color; RDWT bound to last-seen RDAT type. Unknown sizes -> nil/
  skip, never guess (UESP DATA ambiguity resolved via xEdit: two Visual Effect
  bytes at 15-16). CLI `record` + Asset Browser dump WTHR/CLMT/REGN summaries.
  Gates: synthetic-fixture suites green; vanilla sweep (`WeatherRealDataTests`
  via `tools/realtest.sh`) decodes 84 WTHR / 6 CLMT / 317 REGN no-throw, all
  CLMT + REGN weather refs resolve to WTHR. Sidebar UI defers to 7.2.3 weather
  controls (parser-only item). Docs: [weather](/formats/weather.md). Next: 7.2.2
  weather runtime.
* M7.1.2 shadow streaming/budget/quality -- M7.1 sun shadows complete. Per-cascade
  per-instance caster culling (survivor runs in a `cascadeCount x` instance ring, one
  instanced draw per group per cascade) + light-volume near-Z clamp to the resident-cell
  caster union (`ShadowCascadeMath.clampedShadowNearZ`; casterBackup never reaches past
  streamed geometry). `ShadowQuality` off/low/high: high = 3 cascades/12288/3x3 PCF,
  low = 2 cascades/8192/1-tap (`FrameUniforms.shadowSampleRadius` drives MSL taps; no
  map realloc), off skips the pass; `H` A/B toggle preserved independently. Fixed latent
  M7.1.1 MTL4 hazard: no cross-encoder barrier between shadow depth writes + scene-pass
  sampling flipped ~52% of pixels in ~half of runs -- final cascade encoder now issues a
  device-visibility fragment barrier; determinism test guards it. Fly bench gains explicit
  shadow budget: `lastShadowUpdateMS` -> `OffscreenBenchResult.shadowMS`,
  `shadowUpdateExceeded` gate, `bench --fly-path --shadow-budget-ms` (default 12 ms from
  measured Whiterun avg 3.26/p95 6.52 ms @ 640x360 Debug, ~1.8x headroom); probe asserts
  the new `shadow culling` accounting line (`lastShadowDrawStats`). First main-app sidebar
  surface: `World > Environment > Sun shadows` (Off/Low/High popup, live 2 Hz shadow
  stats, UserDefaults `ShadowQualitySetting`, `WorldDestination` enum = extension point
  for M7.2-7.5). Gates passed: quality deltas off/high 5,879 px, off/low 2,449 px,
  low/high 5,131 px, same-quality re-renders bit-identical; fly bench shadow avg
  3.28/p95 6.55 vs 12 ms, all prior gates green; full unit suite green. `make test-ui`
  blocked at harness init on this machine (TCC automation timeout, environment-level);
  sidebar UI test recorded for when it returns. Interior point-light shadows stay out of
  scope (later milestone). Docs: [shadows](/rendering/shadows.md),
  [renderer](/rendering/metal4-renderer.md), [CLI](/tools/cli.md). M7.1 leaves
  [todo](/todo.md); next M7.2 weather core.
* Roadmap dependency order rebuilt in [todo](/todo.md) without dropping planned work.
  M7 now orders shadows -> weather/wind -> shared particles -> precipitation -> grass;
  dynamic physics moved to M15 combat. Early M8 interaction/UI shell + M9 world audio
  create user-visible vertical slices. M10 runtime identity/change journal/native saves +
  CTDA/time/GLOB now precede mutable gameplay. Papyrus interaction = M11, inventory = M12,
  quests + journal = M13, behavior locomotion = M14, combat = M15, AI = M16, dialogue +
  voice/lips = M17. Vanilla SWF fonts + read-only `.ess` import no longer gate gameplay.
  Every milestone keeps a numbered acceptance gate + planned main-app sidebar path.
  AGENTS.md now requires each new subsystem/user-verifiable behavior to add or extend a
  durable sidebar verification surface; parser/math-only work may wait for its first
  visible consumer. App inspection supplements probes/tests/benchmarks, never replaces them.
  Rebased after M6 + M7.1.1 landed: completed items stay out of todo; evidence follows the
  local-capture + numeric-gate policy.
* M7.1.1 cascaded sun shadows -- depth-only pre-pass renders opaque/alpha/terrain +
  skinned casters into a 2048x2048x3 `depth32Float` array (one encoder per cascade,
  same reused MTL4CommandBuffer, before the scene pass); `staticMeshFragment` +
  `terrainFragment` sample it with 3x3 PCF (`depth2d_array.sample_compare`) and darken
  only the direct sun term. `ShadowCascadeMath` fits practical-split cascades (lambda
  0.7, distance 12288) with rotation-invariant bounding-sphere ortho extents +
  texel-snapped origins; `MatrixMath.orthographic` added; MSL cascade pick mirrors
  `cascadeIndex` verbatim. Dedicated shadow instance/draw rings avoid the scene pass's
  per-frame cursor reset; caster instances write once per frame, groups cull per
  cascade by merged bounds. Acne control: raster bias 2/slope 3, receiver bias 0.0015,
  cull back. Gate passed: `ShadowCascadeMathTests` (20 synthetic),
  `RendererShadowTests` A/B (receiver darkens, sky bit-identical, off == baseline);
  real probe WhiterunExterior06 5,194 px differ / 3,370 darker / 0 brighter /
  deterministic; 5x5 screenshot shows building shadows, no acne; single-cell bench avg
  1.73 ms. `H` toggles shadows in the game view (sidebar quality setting = 7.1.2).
  Docs: [shadows](/rendering/shadows.md), [renderer](/rendering/metal4-renderer.md).
  Item 7.1.1 leaves [todo](/todo.md); 7.1.2 owns streaming/budget/quality acceptance.

## 2026-07-20

* M6 actors animate complete -- renderer samples direct human `mt_idle.hkx` clips, composes
  `hkaSkeleton` local poses through parent hierarchy, name-maps world transforms onto NIF
  palettes, then writes `rootParentToSkin * animatedWorld * skinToBone` into a per-frame GPU
  palette slot. Unmatched bones retain bind pose. `RenderScene` owns playback objects with
  resident cells; builder caches immutable clips by skeleton + gender. Rendered actor
  accounting is exact (`animated + static fallback`) and every fallback reason-tagged.
  Deterministic offscreen tests prove animated times differ + static frames match; pose,
  palette, lifecycle metrics tested. Real probes: ChillfurrowFarmExterior 7 rendered = 4
  animated + 3 unsupported-creature fallbacks; ChillfurrowFarm interior 1 rendered = 1
  animated; door round trip passed. Animation update has an explicit 4 ms Debug avg/p95
  fly-bench gate. Per-frame work deduplicates shared clips + meshes: real 35-cell flight
  found 11 animated + 16 reason-tagged static actors; animation update avg 1.61 ms/p95
  2.99 ms, frame avg 5.36 ms/p95 9.51 ms. Cold actor-build p95 2883 ms; 4500 ms Debug
  budget includes first rig/clip decode. Docs: [actor idle animation](/engine/actor-animation.md),
  [CLI](/tools/cli.md). M6 leaves [todo](/todo.md); M7 plan otherwise unchanged.
* Render evidence policy changed: generated captures stay local/ignored; repository gates use
  numeric pixel deltas, accounting, timing, and probe logs. All tracked PNG files + embedded
  links removed; `.gitignore` rejects PNG case variants; roadmap/probe instructions no longer
  ask contributors to add image evidence.
* M6.3 idle clip decode complete -- `HKASplineCompressedAnimation` parses Havok 2010
  hkaAnimation/hkaSplineCompressedAnimation metadata + hkArray/fixup block tables;
  `HKASplineBlock` decodes transform masks, identity/static lanes, u16-quantized vector
  splines, 40-bit omitted-largest quaternions, degree-1/3 B-splines -> `HKABonePose` local
  transforms. `HKAAnimationBinding` resolves track order to bone indices; verified idle
  binding names `NPC Root [Root]`, uses empty-map identity for all 99 tracks, maps four
  float tracks to slots 4...7. Decoder is defensive/typed: metadata/table/block bounds,
  exact transform-region closure, supported quantization only, spline degree/knots/bounds,
  finite + 1e6-bounded outputs; sampled quaternions normalize. Layout from open parsers
  (exyorha/hkxparse MIT, ret2end/HKX2Library MIT, PredatorCZ/HavokLib GPLv3),
  probe-verified on male mt_idle.hkx: hkaSplineCompressedAnimation type 5, 275 frames /
  9.133333 s, 99 transform + 4 float tracks, two blocks whose decode cursors close at
  20,552 + 4,216 transform bytes. New `openskycli animation <hkx>` resolves binding, then
  samples all 275 x 99 bone-indexed transforms over full duration; real gate passed with
  max translation 121, max scale 1,
  quaternion norms 0.9999999...1.0000001, no NaN/inf/bound failure. Synthetic
  `HKASplineAnimationTests` cover linear/static/identity sampling + malformed axes. Docs:
  [hkaSplineCompressedAnimation](/formats/hka-animation.md), [CLI](/tools/cli.md). Item 6.3
  left [todo](/todo.md).
* World/render track promoted to Milestone 7 with full numbered plan in
  [todo](/todo.md) (user priority): M7.1 sun shadows (cascaded maps), M7.2
  data-driven weather (WTHR/CLMT/REGN), M7.3 grass (GRAS), M7.4 particles + effect
  shaders, M7.5 dynamic physics (rigid bodies, ragdoll, projectiles — combat
  consumes later). Downstream milestones renumbered: Papyrus M7 -> M8, audio
  M8 -> M9, UI M9 -> M10; direction section now M11+, re-scope at the M10 gate.
  M6 idle playback still finishes first; M7 starts at the 6.6 gate. Earlier log
  entries keep the pre-renumber milestone names.
* M10+ direction recorded in [todo](/todo.md) from playability gap analysis. Decisions:
  locomotion via Havok Behavior graph reimplementation (exact vanilla movement +
  anim-mod compat; accepted as major RE effort) over native state machine; saves =
  OpenSky-native versioned format + later read-only .ess import, never .ess write;
  milestone order gameplay-first (inventory -> locomotion -> combat -> shared runtime
  -> AI -> dialogue -> save/load), accepting persistence retrofit cost. Candidate
  milestone list incl. render track (shadows, weather, grass, particles, ragdolls)
  * meta (menus/chargen/map). Numbered re-scope deferred to the M9 gate.
* Metal shader tooling decided ([decision](/decisions/metal-tooling.md)): clang-format
  (via `xcrun`, config `tools/format/.clang-format`) formats `.metal` through
  `make format`/`format-check` + pre-commit hook `35-metal-format.sh`; linter =
  Metal compiler with `MTL_TREAT_WARNINGS_AS_ERRORS = YES` (both configs), enforced
  by build gates. `Shaders.metal` one-time reformat. Remaining tooling/meta + open
  questions moved from [todo](/todo.md) to GitHub issues #70-#73 (CI re-enable,
  commit-msg body enforcement, string decode strategy, plugins.txt load order);
  AGENTS.md CI note now points at #70.
* Roadmap re-scoped: M7-M9 planned in [todo](/todo.md). M7 Papyrus quest-capable
  (M7.1 VM core, M7.2 scripts in world, M7.3 quest engine). M8 audio incl. voice +
  lip sync (M8.1 decode/playback foundation, M8.2 game wiring, M8.3 voice + lips);
  xwm decode route decided: ffmpeg (LGPL) wrapped behind Swift interface, dynamic
  link. (Correction, 2026-07-25: "ffmpeg (LGPL)" was true of ffmpeg in general but
  not of any ffmpeg on this machine — the installed Homebrew build is configured
  `--enable-gpl --enable-version3`. The route stands only because OpenSky now builds
  its own decode-only LGPL library; see [ffmpeg for audio decode](/decisions/ffmpeg-audio.md).)
  M9 game UI native-first hybrid (M9.1 HUD, M9.2 menus, M9.3 vanilla fonts
  via SWF glyph extraction); full Scaleform playback ruled out. Each sub-milestone
  carries its own acceptance gate; decision docs (`decisions/ffmpeg-audio.md`,
  `decisions/ui-approach.md`) land with first impl items.
* M6.2 hkaSkeleton decode complete -- `HKASkeleton`
  (`opensky/Formats/HKX/HKASkeleton.swift`) reads each hkaSkeleton out of the
  packfile via the 6.1 virtual-fixup inventory: m_name, m_parentIndices
  (i16/bone, -1 root), m_bones (inline hkaBone stride 16: name + lockTranslation),
  m_referencePose (hkQsTransform stride 48: translation/quat/scale, w-lane junk
  ignored). hkArray located via the local fixup at the field pointer offset,
  size field over capacityAndFlags, size-0 arrays (null ptr, no fixup) decode
  empty. Defensive typed `HKASkeletonError`: bounds, count mismatch, parent
  range, missing bone-name fixup, non-finite pose. `SkeletonBoneMap` name-maps
  the rig onto NIF NiNode names (`NIFSkeleton.boneTransforms`) by exact match,
  reason-tagging mismatches both directions. Layout from open parsers
  (exyorha/hkxparse, ret2end/HKX2Library, ZeldaMods Havok wiki), probe-verified
  on real human + wolf skeleton.hkx (rig + ragdoll). Real human rig: 99 bones,
  2 roots; name-map 93 of 99 matched, 6 HKX-only helper/attach bones + 6
  NIF-only nodes (incl. a Shield/Weapon/Quiver case split). New
  `openskycli skeleton <hkx> [--nif <nif>]` dumps bones/parents/roots + map;
  probe gains the M6.2 99-bone/93-match/reason-tagged gate. Synthetic
  `HKASkeletonFixture` + `HKASkeletonTests`/`SkeletonBoneMapTests` cover happy
  path, empty/multi-root, and one-axis-each malformed input. Docs:
  [hkaSkeleton](/formats/hka-skeleton.md), [CLI](/tools/cli.md). Item 6.2 left
  [todo](/todo.md).
* Local app/test builds now use Apple Development signing -> stable designated
  requirement lets macOS retain removable-volume consent across rebuilds. App Info.plist
  gains `NSRemovableVolumesUsageDescription`; first access explains Skyrim data reads.
  `XCODEBUILD_FLAGS` gives certificate-free CI an explicit ad-hoc override. Xcode's UI
  test graph stays ad-hoc because development signing blocks its non-promptable
  Developer Tool request and mixed-signature graphs cannot pair. UI fixtures use only
  synthetic internal-disk data; app/unit/real-data paths remain stable-signed.
* M6.1 HKX container parse complete -- `HKXFile`/`HKXHeader`/`HKXSection`
  (`opensky/Formats/HKX/`) decode the SSE Havok packfile container: 64-byte
  header (magic pair, fileVersion 8, layout rules 8-1-0-1, contents pointers,
  "hk_2010.2.0-r1" version field), 48-byte section headers, local/global/
  virtual fixup tables with 0xFFFFFFFF sentinel + 0xFF alignment-tail
  handling, `__classnames__` signature+0x09+zstring inventory, virtual-fixup
  object enumeration (`objects`, `rootClassName`, `sectionData(at:)` for
  6.2+). Layout from open parsers (exyorha/hkxparse, ret2end/HKX2Library,
  ZeldaMods Havok wiki), probe-verified byte-by-byte on real skeleton.hkx +
  three idle clips (skeleton: 20 classes/324 objects; idles: 9 classes/5
  objects, hkaSplineCompressedAnimation). New `openskycli hkx <key>` dumps
  header/sections/classes/objects; probe gains skeleton + male/mt_idle hkx
  checks. Synthetic `HKXFixture` + `HKXFileTests` cover happy path +
  malformed input. Docs: [HKX container](/formats/hkx-container.md),
  [CLI](/tools/cli.md). Item 6.1 left [todo](/todo.md).
* Unscheduled backlog moved from [todo](/todo.md) to tracked GitHub issues:
  tree `.btt`/`.lst` LOD + configured distance bands
  ([#62](https://github.com/jjgroenendijk/opensky/issues/62)), GMST-backed walk/run/step
  tuning ([#63](https://github.com/jjgroenendijk/opensky/issues/63)), and creature
  `NiSkinPartition` palette handling
  ([#64](https://github.com/jjgroenendijk/opensky/issues/64)). Each issue records current
  code boundary, open-spec/probe leads, clean-room scope, synthetic tests, and acceptance
  gate; roadmap now keeps milestone + tooling work only.
* Screenshot LOD hole fixed — `openskycli screenshot` without `--neighbors` hid the
  full 5x5 from the distant-LOD pass while building only the center cell -> 24-cell
  ring with neither terrain nor LOD, sky visible through the gap (spotted in the M5
  acceptance check). `RenderCommand.sceneWithLOD` now hides only cells actually
  built; LOD fills the rest. Streaming engine unaffected (app/bench always build
  the full grid).
  Probe ruled water out for the dark basin west of the farmhouse: CELL `00009618`/
  `00009619` XCLW = `0x7F7FFFFF` default sentinel, Tamriel WRLD default water
  height -14000 vs terrain ~-4200 -> data defines no water surface there; the
  black field-plot + white plant fringes are a separate mesh shading defect,
  filed as a GH issue.
* M5.6 milestone acceptance complete — M5 (actors on screen) done. Failure
  accounting gains reasons: `ActorBuildCounts.failureReasons` ("ACHR <id>: <why>")
  threads through `CellLoadSummary` + `CellBuildMetric`; fly bench gates the new
  zero-unexplained rule (`failures == failureReasons.count`, new
  `actorFailureUnexplained` error) and returns per-cell `ActorCellReport`s that
  `bench --fly-path` prints (one accounting line per touched cell, failures carry
  reasons). `make probe` gains gates: 35 per-cell lines present, interior summary
  reports >=1 drawn actor. Full real probe pass: 55 discovered = 27 rendered + 27
  disabled + 1 failed, exact in all 35 cells; single failure reason-tagged — sabre
  cat `SabreCat.nif` `NiSkinPartition` vertex-bone-palette variant (backlog);
  ChillfurrowFarm interior 1 actors (1 drawn); 5,614 stream frames avg 3.15 ms/p95
  5.79 ms; actor build p95 2190.79 ms vs 3000 ms budget; footprint peak 702/1,024
  MB. Synthetic reason-accounting + metric-mirror tests added. M5 leaves
  [todo](/todo.md); M6 (actors animate: HKX idle playback) re-scoped into 6.1-6.6
  with gates.
* CI suspended (GH Actions CPU quota exhausted) -- `ci.yml` reduced to
  `workflow_dispatch` only; "Format & lint" + "Build & test" required status checks
  removed from main branch protection (PR-only flow stays). Git hooks are the only
  gate: pre-commit format/lint, commit-msg, pre-push build+test; `--no-verify`
  remains forbidden. AGENTS.md + commit skill note the suspension; re-enable task
  in [todo](/todo.md).
* M5.5 actor streaming integration complete -- ACHR placed actors build/evict with
  cells on the serial build queue (`CellSceneBuilderActors`): local + worldspace-
  persistent ACHRs (position-owned, door pattern, cached per WRLD), template/visual
  resolvers built once + cached like statIndex, assembled placements merged into each
  cell's RenderScene; interiors run the same pass. Body/head mesh keys join
  `CellScene.assets` -> evict with the cell; MeshLibrary retains skeletons. Record-header
  flag 0x800 decodes to `PlacedActor.isInitiallyDisabled` (UESP record flags) -> explicit
  skip while M5 has no script state. Exact per-cell accounting (discovered = rendered +
  disabled + failed) in `CellLoadSummary` + `CellBuildMetric`; `bench --fly-path` gains
  actor-build p95 + accounting gates (`--actor-build-budget-ms`, default 3000 ms after
  Debug baseline p95 2165 ms — first-load skinned bodies + FaceGen dominate; perf
  follow-up GH #56). Real fly path: 55 discovered = 27 rendered + 27 disabled + 1
  asset-level failure, exact in every cell; actor phase avg 425.76/p95 2164.08/max
  5832.06 ms; footprint peak 700/1,024 MB; 5,559 frames avg 3.14 ms/p95 5.75 ms.
  Chillfurrow interior probe: 1 actors (1 drawn). Synthetic builder-actor,
  streamer-lifecycle + record-flag tests. Docs:
  [actor records](/formats/actors.md), [cell scene](/engine/cell-scene.md),
  [cell streaming](/engine/cell-streaming.md), [CLI](/tools/cli.md). Item 5.5 left
  [todo](/todo.md).
* M5.4 actor assembly complete -- `ActorAssembler` composes race/gender skeleton,
  ordered outfit + visible skin ARMAs, dynamic FaceGen head, common ACHR DATA/XSCL
  transform + world bounds. Missing/invalid skeleton/models retain reason tags; any body/
  head survivor remains renderable, zero geometry tags `noCoreGeometry`. Mesh cache keys
  actor models by explicit skeleton. NIF adds spec-cited `BSDynamicTriShape`: appended
  float4 positions merge with position-free partition UV/normal/color/influence streams;
  FaceGen uses authored Head/Spine node pose. Synthetic tests cover gender/inherited
  source, slot masking, partial failure, no-core policy, transform, dynamic attributes +
  partition-local influences. Real Heimskr probe: boots/robes/hood/hands + 6-mesh head,
  correct ACHR pose, 800x800 offscreen 10.8% lit; visual check passed. Item 5.4 removed
  from [todo](/todo.md).
* M5.3 skinned NIF + GPU bind pose complete -- SSE `NiSkinInstance`/
  `BSDismemberSkinInstance`, `NiSkinData`, `NiSkinPartition`, partition-owned vertex/
  triangle streams, four half-weight/uint8 palette influences, dismember metadata.
  `skeleton.nif` NiNode tree resolves body dummy refs by name; mesh inverse binds remain
  authoritative for undistorted bind-only palettes. Renderer adds skin stream + bone
  matrix buffers, opaque/alpha skinned Metal 4 variants, residency. Synthetic parser,
  palette, skeleton, buffer/error tests pass. Vanilla `malebody_1.nif`: 2 textured meshes,
  1,802 vertices, 2,948 triangles; Asset Browser offscreen image lit, CPU bind bounds
  match source within 0.01 units. Item 5.3 left [todo](/todo.md).

## 2026-07-19

* M5.2 visual appearance resolution complete -- RACE (`Race`: per-gender ANAM
  skeletons, WNAM skin, DATA FaceGen-head flag), ARMO (`Armor`: MODL armature
  FormIDs, BOD2/BODT slots), ARMA (`ArmorAddon`: MOD2/MOD3 gendered models,
  race lists), OTFT (`Outfit`) decoders per UESP + nif.xml biped slots;
  `LeveledActor` generalized to `LeveledList` (LVLN + LVLI, new `useAll`
  bundle flag). `ActorVisualResolver` resolves skin (NPC_ WNAM else RACE
  WNAM) + outfit (DOFT -> OTFT -> ARMO/LVLI) chains to race-compatible ARMA
  models with cross-gender fallback, masks covered skin parts via BOD2 slot
  overlap, emits FaceGen facegeom/facetint paths (defining plugin +
  zero-padded objectID, gated on the RACE FaceGen-head flag). Broken chains
  throw (no silent naked fallback); optional gaps degrade to reason-tagged
  skips. `openskycli actor` prints visuals + gains `--npc` for named NPCs
  (residents live in interior cells); probe gates Heimskr. Real install:
  WhiterunWorld radius 2/4 -> 31/31, 75/75 incl. LVLI guard bundles;
  facegen paths cross-checked against BSA listings. Docs:
  [actor records](/formats/actors.md), [CLI](/tools/cli.md). Item 5.2 left
  [todo](/todo.md).
* M5.1 actor placement + template resolution complete -- ACHR (`PlacedActor`), NPC_
  (`ActorBase`: ACBS gender/template flags, TPLT, RNAM, WNAM, PNAM, DOFT), LVLN
  (`LeveledActor`, lenient 8/12-byte LVLO) decoders per UESP + xEdit specs.
  `ActorTemplateResolver` walks TPLT chains through NPC_ + LVLN (deterministic
  highest-level-first-tie entry), resolves each appearance field by its ACBS flag
  (traits/inventory), tags every field with its source NPC_, throws typed errors on
  cycles/dangling targets/empty lists. New `openskycli actor` probe: Tamriel (6,-2)
  radius 3 -> 107/107 ACHRs resolved, WhiterunWorld (5,-3) radius 2 -> 31/31; guard
  chains route through LVLN as expected. Synthetic fixture matrix covers
  direct/template/leveled, per-flag inheritance, inert flags, cycle, missing target,
  empty list. Docs: [actor records](/formats/actors.md), [CLI](/tools/cli.md).
  Item 5.1 left [todo](/todo.md).
* LOD diffuse DDS fixed -- parser accepts strict 32-bit legacy layouts: terrain xRGB8888
  (`DDPF_RGB`, BGRX masks) + shared object-atlas RGBA8888 (`DDPF_ALPHAPIXELS`, RGBA
  masks), validates pitch/mips, rejects other bit depths/flags/masks. Metal upload maps to
  sRGB BGRA8/RGBA8; absent xRGB alpha -> 255, stored RGBA alpha preserved. Synthetic
  parser + GPU readback tests cover full mip chains + malformed variants. Production CLI
  reports L4/L8/L16/L32 terrain (256x256, 8 mips) + object atlas (2048x2048, 11 mips).
  Whiterun 5x5 frame: 101 LOD blocks/0 unavailable, textured horizon, 100% non-background.
  Full 3,060 BTR + 717 BTO sweep: 0 failed. `make probe`: sustained 720p avg 0.87 ms/p95
  2.91 ms; cross-cell gate 35 unique builds/9 unloads/25 residents/0 void.
* M4.5 milestone acceptance complete -- `bench --walk-path` drives fixed 1/120 s production
  capsule physics from Tamriel `(6,-2)` to Chillfurrow Farm `(7,-3)`, climbs 22.82 units,
  enters CELL `00016204`, crosses 160.34 floor units, follows paired door back to recorded
  exterior pose. Hard gates cover timeout, fall-through, unresolved penetration, wrong
  door/CELL/return, failed cell/door builds, route distances + active-physics avg/p95.
  XTEL actor origin now seeds walk feet correctly. Large triangle soups partition into
  shared-vertex spatial leaves -> 640x360 route 1,065 frames, avg 15.90 ms (62.9 fps), p95
  29.69 ms, max 58.28 ms; pre-partition p95 was 40.66 ms at 480x270. Synthetic route/
  partition/XTEL/
  door-failure tests pass. Fly collision-build p95 budget revised 500 -> 700 ms after repeated
  Debug baselines varied 450.82-552.57 ms; partitioned p95 533.67-635.78 ms. M5 review retained
  numbered 5.1-5.6 sequence + measurable gates.
  M4 done; M5 active in [todo](/todo.md). Utility QoS retained: default/user-initiated trials
  raised walk p95 to 48.61/55.05 ms by competing with frame physics.
* M4.4 capsule/world response complete -- production walk mode queries streamed terrain +
  per-cell static collision. Swept submoves + closest-feature narrowphase cover triangle,
  convex, box, sphere, capsule geometry; iterative depenetration slides along walls, grounds
  ramps/floors, stops ceilings, reports unresolved overlap. 32-unit forward walkable-surface
  probe climbs low treads, rejects high risers/blocked headroom, spans terrain-to-mesh seams.
  XTEL scene camera reseed clears full controller state before next physics step; F/192-unit
  door activation unchanged. Synthetic wall/ramp/step/filter/seam/ceiling + teleport tests
  pass. Real-install probe passes; collision-build p95 450.82 ms under 500 ms budget. Docs:
  [walk mode](/engine/walk-mode.md), [collision world](/engine/collision-world.md).
  Item 4.4 left [todo](/todo.md).
* M4.3 static collision world complete -- each exterior/interior `CellScene` builds placed
  player-solid bhk geometry on serial stream queue, composing REFR x body x shape transforms.
  Per-cell immutable AABB BVH supplies seam-safe resident broadphase; decoded model cache uses
  render mesh keys + same unload keep-set, so scene/index/cache evict together. Collision-only
  NIFs remain physical; no-bhk models add none. CLI 5x5 probe: 1,795 shapes, 161,427 triangles,
  137 filtered bodies, zero gaps. Production 35-cell fly path: collision avg 112.78 ms,
  p95 464.63 ms under 500 ms gate; footprint peak 593/1,024 MB; frame p95 5.77 ms.
  Synthetic placement/interior/BVH/fake-provider lifecycle tests pass. Docs:
  [collision world](/engine/collision-world.md), [CLI](/tools/cli.md). Item 4.3 left
  [todo](/todo.md).
* M4.2 NIF collision decode complete -- `NIFFile.collisionModel()` follows bhk collision
  roots through rigid-body metadata, MOPP/list/transform wrappers, compressed/chunked meshes,
  packed/NiTriStrips collections, convex vertices, box/sphere/capsule primitives. Output
  preserves object flags + duplicate Havok filters/responses, converts 69.99125 units/m,
  isolates malformed roots, accounts unknown reachable blocks. Synthetic matrix covers every
  requested shape/wrapper/filter, big/chunk strips + malformed cycle. Production
  `openskycli collision` sweep over Tamriel `(6,-2)`: 9 models, 7 collision-bearing,
  12 roots/bodies, 13 shapes, 583 triangles, 0 unsupported, 0 decode failures; collision/
  render bounds validate scale + transform composition. Docs:
  [NIF collision](/formats/nif-collision.md), [CLI](/tools/cli.md). Item 4.2 left
  [todo](/todo.md).
* M4.1 terrain walk mode complete -- G toggles default fly camera to 24x128-unit player
  capsule with 112-unit eye, gravity, ground snap, 50-degree slope limit, hardcoded
  180/360-unit walk/run speeds. Controller consumes fixed 1/120 s steps with 100 ms frame
  clamp. Each streamed `CellScene` retains LAND/DNAM CPU field; composition query uses same
  floor ownership as streaming + exact `TerrainMeshBuilder` SW->NE triangle planes (height +
  face normal), not bilinear interpolation. Synthetic saddle, hidden-quadrant, negative/border
  cell, controller math + four-cell traversal tests pass. Real Tamriel probe walked `(6,-2)`
  -> `(9,-2)` at Y -8128 in 342 frames, grounded across three borders with 0.0-unit max
  plane clearance. Docs: [terrain walk mode](/engine/walk-mode.md). Item 4.1 left
  [todo](/todo.md).
* M4/M5 roadmap review fixes -- terrain walking now samples renderer-identical triangles;
  collision decode covers transform wrappers, alternate triangle collections + Havok
  filters with reachable-block coverage accounting. M4 gate becomes production
  `bench --walk-path` over M2 target -> Chillfurrow Farm -> interior -> return, measuring
  active physics instead of static render fps; cross-worldspace Whiterun-city travel stays
  out of hidden scope. M5 splits template semantics from visual appearance, applies ACBS
  inheritance flags, adds DOFT/OTFT outfit + body-slot resolution, reason-tagged actor
  accounting, actor-enabled stream budgets; gate moves to 5.6.
* Distant terrain coverage fixed -- L4/L8/L16/L32 selection partitions each cell exactly;
  partial BTR blocks clip crossing triangles to owned cell rectangles with interpolated
  attributes + mask-keyed GPU cache variants. LOD hides successful residents only, leaving
  void/failed slots covered. Settled recenter now stages replacement full cells while old
  grid + LOD remain live, then swaps cells + ring atomically. Synthetic ownership/area tests
  pass. Real Whiterun 5x5 frame: prior sky seams filled, 101 LOD blocks/0 unavailable, 975
  visible draws, 3,313 instances, 100% non-background. East/north fly path: 35 unique builds,
  9 unloads, 25 final residents; 5,192 frames avg 3.32 ms/p95 5.94 ms/max 17.75 ms.
* M4/M5 re-scope in [todo](/todo.md) -- M4 = walkable world: 4.1 terrain walk controller
  (LAND heightfield ground), 4.2 NIF bhk collision decode (NifTools `nif.xml`; Havok
  scale + `bhkCompressedMeshShapeData` layout flagged UNCONFIRMED), 4.3 per-cell
  collision world on the streaming build queue, 4.4 collide-and-slide capsule, 4.5 gate =
  walk-mode Whiterun round trip incl. interior, >30 fps via `openskycli bench`. M5 =
  actors on screen: 5.1 ACHR/NPC_/template/body-model record chain, 5.2 skinned NIF
  decode + GPU bind-pose skinning (`NiSkinInstance`/`BSDismemberSkinInstance`,
  `skeleton.nif`), 5.3 actor assembly (skeleton + ARMA parts + FaceGen head), 5.4
  actor streaming, 5.5 gate = bind-pose actors in Whiterun exterior + interior with
  probe-verified counts + fps gate. Byte layouts unverified -> confirm at impl; FaceGen
  path shape flagged UNCONFIRMED. M6+ direction unchanged; LOD-quality + GMST items
  moved to explicit backlog.
* M3 complete -- production probe passed exterior streaming + environment acceptance.
  5x5 scripted east/north flight built 35 unique cells once, unloaded 9, settled at 25
  resident/0 void with 458 -> 510 -> 470 MB waypoint footprint (559 MB peak); 4,784
  stream frames averaged 3.11 ms, p95 5.43 ms, max 19.64 ms at 640x360. Sustained
  1280x720 render averaged 0.77 ms, p95 0.97 ms across 360 frames. Integrated 25-cell
  frame resolved terrain, 3,396 object instances, water in 8 cells, procedural sky + 122
  LOD blocks with 0 unavailable. Chillfurrow Farm probe entered interior CELL 00016204
  through door 0001633D/000163A8, rendered arrival, returned to exterior `(7,-3)`.
  Numeric cell/frame results above remain the repository acceptance evidence.
  M4 numbering, scope + gate remain intentionally pending.
* M3.7 lighting complete -- CELL XCLL accepts exact 92-byte + field-boundary truncated
  tails; LTMP resolves LGTM DATA/DALC per XCLL inheritance bits. Skyrim.esm probe confirms
  directional rotation int32 values are degrees (`WhiteRunIntLightingTemplate` XY = 180).
  Exact 48-byte LIGH DATA + FNAM, REFR XRDS/XEMI decode into supported omni point lights;
  negative/spot/off lights skip. Interior forward path adds base + six-axis ambient,
  directional lambert, nearest 8 point lights per draw, distance fog. Exterior scenes keep
  existing `SceneCamera` sun/ambient + procedural sky. Chillfurrow Farm real round trip:
  232 refs, 118 draws, 69 models, 49 textures, 4 point lights; lit/unlit 1280x720 comparison
  shows cell fog/ambient shift, return to `(7,-3)` succeeds. Synthetic format/inheritance/
  selection tests + app/CLI Metal builds green. Docs:
  [lighting records](/formats/lighting.md), [renderer](/rendering/metal4-renderer.md),
  [interiors](/engine/interiors.md).

## 2026-07-18

* M3.6 interiors complete -- CELL top-group type-2/type-3 walk uses FormID decimal
  ones/tens label hints with full fallback; interior scenes reuse ref/base build without
  terrain/sky. DOOR joins ModelBase MODL coverage; REFR XTEL strict-decodes exact 32-byte
  destination pose/flags. WRLD persistent `(0,0)` XTEL refs map into physical streamed
  cells by position. F activates nearest door within 192 units; serial transition resolves
  destination CELL, swaps exact XTEL camera pose, suspends exterior grid/LOD inside,
  resumes + seeds destination exterior on return. `openskycli interior` acceptance found
  Chillfurrow Farm 0001633D `(7,-3)` -> interior CELL 00016204/door 000163A8 -> same
  exterior door; rendered 1280x720 textured interior frame. Synthetic decoder/builder/
  streamer/input tests cover malformed XTEL, untrusted labels, persistent ownership,
  proximity, suspension, exact pose, return. Docs: [records](/formats/records.md),
  [interiors](/engine/interiors.md), [streaming](/engine/cell-streaming.md),
  [CLI](/tools/cli.md).
* M3.5 sky + water complete -- exterior scenes now carry one procedural fullscreen sky
  marker unless WRLD says no-sky; hardcoded day/night/twilight gradient + sun disc driven
  by renderer time-of-day (`openskycli screenshot --time-of-day`, default 13:00). CELL
  XCLW height overrides decode all three no-water sentinels; missing height resolves WRLD
  DNAM through PNAM land-data inheritance. CELL XCWT/WRLD NAM2 select WATR; exact SSE DNAM
  228/232-byte variants decode shallow/deep/reflection RGBX only. Builder emits one cached
  4096-unit plane per water cell. Renderer adds first straight-alpha Metal 4 pipeline,
  read-only depth, animated color ripples + view-angle reflection. Synthetic decoder,
  builder, scene-merge, offscreen sky/time, blend tests green. Real-install target 5x5
  showed horizon + sun; nearby `WhiterunExterior17` (5,-4) resolved + rendered water.
  Water-cell bench: 120 frames @ 1280x720 avg 1.13 ms, p95 2.06 ms vs 33.33 ms budget.
  Docs: [water format](/formats/water.md), [sky + water](/engine/sky-water.md),
  [renderer](/rendering/metal4-renderer.md), [CLI](/tools/cli.md).
* M3.4 distant LOD complete -- strict 16-byte `lodsettings` parser; NIF multi-bound +
  `BSSubIndexTriShape` decode; BTR terrain + BTO object atlas loading; `WATER` subtree skip;
  lodsettings-anchored 4/8/16/32 rings outside loaded 5x5. LOD builds on serial streaming
  queue, composes without changing camera framing, retains/evicts shared assets safely.
  `openskycli lod` swept all vanilla Tamriel 3,060 BTR + 717 BTO with 0 failures. Real 5x5
  render: 122 LOD blocks, 0 unavailable, horizon filled, intersection-free selection.
  Tree billboards + boundary clipping deferred. Docs:
  [LOD format](/formats/lod.md), [LOD streaming](/engine/distant-lod.md),
  [CLI](/tools/cli.md).
* App + CLI screenshots -- World toolbar gains `Screenshot…`: save panel -> live camera +
  current streamed scene offscreen-rendered at drawable pixel size, PNG output excludes app
  chrome; disabled in Asset Browser. New `openskycli screenshot --out` uses existing
  cell/grid/zoom render options; `render` kept as compatibility alias. Shared
  `FrameScreenshot` owns BGRA readback + PNG encoding across app, CLI, previews, tests.
  Probe now writes `logs/probe-screenshot.png`. Docs: [main app](/tools/preview-gui.md),
  [CLI](/tools/cli.md).
* M3.3 complete -- asset browser merged into main app: one OpenSky window now launches in
  World mode and swaps in-place to a persistent Asset Browser. AppKit browser/detail/
  Settings shells moved under `opensky/`; AppKit-free catalog + engine preview pipeline
  unchanged. Main menu gains Settings Cmd+, + Edit; data-root changes re-resolve locator,
  rebuild World renderer/streamer dependencies, reload browser without relaunch. Missing
  install now renders remediation in-window, no modal alert. Removed `openskypreview`
  target/scheme/source dir + `make preview`; CLI excludes app-only shells. UI smoke covers
  default mode, switch, missing-data state, Settings; env-gated real install rendered
  World + selected NIF in browser, full-window screenshots under `logs/`; real catalog +
  DDS/NIF preview pipeline passed. Preview image compression priorities keep mode switch
  from resizing window. Docs: [main-app asset browser](/tools/preview-gui.md),
  [game data locator](/engine/game-data-locator.md).
* **M3.2 complete -- guarded async cell streaming**: launch starts empty and builds one
  center-out cell at a time off main; demo camera cannot recenter before first seed. Local
  backlog + runner pending-set dedupe bound work; per-cell mesh/texture ownership,
  resident-union drop sets, serial eviction, stale-success cleanup, transactional renderer
  swaps, and overlap-safe retire purge make unload safe. External-volume 15 GiB fill growth
  traced to `.mappedIfSafe` copying ~14.6 GiB BSA set; BSA/ESM now `.alwaysMapped`.
  Repaired real harness disables parallel tests, preflights exact selector + executed count,
  guards `task_vm_info.phys_footprint`, reuses targets, paces, and times out. Guarded 5x5:
  25 resident/0 void, ~444 MB fill, <0.5 GB peak. New shared
  `CellStreamingFlyBenchmark` + `openskycli bench --fly-path`: center -> east -> north,
  433 -> 425 -> 419 MB settled (462 MB peak), 35 unique builds exactly once, 9 initial
  cells unloaded, final 25/0, avg 2.79 ms/p95 5.33 ms/max 53.48 ms at 1280x720. Docs:
  [cell streaming](/engine/cell-streaming.md), [CLI](/tools/cli.md).
* **Async cell streaming controller** (M3.2 async build): new
  `World/CellStreamer.swift` drives live streaming from one main-thread
  `update(cameraPosition:)`. Concurrency: `CellSceneBuilder` +
  `MeshLibrary` + `TextureLibrary` confined to ONE serial `DispatchQueue`
  (`SerialCellBuildRunner`, qos utility) -- queue over actor so builds run
  one-at-a-time with no reentrancy and the caches stay lock-free
  (confinement, not locking); main only gets finished `CellScene` values.
  `CellSceneProvider` is the build seam (`BuilderCellSceneProvider` in the
  app, fakes in tests); `CellBuildRunning` abstracts the executor. Pure
  `CellStreamCore` value type holds resident/inFlight/void/failed sets:
  `accountedCells` feeds `CellGridManager` so void slots (`cellNotFound`) +
  failed builds are remembered and never re-requested (no retry storm);
  `integrate` discards stale/out-of-order completions (unloaded mid-flight).
  Per-frame budget: at most one drawable cell integrated (a swap is a full
  recompose); void/failed/stale drained free; requests dispatched
  center-out. `CellGridManager.cellCenter(of:)` added to seed the grid on a
  launch cell. Docs: [cell streaming](/engine/cell-streaming.md) controller
  * concurrency sections; MeshLibrary/TextureLibrary threading comments.
  Tests: `CellStreamCoreTests` (dedupe, void/failed no-retry, unload forget,
  stale/out-of-order), `CellStreamerTests` (fake runner: budget order,
  recenter unload, first-cell-only camera reseed).
* **Instanced draws for repeated models** (M3.2 renderer core): instances
  sharing mesh + material draw as one `drawIndexedPrimitives(...
  instanceCount:)`. `RenderScene` now builds `DrawGroup`s (mesh, material,
  `[DrawInstance]`; key = mesh + diffuse ObjectIdentifiers, first-appearance
  order); `RenderScene(merging:)` re-groups across cells. Per-draw GPU data
  split: `DrawUniforms` keeps material scalars in the 256-aligned ring
  (per group), matrices move to new tightly-packed `InstanceTransform`
  ring (128 B stride, `instanceSlotCapacity` per slot, same pow2
  regrow-on-swap). `staticMeshVertex` gains `[[instance_id]]` + `device
  InstanceTransform*` at `BufferIndexInstanceTransforms` (arg table 5
  buffers); terrain stays non-instanced. Culling composes per instance:
  only visible transforms written, group drawn with visible count,
  all-culled group skipped. `openskycli render` prints a draw-stats line
  (docs/tools/cli.md updated). Real install: Whiterun (6,-2) 49 instances
  -> 32 draw calls; 3x3 grid 711 -> 330; grid frame differs from
  pre-instancing baseline by 54/921600 px (draw-order z-fight edges, max
  delta 34) — visually identical; bench avg 0.47 ms / p95 0.50 ms. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) instanced draws section.
  Tests: `RendererInstancingTests` (one call for N instances w/ projected
  pixel evidence, culling composes), grouped-scene updates across
  `RenderSceneTests`/`DemoSceneTests`/`CellSceneBuilderTests`/
  `CellSceneCompositionTests`.
* **Swappable renderer scene + retire list** (M3.2 renderer core):
  `Renderer.setScene(_:camera:)` swaps the drawable scene between frames
  (main thread, same as draw(in:); never blocks on the GPU). Draw-uniform
  ring sized by `drawUniformSlotCapacity` (next pow2 >= drawCount, min 1),
  regrown on swap when exceeded; old scene allocations + replaced rings go
  on a retire list tagged with `frameIndex - 1`, released only once
  `endFrameEvent.signaledValue` proves those frames drained. Residency:
  setScene only adds (MTLResidencySet removals hit at commit() even with
  frames queued); removal happens at purge, filtered against the live set
  (A->B->A swaps, shared cell assets). Optional camera param reseeds
  sun/ambient + free-fly pose. New `World/CellSceneComposition.swift`:
  resident `[CellCoordinate: CellScene]`, setCell/removeCell,
  composedScene() via RenderScene(merging:) in (x,y) order,
  composedBounds() — container for the upcoming streaming controller.
  Real-install verify: Whiterun 3x3 PNG byte-identical, bench avg 0.51 ms /
  p95 0.61 ms. Docs: [metal4-renderer](/rendering/metal4-renderer.md) scene
  swap section. Tests: `RendererSceneSwapTests` (regrow swap, empty-scene
  clear frame, camera reseed), `CellSceneCompositionTests`.
* **Frustum culling wired into the renderer** (M3.2 renderer core): per-draw
  world AABBs + per-frame culling. New `RenderPlacement` (model, transform,
  world bounds) replaces the `RenderScene` instance tuples; `DrawItem` /
  `TerrainDrawItem` carry `bounds: ModelBounds?` (nil -> never culled). Cell
  build threads `MeshLibrary.bounds(forPath:).transformed(by:)` onto items
  (same value the cell AABB already unioned); terrain items get per-patch
  bounds; DemoScene computes its own. `encodeScenePass` builds one
  `Frustum(viewProjection:)` per frame -> skips failing items; per-draw ring
  now indexed by running visible-draw cursor (visible <= drawCount = ring
  capacity). Per-frame counts exposed as `Renderer.lastDrawStats`
  (`SceneDrawStats`). Encode path split to
  `Rendering/RendererScenePass.swift` (file-length limit, RendererSetup
  precedent). Real-install verify: `openskycli render --x 6 --y -2
  --neighbors` byte-identical PNG before/after (7.4% non-background);
  `openskycli bench` avg 0.55 ms / p95 0.74 ms vs 33.33 ms budget. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) Frustum culling section.
  Tests: `RendererCullingTests` (culled-vs-drawn stats + pixel checks,
  all-culled clear frame), existing offscreen/scene suites green.
* **Widen base coverage, M3.2**: `CellSceneBuilder` drew STAT bases only; MSTT, TREE,
  FURN, ACTI, CONT placements fell into the (now-gone) non-STAT skip bucket. New shared
  decoder `ModelBase` (`opensky/Formats/ESM/Records/ModelBase.swift`) reads EDID + MODL
  for all five types (UESP "Skyrim Mod:Mod File Format" /MSTT /TREE /FURN /ACTI /CONT —
  same field layout as STAT); animation/interaction fields stay unread, model path only.
  `CellSceneBuilder` gains a second lazy FormID -> `ModelBase` index over the five
  top groups (STAT stays first, largest, most common); `resolveInstances` tries STAT
  then ModelBase before giving up. Skip bucket `nonSTATSkipCount`/`nonSTATBases` renamed
  to `unsupportedBaseSkipCount`/`unsupportedBases` (`CellScene.swift`,
  `CellSceneBuilder.swift`) — now means "base FormID resolves to neither index" (DOOR,
  NPC_, ACHR, IDLM, MISC, FLOR, SOUN, ... bases, or a malformed base record), not
  "non-STAT". Real-install verify (`openskycli render`, `/Volumes/data/steam/...Skyrim
  Special Edition`): WhiterunExterior06 (6,-2) 16 refs went from 15/16 to 16/16 drawn
  (the lone ACTI now draws); WhiterunExterior02 (5,-3) 17/25 -> 25/25; WhiterunExterior10
  (7,-1) 28/34 -> 34/34; ChillfurrowFarmExterior (7,-3, 134 refs, all 5 new types
  present) 75/134 -> 104/134 (30 skipped: 13 unsupported-base — IDLM/MISC/DOOR/SOUN/FLOR,
  genuinely out of scope — plus 17 load-failed on a handful of CONT/FLOR plant meshes
  with what looks like a doubled-backslash path quirk in that plugin's MODL data, caught
  and skipped by the existing mesh-load skip bucket, never crashing). Visually verified:
  `openskycli render --neighbors` over the (6,-2) 3x3 grid — city props (wells, crates,
  furniture) and farm trees now draw where they were previously invisible, no artifacts.
  Docs: [record decoders](/formats/records.md), [cell scene](/engine/cell-scene.md).
  Tests: `RecordDecoderTests` ModelBase cases, `CellSceneBuilderTests` new base-type
  draw/marker cases + renamed skip-bucket assertions.
* **Cell streaming grid manager** (M3.2, grid-manager sub-item): new
  `opensky/World/CellGridManager.swift` -- pure `simd`-only value type, camera
  `SIMD3<Float>` position -> desired NxN exterior-cell grid (`uGridsToLoad`
  default 5 -> radius 2, ref UESP "Skyrim:INI Settings" Grid section), diffed
  against a caller-supplied loaded set. Floor-division cell mapping (not
  truncation -- negative coords land correctly). Ownership split: the manager
  tracks only its desired center cell; the loaded set stays with the caller
  so async loads (later commit, same 3.2 item) can finish out of order or
  fail without the manager drifting from reality -- `update` always diffs
  fresh against whatever `loaded` the caller reports that frame. Hysteresis
  (128-unit margin, checked per axis) stops a camera oscillating across a
  cell border from thrashing load/unload. Docs:
  [cell-streaming](/engine/cell-streaming.md). Tests: `CellGridManagerTests`
  -- floor mapping incl. negative/boundary coords, 5x5 grid contents, radius
  parameter, one-cell-move diff (leading/trailing edge), hysteresis no-thrash,
  decisive-crossing, diagonal-corner cases.
* **Frustum culling math** (M3.2, math only): new `Rendering/Frustum.swift` —
  `Frustum(viewProjection:)` extracts 6 inward planes from a `P * V` matrix
  (Gribb/Hartmann 2001, adapted to column-vector convention + Metal's z in
  [0, 1] clip range: near = row2 alone, not row3 + row2), plus a conservative
  positive-vertex `intersects(min:max:)` AABB test and a `ModelBounds`
  convenience overload. Pure, renderer-independent — `Renderer.swift`/
  `RenderScene.swift` wiring lands with rest of 3.2 cell streaming so world
  AABBs are available per loaded cell. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) Frustum culling section.
  Tests: `FrustumTests` (ahead/behind/left/right/above/below, near-plane
  straddle kept, beyond-far culled, enclosing box kept, degenerate point).
* **Agent workflow efficiency — skills split + dev-loop make targets**: transcript
  mining of 35 sessions (3.7k shell commands) drove two changes. (1) Makefile gains
  the observed repeated loops as targets: `fix` (format then strict lint, one shot),
  `test-one T=Class[/test]` (replaces hand-typed `xcodebuild -only-testing`
  invocations), `test-report` (newest `.xcresult` summary via `xcresulttool`),
  `app-path`/`cli-path` (built-product paths via `-showBuildSettings`, replaces
  DerivedData globbing), `run-cli ARGS=...` (build + exec `openskycli`). (2) Root
  AGENTS.md slimmed to always-relevant rules (295 -> 197 lines); conditional
  workflows moved to skills under `.AGENTS/skills/`: new `format-parser`
  (reverse-engineering discipline), `docs-wiki` (OKF rules), `probe` (env-gated
  real-data scratch-test template modeled on `CellRenderRealDataTests`, MainActor
  rules, offscreen render verification paths) joining existing `commit`.
  `docs/todo.md` handoff section cut to pointers; stale PR-state snapshot removed
  (live state comes from `gh pr list`). `openskypreview` gains a real
  main menu (Settings… Cmd+, / Edit / Quit) and a Settings window that shows
  the resolved game data root + source and lets the user pick the install
  folder via `NSOpenPanel` — validated + persisted through new
  `GameDataLocator.saveUserChoice`/`clearUserChoice`; browser catalog reloads
  live on change (new `PreviewViewController.reload`, catalog-load generation
  counter drops stale loads). Data-root setting now lives in shared defaults
  domain `nl.jjgroenendijk.opensky` (`GameDataLocator.settingsDefaults`) so
  app/preview/CLI read one setting despite differing bundle ids. Docs:
  [preview-gui](/tools/preview-gui.md), [locator](/engine/game-data-locator.md).
  Tests: `GameDataLocatorTests` save/clear cases.
* **Terrain 3x3 grid verify, closes M3.1** (M3.1): `openskycli render --neighbors` builds
  the target cell plus its 8 grid neighbors off one shared `MeshLibrary`/`TextureLibrary`/
  `CellSceneBuilder` (residency + STAT index dedup across cells, not a streaming grid
  manager — that's 3.2) and composes the 9 `CellScene`s with new `RenderScene(merging:)`
  (`opensky/Rendering/RenderScene.swift`: flat concat of the opaque/alpha-tested/terrain
  draw lists — items already carry absolute world matrices, no re-transform). Camera
  generalizes `SceneCamera.framing` to the union of all 9 bounds. A neighbor slot that
  fails to build (void grid position, malformed worldspace) warns to stderr and is
  skipped, not fatal. Real-install run over Tamriel (6,-2) + 8 neighbors (Whiterun): all 9
  slots built (WhiterunExterior02/03/05/06/08/09/10, ChillfurrowFarmExterior, cell
  000095F9), 0 missing textures, 4 terrain quads/cell; visually verified (default + a
  temporary steep top-down angle, not committed) — terrain continuous under the M2 walls
  across all 9 cells, no height cracks or gaps at any internal cell border, splat
  variation visible city-wide. Docs:
  [terrain](/engine/terrain.md) Verification section, [cli](/tools/cli.md) `--neighbors`.
  Tests: `RenderSceneTests` merge cases (concat counts, cross-scene residency dedup, empty
  input). Closes milestone 3.1 (`docs/todo.md`).
* **Terrain splat pipeline** (M3.1): third render pipeline (`TerrainSplat`,
  `terrainVertex`/`terrainFragment`) blends each quadrant's BTXT base with up
  to 8 ATXT layer diffuses by per-vertex VTXT opacities in one draw. Binding
  decision: per-quadrant multi-texture argument-table binds (base at
  `TextureIndexDiffuse`, `array<texture2d, 8>` at `TextureIndexTerrainLayer0`;
  `texture2d_array` rejected — layer diffuses vary in size/format; per-layer
  draws rejected — blend pipeline + N draws/quadrant). Weights = second vertex
  stream (`BufferIndexTerrainWeights`, two float4 lanes) — static 48-byte
  layout untouched. `TerrainMeshBuilder` now emits `Patch` values (mesh + base
  FormID + layers, VTXT baked dense: position 0-288 = 17x17 row-major, UESP
  LAND); `CellSceneBuilder` resolves base + layer LTEX->TXST diffuses, drops
  broken layer chains (counted, `terrainLayerSkipCount`), packs weights, emits
  `RenderScene.terrain` items. Blend = ordered `mix(albedo, layer, opacity)`;
  exact vanilla curve UNCONFIRMED. Cap `TerrainConstantMaxLayers = 8` (format
  max; vanilla ~6/quadrant). Lighting identical to static path; TX01 normal
  maps deferred. Docs: [metal4-renderer](/rendering/metal4-renderer.md) splat
  section + [terrain](/engine/terrain.md) rewrite. Tests: weight bake/pack +
  layer routing (`TerrainMeshBuilderTests`), resolution + blend order + drop
  accounting (`CellSceneTerrainTests`), GPU pixel-level blend proof
  (`TerrainSplatRenderTests`), terrain residency (`RenderSceneTests`). Visual:
  WhiterunExterior06 render — 4 quads, 14 layers, dirt/grass/rock/snow
  transitions under the M2 walls.
* **Terrain mesh build** (M3.1): new `opensky/World/TerrainMeshBuilder.swift`
  turns a decoded LAND into engine `Mesh`/`Model` values — 33x33 vertex grid,
  128-unit quads over the 4096 cell, heights passthrough (VHGT already *8),
  VNML normals (`v/127` normalized, zero/absent -> up), VCLR colors, UVs
  `(c,r)/2` (density UNCONFIRMED, tuned in splat commit). One sub-mesh per
  painted, non-hidden quadrant (XCLC quad-flags force-hide) with its BTXT base
  material resolved BTXT -> LTEX(TNAM) -> TXST(TX00) via `ESMWalk`, paths
  canonicalized through `NIFShaderTextureSet.vfsKey`. `CellSceneBuilder` places
  terrain at `(gridX*4096, gridY*4096)` (REFR world frame), appends opaque
  DrawItems under the objects, feeds `CellScene.bounds`, adds
  `terrainQuadrantCount` to the summary. LAND-less exterior cell -> flat plane
  at WRLD DNAM default land height (new `Worldspace.defaultLandHeight`/
  `defaultWaterHeight`; Tamriel -27000); DNAM absent -> no ground (UNCONFIRMED,
  probe later). Docs: [terrain subsystem](/engine/terrain.md), cell-scene LAND
  note updated. Synthetic-fixture tests (`TerrainMeshBuilderTests`,
  `CellSceneTerrainTests`). Edge-overlap probe (`LandRealDataTests`, real
  Tamriel): 4 adjacent pairs, 0 mismatched edge vertices — shared row/col match
  exactly, overlap claim confirmed (streaming can weld by dropping a shared edge).
  Splat render is the next 3.1 item.
* **LAND/LTEX/TXST decoders** (M3.1): new terrain record decoders in
  `opensky/Formats/ESM/Records/{Land,LandTexture,TextureSet}.swift` +
  [land format doc](/formats/land.md). LAND = VHGT gradient height field
  (float anchor + 33x33 int8 deltas; col 0 carries row-to-row, cols 1-32
  accumulate west->east, result *8 game units), VNML/VCLR 33x33x3 bytes,
  BTXT base + paired ATXT/VTXT splat layers (quadrant 0-3, VTXT position
  0-288, float opacity). LTEX TNAM -> TXST TX00 diffuse / TX01 normal. Ref
  UESP LAND/LTEX/TXST + xEdit `wbDefinitionsCommon.pas`. Synthetic-fixture
  unit tests (`TerrainRecordDecoderTests`) + env-gated Tamriel sweep
  (`LandRealDataTests`). Sweep over vanilla Skyrim.esm: 11186 LAND records
  decoded no throws, height -37032..39392 units, up to 23 cell-wide splat
  layers, VTXT position max 288, quadrants {0,1,2,3}. Decoders only; mesh
  build + splat render are later 3.1 items.
* **Milestone 3 detailed plan**: expanded [todo](/todo.md) M3 into sub-itemed
  3.1-3.7 (terrain -> streaming -> LOD -> sky/water -> interiors -> lighting
  -> gate) with per-item acceptance, spec refs, probe strategy, dependency
  order (3.4/3.5 parallelizable vs 3.2/3.3). Format facts pre-verified
  against open specs — UESP mod-file-format pages (LAND/CELL/WRLD/LTEX/TXST/
  REFR/DOOR/WATR/LGTM/LIGH/WTHR/CLMT, LOD Settings File Format), xEdit
  `dev-4.1.6` source (`wbDefinitionsTES5.pas`, `wbDefinitionsCommon.pas`,
  `wbLOD.pas`, `wbImplementation.pas`), DynDOLOD docs + xLODGen LODGen
  source. Key facts folded into item text: VHGT row-carry x8 height decode;
  .btr/.bto are NIF containers (BSMultiBoundNode / BSSubIndexTriShape),
  level N = NxN cells SW-anchored, 16-B lodsettings; XTEL 32-B dest-REFR
  teleport; interior block/sub-block = FormID last decimal digits; XCLW
  no-water sentinels; XCLL truncation variants. Flagged UNCONFIRMED for
  impl-time probes: LAND-less-cell flat-plane fallback, live per-quad layer
  limit (~6, community), XCLL rotation units, vanilla .btr/.bto blocks
  beyond what xLODGen emits.
* **Milestone 2 accepted** (2.11, complete — M2 left [todo](/todo.md)):
  target cell textured + recognizable, free-fly verified (2.7/2.8), fps
  gate measured not eyeballed via new `openskycli bench` — offscreen path
  split into `RendererOffscreen.swift`, every frame FrameStats-instrumented,
  `renderOffscreenSustained` returns per-frame wall times. Apple M1,
  Debug, real install, `WhiterunExterior06`, 360 frames: avg 0.39 ms
  (2557 fps) p95 0.43 ms @ 1280x720; avg 0.54 ms (1846 fps) @ 1920x1080 —
  far above the 30 fps bar. `bench` wired into `make probe`; `render`
  gained `--zoom` (framing camera alone leaves ~4% of pixels covered).
  Numeric output remains in [renderer doc](/rendering/metal4-renderer.md). M3
  items re-checked against M2 (notes in todo): ordering unchanged,
  `CellSceneBuilder` is the streaming unit, bench/preview are the M3
  verification path.
* **Agent rules restructure**: root AGENTS.md slimmed — tool-target rules
  moved next to the code (`openskycli/AGENTS.md`,
  `openskypreview/AGENTS.md`, each with `CLAUDE.md` symlink), commit/PR
  procedure moved to a skill (`.AGENTS/skills/commit/SKILL.md`,
  `.claude/skills` symlinks to it; `.claude/*` harness state now
  gitignored). Root keeps the global contract + non-negotiables.
* **Asset preview GUI** (2.10, complete): new `openskypreview` app target
  (same synchronized-group sharing as the CLI; `make preview` builds).
  Programmatic AppKit browser: category popup (meshes/textures/records/
  all) with filter and lazy table over `PreviewCatalog` (archive entries
  via `VirtualFileSystem.archiveEntries()` + headers-only `ESMWalk` over
  every Skyrim.esm record); catalog load + record filtering off-main. Detail
  pane: NIF -> single-model offscreen render via MeshLibrary + framing
  camera; DDS -> `TexturePreviewScene` textured quad with black sun +
  white ambient (fragment output = sampled texel); record ->
  `RecordTextDump` (shared impl — CLI `record` prints the same string;
  `ESMWalk` moved to `opensky/Formats/ESM/`). Missing install ->
  in-window message, app still launches. Unit tests: catalog grouping +
  filter, dump format, quad math; env-gated `PreviewRealDataTests`
  verified against the real install (172,750 entries, 869,687 records,
  `logs/preview-dds.png` + `logs/preview-nif.png`). Doc:
  [asset preview GUI](/tools/preview-gui.md). Item 2.10 left
  [todo](/todo.md).

## 2026-07-17

* **CLI dev tool** (2.9, complete): new `openskycli` command-line target
  sharing the engine sources via a synchronized-group exception set
  (app-only files excluded); entry code in `openskycli/`. Subcommands:
  `vfs ls`/`vfs cat` (new `VirtualFileSystem.archiveEntries()`, tested),
  `record` (FormID/EDID lookup + decoded dump), `cell` (Metal-free
  exterior-cell summary), `nif`/`dds` (parser-eye asset inspection),
  `render` (offscreen cell -> PNG via `Renderer.renderOffscreen`).
  `make cli` builds; env-gated `make probe` (`tools/probe.sh`) smoke-runs
  all commands against the local install, self-skips without game data,
  logs to `logs/`. Verified on the real install: cell/record match the
  first-render-cell decision (16 refs, 15 STAT), render PNG shows the
  Whiterun walls (4.3% non-background). stdlib arg parsing —
  swift-argument-parser rejected while the surface stays small. Doc:
  [CLI dev tool](/tools/cli.md). Item 2.9 left [todo](/todo.md).
* **Item 2.8 complete — free-fly camera**: fly the rendered cell with
  WASDQE + mouse-look. New `FreeFlyCamera` (pure pose -> view matrix +
  per-frame integration; yaw about +Z, pitch clamped +/-89 deg) and
  `CameraInputState` (logical pressed-key/pointer/boost state) — both
  AppKit-free, unit-tested (`FreeFlyCameraTests`, `CameraInputStateTests`):
  orientation vs conventions, pitch clamp, movement direction relative to
  yaw, boost, seed reproduces the 2.7 framing view. Input capture in new
  `GameMetalView` (MTKView subclass): NSEvent key/pointer -> state, click
  grabs pointer (`NSCursor.hide` + `CGAssociateMouseAndMouseCursorPosition`),
  Esc/focus-loss releases. `Renderer` holds a live camera seeded from the
  injected `SceneCamera`, advances it each frame with real clamped `dt`;
  nil input (offscreen/tests) -> static seeded pose, so offscreen tests
  unchanged. Speeds: base 1800 units/s (~2.3 s per 4096-unit cell), Shift
  x3.5. Doc: [free-fly camera](/engine/free-fly-camera.md). Item 2.8 left
  [todo](/todo.md).
* **Item 2.7 complete + coordinate decisions final**: real-data render of
  `WhiterunExterior06` verified visually (offscreen PNG) — 16 refs, 15
  drawn, 1 non-STAT skip, 0 missing textures; wall runs join correctly,
  nothing inside-out -> winding + REFR euler sign/order in
  [coordinates](/decisions/coordinates.md) upgraded from provisional to
  final. Item 2.7 left [todo](/todo.md).
* **Cell render at launch** (2.7 app wiring, part 2): AppDelegate locates
  game data before window content, wires a scene factory into
  `GameViewController` (runs on the view's Metal device): VFS ->
  `ESMFile` -> `TextureLibrary` -> `MeshLibrary` -> `CellSceneBuilder` ->
  `SceneCamera.framing(bounds:)` -> injected `Renderer`. Target constants
  centralized in `opensky/FirstRenderCell.swift` (Tamriel (6,-2)). Any
  factory failure -> `[ERROR]` log + DemoScene fallback, never crash;
  build synchronous at startup (fine for one small cell). New env-gated
  `CellRenderRealDataTests`: real-install build + offscreen render +
  `logs/cell-whiterunexterior06.png`, auto-skips without
  `OPENSKY_DATA_ROOT`. Doc: [cell scene build](/engine/cell-scene.md).
* **Scene + camera injection** (2.7 app wiring, part 1): `Renderer` init
  is now `init(view:scene:camera:)` — optional prepared `RenderScene` +
  `SceneCamera`; nil -> DemoScene + `.demo` camera, so existing tests/CI
  run unchanged. `updateFrameUniforms` reads the stored camera, per-draw
  ring sized off the injected scene. New `SceneCamera`
  (`opensky/Rendering/`): `.demo` constants + `framing(bounds:)` — frames
  a Z-up AABB from south-west/above at `radius / sin(fovY/2) * 1.1`,
  min 64 units; unit-tested. Doc:
  [Metal 4 renderer](/rendering/metal4-renderer.md).
* **Cell scene build** (2.7): new `opensky/World/` — `CellSceneBuilder`
  walks WRLD top group -> world children -> exterior blocks (labels
  ignored, XCLC decoded) -> CELL + children -> persistent/temporary REFR
  records; STAT index (lazy, raw FormIDs, single plugin); instances via
  `MatrixMath.placement`, sorted by (mesh path, FormID) -> adjacent per
  model (instancing-ready) -> opaque-first `RenderScene`. Robustness:
  per-ref/asset failures log + skip + count (malformed / non-STAT /
  marker / load-failed buckets), only worldspace/cell absence throws;
  `CellLoadSummary.summaryLine` one-liner after load. `MeshLibrary` now
  records a model-space `ModelBounds` AABB at parse time ->
  `CellScene.bounds` world AABB for camera framing. Doc:
  [cell scene build](/engine/cell-scene.md).
* **First-render-cell decision** (2.7): probe over Tamriel grid box
  [-2,10]x[-9,3] (170 cells, 9 720 STATs) -> target = `WhiterunExterior06`
  at (6,-2): 16 refs, 94% STAT, 8 distinct models, all VFS-resolvable,
  recognizable Whiterun walls. Farm cells rejected (127-153 refs, 28-34
  models). Probe fact binding scene build: STAT MODL paths carry no
  `meshes\` prefix, VFS keys do -> prepend before lookup. Doc:
  [first render cell](/decisions/first-render-cell.md).

## 2026-07-10

* **Winding decision corrected by observation** (2.6): demo ground plane
  (only single-sided flat mesh) culled away under the provisional
  `.clockwise` front — closed boxes masked it by showing interior faces.
  Front = counter-clockwise seen from outside (right-hand-rule outward
  normals), cull back; matches OpenMW's GL rendering of the same content.
  [Coordinates](/decisions/coordinates.md) winding section rewritten,
  no longer provisional; re-verify against vanilla NIFs at 2.7.
* **Static-mesh render path** (2.6): triangle placeholder replaced.
  Opaque + alpha-test pipeline variants (function constant, one fragment
  fn); `FrameUniforms`/`DrawUniforms` 256-byte-aligned rings (per-draw
  ring = slots x drawCount); binds via one `MTL4ArgumentTable` (state
  captured per draw); trilinear+aniso repeat sampler; depth32Float +
  less/write; per-draw cull-none for double-sided. `FrameStats` logs
  per-120-frame window (frame interval/fps, CPU encode, GPU ms via
  `MTL4CounterHeap` timestamps + `sampleTimestamps` correlation) — the
  2.9 fps gate measure. `Renderer.renderOffscreen` renders one frame
  synchronously into an owned target: deterministic pixel tests + PNG,
  future 2.9 screenshot. Windowless `MTKView.currentDrawable` crashes in
  `waitForDrawable` -> never test through drawables (`docs/testing.md`).
  Scene types: `StaticVertexLayout` (48-byte interleave + descriptor),
  `RenderMesh`/`RenderModel`/`RenderScene` (opaque-first draw lists,
  residency dedup), `DemoScene` (synthetic proving scene, throwaway at
  2.7). Doc: [Metal 4 static-mesh renderer](/rendering/metal4-renderer.md).
  Item 2.6 complete -> left [todo](/todo.md).

* **DDS probe acceptance** (2.5): swept all 32 920 `.dds` in the local
  install's BSAs — 22 636 BCn parsed clean (BC3 18 074 / BC1 4 417 /
  BC2 145; vanilla has zero DX10/BC7 files), 10 284 rejected with typed
  errors as designed (10 225 uncompressed RGB face/tint/UI art, 58
  cubemaps, 1 volume -> placeholder path). Max dim 8192 -> fixed stale
  4096 comment. Farmhouse set (candidate 2.7 area): 64/64 full decode +
  GPU upload. Numbers folded into
  [DDS texture container](/formats/dds.md). Item 2.5 complete -> left
  [todo](/todo.md).
* **DDS -> MTLTexture upload** (2.5): `Rendering/TextureLoader.swift` (new
  `opensky/Rendering/` dir, noted in AGENTS.md layout) — BCn
  `MTLPixelFormat` per usage (`TextureUsage.color` -> sRGB view, `.data` ->
  linear; BC4/5 have no sRGB variants), full mip chain via
  `MTLTexture.replace`, `.shared` storage (unified memory). Failure path:
  parse/upload error or missing file -> log + shared 1x1 placeholder
  (mid-gray color / flat normal), never crash. GPU tests gated on
  `supportsBCTextureCompression` (paravirtual CI GPUs lack it).
* **DDS container parser** (2.5): `Formats/DDS/DDSFile.swift` — magic +
  DDS_HEADER + optional DDS_HEADER_DXT10; FourCC DXT1/3/5, ATI1/2, BC4U/5U +
  DXGI UNORM/`_SRGB` codes -> BC1-BC5/BC7; tightly packed mip chain sliced by
  4x4-block math, `bytesPerRow` for `MTLTexture.replace`; cubemap/volume/
  array/uncompressed -> typed `unsupported`, truncated chain -> `malformed`.
  Ref: Microsoft DDS programming guide. Doc:
  [DDS texture container](/formats/dds.md).
* **NIF materials probe acceptance** (2.4): resolved materials for all
  22 196 geometry-BSA `.nif` (zero failures): 50 407 materials, 1 356
  fallback, 9 096 alpha-test, 5 329 blend, 1 362 double-sided; 99.6% of
  diffuse keys resolve in the texture BSAs after teaching `vfsKey` the
  engine's last-`textures/` truncation (vanilla ships exporter-absolute
  paths); 198 remaining misses are genuinely absent vanilla textures ->
  2.5 placeholder rule. `Model.materials` now carries resolved engine
  `Material` values (`Geometry/Material.swift`); `MaterialSlot` block refs
  replaced. Item 2.4 complete -> left [todo](/todo.md).
* **NIF material block decoders** (2.4): `Formats/NIF/NIFShaderProperty.swift`
  — BSLightingShaderProperty (Skyrim layout: shader type before the
  NiObjectNET name, flags 1/2, UV offset/scale, texture set ref, alpha,
  glossiness, specular; type-conditional tail unread);
  `NIFTextureSet.swift` — BSShaderTextureSet slots + `vfsKey(for:)` path
  normalization (lowercase, `\` -> `/`, strip `data/`, ensure `textures/`);
  `NIFAlphaProperty.swift` — AlphaFlags blend/test bits + threshold.
  `NIFObjectNET` split out of the AV prefix (property blocks lack NiAVObject
  fields). Ref: NifTools `nif.xml`. Doc: [NIF mesh](/formats/nif.md)
  materials subset.
* **NIF geometry probe acceptance** (2.3): typed decode sweep over the
  geometry BSAs (Meshes0/1, _ResourcePack) — 22 196 `.nif` through
  `NIFFile.model()`, zero errors; 51 671 meshes, 23.5 M verts, 23.3 M tris,
  5 751 skinned/empty shapes skipped. Candidate-static AABBs plausible vs
  the 4096-unit cell (farmhouse01 1409 x 705 x 744). Numbers folded into
  [NIF mesh](/formats/nif.md). Item 2.3 complete -> left [todo](/todo.md).
* **NiNode scene-graph decode** (2.3): `Formats/NIF/NIFObject.swift` — shared
  NiObjectNET + NiAVObject prefix (name via string table, flags, T/R/S,
  collision ref; Skyrim streams 83/100 only) with `localTransform` = T·R·S;
  `NIFNode.swift` — children refs, one layout for NiNode + append-only
  subclasses (BSFadeNode…), selector nodes excluded.
  `BinaryReader.readFloat32`. Ref: NifTools `nif.xml`. Doc:
  [NIF mesh](/formats/nif.md) scene-graph + NiNode sections.
* **BSTriShape geometry decode** (2.3): `Formats/NIF/NIFTriShape.swift` —
  bounding sphere, skin/shader/alpha refs, BSVertexDesc bitfield -> attribute
  flags + stride cross-check, interleaved BSVertexDataSSE records (full-float
  positions — SSE never packs them half, unlike FO4; half UVs, normbyte
  normals/tangents, split bitangent reassembled, colors; skinning/eye bytes
  skipped), validated uint16 triangle list, SSE particle trailer ignored.
  Stride/data-size mismatch -> `malformed`. Ref: NifTools `nif.xml`
  (BSVertexDataSSE, BSVertexDesc); normbyte remap per NifSkope/nifly. Doc:
  [NIF mesh](/formats/nif.md) BSTriShape section.
* **NIF scene flatten -> engine meshes** (2.3): `Geometry/Mesh.swift` — engine
  `Mesh`/`Model`/`MaterialSlot` types decoupled from disk layout;
  `Formats/NIF/NIFModel.swift` — `NIFFile.model()` walks footer roots,
  composes `parent * local` transforms, decodes BSTriShape leaves, dedups
  material slots by (shader, alpha) ref pair, skips skinned/empty shapes
  (counted), throws `malformed` on bad refs/cycles/depth > 64. New
  `opensky/Geometry/` dir noted in AGENTS.md layout. Doc:
  [NIF mesh](/formats/nif.md) "Scene graph -> engine mesh".
* **NIF container probe acceptance** (2.2): walked every `.nif` in the local
  install — 22 806 files across 8 BSAs, all parsed, zero throws. All version
  20.2.0.7 / user 12; BS stream 100 except one 83. 143 distinct block types;
  histogram + M2 coverage list folded into [NIF mesh](/formats/nif.md).
  Item 2.2 complete -> left [todo](/todo.md).
* **Lossy text decode for NIF strings** (2.2): probe over vanilla meshes hit
  exporter garbage in one string table (bytes undefined in cp1252) ->
  `GameText.decodeLossy` (UTF-8 -> cp1252 -> ISO 8859-1, never nil), used for
  NIF header strings so a junk name cannot reject a mesh. Note in
  [NIF mesh](/formats/nif.md).
* **NIF block walk** (2.2): `Formats/NIF/NIFFile.swift` — slices every block
  payload by the header size array (unknown types skipped by construction),
  reads footer roots, `blockTypeCounts()` histogram for probes. Oversized
  block / truncated footer -> `NIFError.malformed`. Doc:
  [NIF mesh](/formats/nif.md) block walk + footer sections.
* **NIF header parser** (2.2): `Formats/NIF/NIFHeader.swift` — version line,
  version (20.2.0.7 only), endian byte, user version, BSStreamHeader (83/100),
  block type table, per-block type index (PhysX bit masked) + size array,
  string table, groups. Typed `NIFError`. Ref: NifTools `nif.xml`. Doc:
  [NIF mesh](/formats/nif.md).
* **MatrixMath growth** (2.1): `zUpToYUp` basis change, `rotationX/Y/Z`,
  `scale(uniform:)`, `lookAt` (RH, works straight off Z-up world vectors),
  `placement(position:rotation:scale:)` = `T * Rz(-z) * Ry(-y) * Rx(-x) * S` for
  REFR data. Unit tests: axis mapping, det +1, eye/target properties, yaw sign,
  TRS round-trip. Item 2.1 complete -> left [todo](/todo.md).
* **Coordinates + units decision** (2.1):
  [decision doc](/decisions/coordinates.md) — world space stays Skyrim Z-up RH at
  native units, view/projection convert to Metal NDC; fixes column-major `M * v`,
  clockwise front + back cull (provisional, verify at 2.6), near 10 / far 65 536
  units, REFR euler = `Rz(−z)·Ry(−y)·Rx(−x)` (sign/order flagged for 2.7 visual
  check). Backed by probe over vanilla `Skyrim.esm`: 236 187 temporary refs in
  6 372 Tamriel exterior cells — all positions inside their 4096-unit grid square,
  all rotations within ±2π (radians).
* **Milestone structure in todo**: [todo](/todo.md) — added "Milestones at a glance"
  overview (M1 done -> M4, one goal + one gate each), gave milestone 3 a goal line,
  numbered items 3.1-3.6 and an acceptance gate 3.7 (mirrors M2's shape), marked M4 as
  direction-only pending re-scope at 3.7. Item content unchanged.
* **Headless unit-test host + testing doc**: `OpenSkyApp.main()` skips
  `AppDelegate` (window/renderer/probe) when `XCTestConfigurationFilePath` is
  set, activation policy `.prohibited` -> `make test` runs with no visible
  window. UI smoke test guards the normal launch path. Split earlier same day:
  `make test` = unit only, `make test-ui` = XCUITest suite, CI runs both.
  Doc: [testing setup](/testing.md).
* **Renderer skeleton doc**: audit of done-item wiki coverage found one gap — Metal 4
  render loop knowledge lived only in code. Added
  [Metal 4 renderer skeleton](/rendering/metal4-renderer.md) (command flow, frame pacing,
  256-byte uniform ring buffer, argument tables, residency, MatrixMath conventions);
  filled the empty Rendering section in [index](/index.md).
* **Todo hygiene rule**: AGENTS.md — done item leaves `docs/todo.md` in the same commit,
  knowledge folds into the wiki + this log; todo holds open work only. Applied to
  [todo](/todo.md): dropped "Done" + completed milestone 1 sections (history lives here,
  layouts in `docs/formats/`).
* **Milestone 2 detailed plan**: expanded [todo](/todo.md) milestone 2 into
  sequenced sub-items 2.1-2.9 (coordinates decision -> NIF container/geometry/
  materials -> DDS -> renderer -> cell scene -> camera -> acceptance) with
  per-item acceptance criteria, spec refs, probe strategy, dependency order.

## 2026-07-09

* **Record decoders + lstring wiring**: `Formats/ESM/Records/` — `Worldspace`
  (WRLD), `Cell` (CELL, both DATA sizes, 8/12-byte XCLC), `PlacedReference`
  (REFR pos/rot/scale), `StaticObject` (STAT MODL), `LString` +
  `GameData/LocalizedStrings.swift` (table lookup through the VFS, lazy per
  kind, language pick). Shared lenient decode moved to `Formats/GameText.swift`.
  Doc: [records](/formats/records.md). Milestone 1 acceptance met — probe
  listed 37 worldspaces (names via string tables), counted cells (16 978
  exterior), dumped WhiterunExterior01's 100 STAT refs with model paths.
* **Localized string tables**: `Formats/Strings/StringTable.swift` —
  `.strings`/`.dlstrings`/`.ilstrings` reader (header + directory, zstring
  vs length-prefixed framing, lenient UTF-8 -> windows-1252 decode).
  `BinaryReader.readZStringData` added for caller-chosen encodings. Doc:
  [string tables](/formats/strings.md). Verified against all 273 vanilla
  table files (10 languages, 834 865 strings, 0 failures).
* **FormID + master resolution**: `Formats/ESM/PluginHeader.swift` (TES4
  HEDR/CNAM/SNAM/MAST decode) + `FormID.swift` (`FormID`, `ResolvedFormID`,
  `FormIDResolver` — top byte -> master index, out-of-range clamped to the
  plugin, null -> nil). Doc: [FormID](/formats/formid.md). Verified against
  all five vanilla masters. Lint config: `inclusive_language` now allows
  "master" — TES4 domain term (MAST), spec traceability.
* **ESM/ESP container walk**: `Formats/ESM/` — TES4 + top-group index over a
  memory-mapped plugin, lazy GRUP/record traversal, zlib record decompression
  (`Formats/Zlib.swift` over Apple Compression), field iterator with XXXX size
  extension, shared `FourCC` type code. Doc: [ESM container](/formats/esm.md).
  Verified against vanilla Skyrim.esm (870 k records, all payloads parse).
* **VFS / resource manager**: `GameData/VirtualFileSystem.swift` +
  `ArchiveLoadOrder.swift` — one lookup layer over the data root. Loose files
  override archives, later archives override earlier, case/separator-
  insensitive keys, lazy archive open, malformed archives logged + skipped.
  Load order: ini resource lists (Skyrim.ini -> Skyrim_Default.ini -> built-in
  vanilla) then plugin-named archives. Doc: [VFS](/formats/vfs.md).
* **Game data locator**: `GameData/GameDataLocator.swift` — env var ->
  UserDefaults -> default Steam path, fail-loud alert + os_log on missing/invalid,
  no silent fallback. Doc: [game data locator](/engine/game-data-locator.md).
  Verified against real install (`/Volumes/data/steam/...`) via unified log.
* **Roadmap**: expanded [todo](/todo.md) into full milestone plan (M1 game data ->
  M4 playable) + agent handoff instructions (branch/PR state, machine quirks,
  format-work discipline).
* **BSA parser**: BSA v105 reader (`Formats/BSA/`), clean-room LZ4
  frame/block decoder, bounds-checked BinaryReader. Docs:
  [BSA format](/formats/bsa.md). Verified against vanilla SSE archives at
  runtime; synthetic-fixture unit tests.
* **macOS conversion**: iOS template -> native macOS-only app, Xcode 26.3 project
  format (objectVersion 100), programmatic AppKit + Metal 4 rotating-triangle
  skeleton, shared scheme, MatrixMath + tests. See
  [decision](/decisions/native-macos-app.md). Rewrote [todo](/todo.md) as roadmap.
* **Creation**: Initialized docs wiki and project development tooling
  (AGENTS.md, git hooks, lint/format, CI).
