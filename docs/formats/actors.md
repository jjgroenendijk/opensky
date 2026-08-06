---
type: File Format
title: Actor records (ACHR, NPC_, LVLN/LVLI, RACE, ARMO, ARMA, OTFT) + resolution
description: Actor records, appearance resolution, GPU asset assembly, and FaceGen paths.
tags: [format, plugin, actors, achr, npc, leveled, template, race, armor, outfit, facegen]
timestamp: 2026-07-30T00:00:00Z
---

# Actor records, Skyrim SE

Milestones 5.1, 5.2 + 5.4 subset: enough decode to place actors, resolve who they
look like, and assemble GPU skeleton/body/FaceGen assets at world pose — no stats,
AI, factions, spells, or carried inventory yet. Container framing:
[ESM/ESP plugin container](/formats/esm.md); decode
policy (skip unknown fields, `ESMError.malformed` only on structurally
unusable input): [record decoders](/formats/records.md).

Reference: UESP "Skyrim Mod:Mod File Format" subpages `/ACHR`, `/NPC_`,
`/LVLN`, `/LVLI`, `/RACE`, `/ARMO`, `/ARMA`, `/OTFT`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>);
xEdit dev-4.1.6 `wbDefinitionsTES5.pas` (template flag masks) +
`wbDefinitionsCommon.pas` (`wbLeveledListEntry`); CK wiki "Template Data"
(flag -> tab coverage); NifTools `nif.xml` `BSDismemberBodyPartType`
(biped slot numbering). Impl: `opensky/Engine/Formats/ESM/Records/` +
`opensky/Engine/World/ActorResolution.swift` +
`opensky/Engine/World/ActorVisualResolution.swift` + `opensky/Engine/World/ActorAssembly.swift`.

## ACHR -> PlacedActor

Placed NPC. REFR-shaped; lives in the same CELL persistent/temporary children
groups. Worldspace-persistent ACHRs are stored under the (0,0) persistent
cell; physical position decides streamed-cell ownership (door pattern,
[cell scene](/engine/cell-scene.md)).

| field | type     | decoded                                 |
| ----- | -------- | --------------------------------------- |
| NAME  | formID   | `base` (NPC_), required                 |
| DATA  | float[6] | `placement` pos + rot radians, required |
| XSCL  | float    | `scale`, absent -> 1.0                  |
| VMAD  | struct   | `scriptData` attachment accumulator     |

Record-header flag 0x800 (UESP record flags) decodes to `isInitiallyDisabled`:
actor placed but hidden until quest/script enables it -> explicit render skip
while M5 has no script state. VMAD layout and binding:
[Papyrus attachment data](/formats/vmad.md). Skipped for now: XEZN encounter
zone, patrol data, XRGD/XRGB ragdoll, XLCM level modifier, XESP enable parent,
XOWN owner, XLCN/XLRL location, XLKR link (4- or 8-byte), header flag 0x200
(starts dead).

## NPC_ -> ActorBase

Appearance-relevant subset:

| field | type    | decoded                                        |
| ----- | ------- | ---------------------------------------------- |
| EDID  | zstring | `editorID`                                     |
| FULL  | lstring | `name`                                         |
| ACBS  | struct  | `flags`, `templateFlags` (below), required     |
| TPLT  | formID  | `template` — NPC_ or LVLN, absent -> no chain  |
| RNAM  | formID  | `race` (RACE), required by spec                |
| WNAM  | formID  | `wornArmor` — skin ARMO; absent -> race skin   |
| PNAM  | formID  | `headParts` (HDPT), one per repeated subrecord |
| DOFT  | formID  | `defaultOutfit` (OTFT)                         |
| VMAD  | struct  | `scriptData` attachment accumulator            |

ACBS, 24 bytes:

| offset | type   | field                                      |
| ------ | ------ | ------------------------------------------ |
| 0x00   | uint32 | flags (0x01 female, 0x20 unique, ...)      |
| 0x04   | int16  | magicka offset (skipped)                   |
| 0x06   | int16  | stamina offset (skipped)                   |
| 0x08   | uint16 | level or PC-level-mult x1000 (skipped)     |
| 0x0A   | uint16 | calc min level (skipped)                   |
| 0x0C   | uint16 | calc max level (skipped)                   |
| 0x0E   | uint16 | speed multiplier (skipped)                 |
| 0x10   | uint16 | disposition base (skipped)                 |
| 0x12   | uint16 | template data flags                        |
| 0x14   | int16  | health offset (skipped)                    |
| 0x16   | uint16 | bleedout override (skipped)                |

Template data flags: 0x0001 traits, 0x0002 stats, 0x0004 factions, 0x0008
spell list, 0x0010 AI data, 0x0020 AI packages, 0x0040 model/animation
(UESP: "unused?"; xEdit names it, CK omits it — do not rely on it), 0x0080
base data, 0x0100 inventory, 0x0200 script, 0x0400 def pack list, 0x0800
attack data, 0x1000 keywords.

## LVLN / LVLI -> LeveledList

Leveled NPC + leveled item lists share one layout (UESP documents the entry
struct once); one decoder accepts both record types.

| field | type    | decoded                                                 |
| ----- | ------- | ------------------------------------------------------- |
| EDID  | zstring | `editorID`                                              |
| LVLD  | uint8   | `chanceNone` (always 0 for LVLN per UESP)               |
| LVLF  | uint8   | `flags`: 0x01 all levels, 0x02 each count, 0x04 use all |
| LVLO  | struct  | `entries[]`, one per subrecord                          |

LVLF 0x04 "use all" marks a bundle: every entry applies at once (probed:
`ArmorStormcloakSet` = boots + cuirass + gauntlets + helmet list). Without it
the list is alternatives — one entry is picked.

LVLO: UESP documents 12 bytes (uint32 level, formID reference — NPC_ or
nested LVLN, uint32 count). xEdit's `wbLeveledListEntry` reads uint16 level +
2 pad + formID and accepts an 8-byte form with count defaulting 1 —
byte-identical for sane values; OpenSky decodes the lenient shape. COED owner
data (own subrecord after an LVLO) + OBND/LLCT/MODL are skipped.

## RACE -> Race

Appearance subset only; DATA stats, spell lists, keywords, body-part/tint
data, and morphs stay undecoded.

| field     | type    | decoded                                             |
| --------- | ------- | --------------------------------------------------- |
| EDID      | zstring | `editorID`                                          |
| FULL      | lstring | `name`                                              |
| WNAM      | formID  | `defaultSkin` — ARMO worn when the NPC_ has no WNAM |
| BOD2/BODT | struct  | `bodyTemplate` (shared decode, below)               |
| DATA      | struct  | `flags` — uint32 at offset 0x20 only                |
| MNAM/FNAM | marker  | 0-byte gender markers gating model blocks           |
| ANAM      | zstring | `maleSkeletonPath` / `femaleSkeletonPath`           |

DATA flags (UESP RACE): 0x1 playable, 0x2 FaceGen head. Probed values:
playable races carry 0x2, creature races (cow/dog/bear) do not — this bit
gates FaceGen path emission.

Gendered skeleton block ordering (probed on NordRace): `MNAM`(0 bytes) ->
male `ANAM` + `MODT`, then `FNAM`(0 bytes) -> female `ANAM` + `MODT`. Later
MNAM/FNAM markers open other gendered blocks (body models, head data) whose
bodies carry MODL — ANAM appears only in the skeleton block, so pairing ANAM
with the most recent marker is unambiguous; first path per gender wins.

## ARMO -> Armor

One equippable piece. Worn geometry comes from ARMA armatures; the ARMO's own
MOD2/MOD4 path strings are the ground/inventory ("_GO") models and are
skipped, as are enchantment/value/keywords.

| field     | type    | decoded                                         |
| --------- | ------- | ----------------------------------------------- |
| EDID      | zstring | `editorID`                                      |
| FULL      | lstring | `name`                                          |
| RNAM      | formID  | `race` filter (usually 0x19 DefaultRace)        |
| BOD2/BODT | struct  | `bodyTemplate` — equip slots for masking        |
| MODL      | formID  | `armatures[]` — one ARMA per repeated subrecord |

ARMO MODL is a 4-byte ARMA FormID, never a path (probed: SkinNaked carries
25); non-4-byte MODL is skipped defensively.

## ARMA -> ArmorAddon

How a piece displays on a body: per-gender models + applicable races. Texture
swaps (NAM0-3) and MODT hashes are skipped.

| field     | type    | decoded                                       |
| --------- | ------- | --------------------------------------------- |
| EDID      | zstring | `editorID`                                    |
| BOD2/BODT | struct  | `bodyTemplate` — slots the armature covers    |
| RNAM      | formID  | `primaryRace`                                 |
| DNAM      | struct  | draw priorities + weapon adjust (below)       |
| MODL      | formID  | `additionalRaces[]` (base + vampire variants) |
| MOD2      | zstring | `maleModelPath` (3rd person)                  |
| MOD3      | zstring | `femaleModelPath` (3rd person)                |
| MOD4      | zstring | `maleFirstPersonModelPath` (1st person)       |
| MOD5      | zstring | `femaleFirstPersonModelPath` (1st person)     |

MOD4/MOD5 are the models drawn on the first-person arms
([behavior graph runtime](/engine/behavior-runtime.md), "First person"), and they
are declared far less often than MOD2/MOD3: probed on the local install
2026-08-04, of the ARMA records reachable from vanilla iron armour only the torso
and hand armatures carry one. `firstPersonModelPath(female:)` falls back across
genders exactly as the third-person accessor does, and returns nil rather than the
third-person path when neither gender declares one — a third-person cuirass on a
first-person rig would be skinned to a skeleton that does not have its bones.

Probed: ARMA records at form version 40 emit 12-byte BODT while ARMO/RACE at
44 emit 8-byte BOD2 — the shared decoder accepts both.

### DNAM, 12 bytes

```text
00 uint8   male draw priority
01 uint8   female draw priority
02 4 bytes weight-slider flags (xEdit) / one unknown uint32 (UESP)
06 uint8   detection sound value
07 1 byte  unused
08 float32 weapon adjust
```

UESP and xEdit name bytes 2-5 differently and agree on every offset. Only the
two priorities and `weaponAdjust` are carried; detection sound is stealth and
the weight sliders are body morphs, neither of which this engine has. A
payload shorter than 12 bytes decodes as far as it reaches rather than
throwing — a missing priority degrades to the same reading as no DNAM, while
refusing the record would drop an armature that renders fine.

**Priority is a draw order, not a visibility rule.** The Creation Kit wiki
"ArmorAddon" page: priority "is used to determine the order of the
ArmorAddons. The base naked body (for all parts) is always 0. The armor for a
torso would then be 5 and gloves that you want to draw over the ends of
sleeves, for example, would be 10." Probed, and this is the case that settles
it:

```text
openskycli record OrcishCuirassAA
  -> slots 0x114 (body|forearms|calves), priority male 5 female 5
openskycli record OrcishBootsAA
  -> slots 0x180 (feet|calves),          priority male 10 female 10
```

The two share the calves slot and the boots outrank the cuirass there. Were
priority a visibility rule, equipping Orcish boots would delete the Orcish
cuirass, because one armature covers body, forearms *and* calves and hiding
it for losing one slot takes the torso with it. Vanilla draws both. So
OpenSky sorts worn parts by ascending priority and hides nothing on that
basis; hiding stays the equipped-slot mask's job.

## OTFT -> Outfit

| field | type    | decoded                                          |
| ----- | ------- | ------------------------------------------------ |
| EDID  | zstring | `editorID`                                       |
| INAM  | formID[]| `items[]` — packed uint32 array, size/4 entries  |

Entries mix ARMO and LVLI freely (probed: guard outfits nest LVLI bundles);
size not a multiple of 4 -> malformed.

## Body template (BOD2/BODT) + biped slots

Both shapes open with a uint32 biped-slot bitfield; bit N = biped slot
(30 + N), numbering per nif.xml `BSDismemberBodyPartType` (SBP_30_HEAD ...
SBP_61_FX01). BOD2 = slots + uint32 armor type (8 bytes). BODT = slots
[+ uint32 general flags] + uint32 armor type; the 8-byte BODT omits the
general-flags word, making the tail ambiguous -> armor type nil there.

## Template resolution (ActorTemplateResolver)

TPLT + template flags control which record supplies each field group
(UESP NPC_ ACBS notes + CK "Template Data"):

* traits (0x0001): race, gender, skin, height/weight, voice, death item,
  character-gen tabs -> head parts. WNAM sits on the CK Traits tab, so it
  rides this flag (inference — neither source names WNAM explicitly).
* inventory (0x0100): outfits (DOFT) + carried items, not the death item.
* base data (0x0080): name + essential/protected/respawn-style flag bits
  (not yet consumed by the bind-pose milestone).

Chain walk: follow TPLT unconditionally (flags select per-field, not
per-link); an LVLN hop picks its entry deterministically for the bind-pose
milestone — highest level wins, first among ties (`deterministicEntry`) —
instead of rolling player level against chance-none. Per-field rule: a record
delegates a field upward only while it has a TPLT and the field's flag set; a
set flag without TPLT is inert; the chain tail always provides. Every
resolved field carries its source NPC_ FormID. Cycles, dangling FormIDs, and
empty lists throw typed `ActorResolveError`s; index misses degrade to
`missingTarget`, never a crash.

Indexes stay raw-`UInt32`-keyed within one plugin (CellSceneBuilder
convention); cross-plugin identity waits for load-order support (FaceGen
already resolves through `FormIDResolver` to defining plugin + objectID).

## Visual resolution (ActorVisualResolver)

Turns a template-resolved appearance into renderable inputs:

* Skeleton: RACE ANAM for the resolved gender.
* Skin chain: NPC_ WNAM else RACE WNAM -> ARMO -> race-compatible ARMAs.
* Outfit chain: NPC_ DOFT -> OTFT INAM entries; ARMO used directly, LVLI
  expanded — `useAll` lists take every entry (bundle), others take the
  deterministic entry (highest level, first among ties, matching the LVLN
  policy). Cycle detection tracks only the active chain so duplicate
  siblings stay legal.
* Slot masking: equipped ARMO BOD2/BODT slots union into a mask; a skin
  armature whose slots overlap it is hidden (no duplicate geometry under
  clothes). ARMA slots decide the overlap, falling back to the owning
  ARMO's slots.
* ARMA race compatibility: `primaryRace` match or membership in the
  additional-race MODL list.
* Gendered model: MOD2 male / MOD3 female with cross-gender fallback —
  vanilla ships male-only ARMAs worn by both genders (probed:
  `StormCloakBootsAA`); skip only when neither model exists.
* First-person model: every resolved part also carries its MOD4/MOD5 path
  when the ARMA declares one, so `firstPersonProjection(skeletonPath:)` can
  swap a whole resolved visual onto the `_1stperson` rig without re-walking
  any chain. A part with no first-person model is dropped there with reason
  `noFirstPersonModel` rather than falling back to its third-person mesh.

Failure policy (milestone gate): broken chains throw typed
`ActorVisualError`s — dangling race/skin/outfit/item FormIDs, empty or
cyclic leveled lists. Never a silent naked fallback. Missing optional parts
degrade to reason-tagged `AppearanceSkip`s (dangling armature, no compatible
armature, no model, masked by outfit, duplicate armature, missing skeleton
or body slots, unrenderable equipment, no first-person model) so
accounting stays exact.

## Runtime equipment (M12.2.1)

`resolve(appearance:equipped:)` takes an optional equipped-FormID set that
*replaces* the DOFT chain for that actor. Nil — an actor nothing has touched —
resolves through DOFT exactly as before.

Replacement rather than merge, because the baseline equipped set already *is*
the default outfit (`InventoryBaselineResolver.actorBaseline`); merging the
two would re-dress an actor the moment anything undressed it. An empty
equipped set therefore means a stripped actor, and the skin the outfit was
hiding comes back.

Each equipped FormID resolves to one of three things:

* a known ARMO -> a worn piece, through the same ARMA selection and slot
  masking the outfit path uses;
* an equippable WEAP with a MODL -> a `ResolvedAttachment` (below);
* anything else -> an `AppearanceSkip` tagged `unrenderableEquipment`.

A runtime equipped set never throws. A broken DOFT chain is malformed plugin
data and the gate says throw; an equipped FormID naming nothing renderable is
ordinary runtime state — a mod item, a script equipping a token — and
degrades to a tagged skip.

Where the set comes from: `CellSceneBuilderActors` reads the actor's
`ReferenceInventoryState` out of the build's `WorldStateSnapshot`. Refresh is
the ordinary `noteStateMutation` cell rebuild (see
[runtime state](/engine/runtime-state.md)); there is no patching path.

## Weapon hand attachment (M12.2.1)

A drawn weapon is a rigid model hung off a named skeleton bone. Bone names are
observed from the install, never assumed — `openskycli skeleton` over
`meshes\actors\character\character assets\skeleton.hkx`:

| rig bone      | parent                | meaning                        |
| ------------- | --------------------- | ------------------------------ |
| `Weapon` (43) | `NPC R Hand [RHnd]`   | drawn right-hand weapon        |
| `Shield` (42) | `NPC L Hand [LHnd]`   | drawn left-hand shield         |
| `Quiver` (60) | spine                 | quiver                         |
| `WeaponSword`, `WeaponAxe`, `WeaponDagger`, `WeaponMace` | pelvis | sheathed |
| `WeaponBack`, `WeaponBow` | spine     | sheathed on the back           |

OpenSky uses `Weapon`. The sheathed nodes belong to draw/sheath, which is M15.
The matching node in `skeleton.nif` is spelled `WEAPON` (uppercase) while the
Havok rig spells it `Weapon`, so `NIFSkeleton.transform(forBoneNamed:)` folds
case; skin bone names match exactly and take the fast path.

`RenderScene` bakes every placement's transform into its draw instances when
the scene is built, and cell scenes are built on the streaming queue rather
than per frame — so an attachment cannot be a placement with a fixed
transform. The one per-frame transform channel that already exists is GPU
skinning, so `RigidAttachment` rewrites the weapon model as a skinned mesh
with exactly one bone, named after the attachment node. The pose the actor's
clip already computes for `Weapon` then moves it, with no new per-frame code.

Given the shader's `world = modelMatrix * (bone * v)` and
`modelMatrix = actorTransform * meshLocal`, the palette halves are:

```text
rootParentToSkin   = meshLocal⁻¹
skinToBoneMatrices = [meshLocal]
bindPoseMatrices   = [meshLocal⁻¹ · restTransform · meshLocal]

world = actorTransform · meshLocal · meshLocal⁻¹ · boneWorld · meshLocal · v
      = actorTransform · boneWorld · (meshLocal · v)
```

which is the weapon's own geometry placed at the bone, in the actor's space.
The bind matrix uses the skeleton's rest transform for the node, so a model
that is never animated still hangs in the right place instead of collapsing
to the origin.

Attachment placements carry nil bounds (never culled): the model's own bounds
sit at the weapon's origin, not where the hand carries it, so pushing them
through the actor transform would name a box the geometry is never in.

A mid-clip swap **resumes**, it does not restart. `Renderer.animationTime` is
a monotonic clock a cell rebuild never touches, and
`RenderScene.updateAnimations(at:)` samples every resident actor from it, so
the playback a rebuild produces is sampled at the same world time as the one
it replaced. No bind-pose frame appears because `Renderer.draw` poses before
it encodes.

Out of scope here: draw/sheath animations (M15), shields-on-back and
dual-wield placement, ARMA texture swaps, and the DNAM `weaponAdjust` float,
which is decoded but not yet applied to the attachment offset.

## FaceGen paths

Baked head assets, keyed by the NPC_ that provides character-gen data (the
traits source). Convention verified against the real install (BSA listing +
per-NPC cross-checks):

```text
meshes\actors\character\facegendata\facegeom\<plugin>\<id8>.nif
textures\actors\character\facegendata\facetint\<plugin>\<id8>.dds
```

`<plugin>` = defining plugin file name lowercased (`skyrim.esm`); `<id8>` =
8-hex zero-padded FormID with the load-order byte forced to `00` (== the
24-bit objectID). Lowercase extensions, backslash separators — matches VFS
key normalization. Emitted only when the race carries the FaceGen-head DATA
flag (0x2): creature races bake none, while head-part-less humanoids
(e.g. Nazeem, PNAM-free) still have files.

## Actor assembly

`ActorAssembler` consumes one `PlacedActor` + `ResolvedActorVisual` and an
`ActorAssetProvider`:

* Load race/gender skeleton once; missing/invalid skeleton becomes tagged skip.
* Load resolved outfit parts first, remaining visible skin parts next, FaceGen head last.
  `MeshLibrary` caches each GPU model by normalized path + explicit skeleton key.
* Apply one `MatrixMath.placement(position:rotation:scale:)` to every part, preserving
  ACHR DATA pose + XSCL uniform scale. Per-model bounds transform into one actor world AABB.
* Preserve appearance skips; model/skeleton failures add exact missing/invalid asset tags.
  Any surviving body or head model keeps partial actor renderable. Zero models adds
  `noCoreGeometry` and rejects skeleton-only output.

FaceGen `BSDynamicTriShape` details + node-reference pose live in
[NIF mesh](/formats/nif.md). `faceGenTintPath` stays attached to head role for later tint
composition; current NIF material diffuse/vertex color renders baked head geometry.

## Actor streaming (5.5)

`CellSceneBuilderActors.swift` runs the full chain on the serial cell build
queue: ACHR collection (local persistent + temporary children; exterior cells
union in worldspace-persistent ACHRs owned by physical position — door
pattern) -> template resolve -> visual resolve -> assembly -> placements merged
into the cell's `RenderScene`. Resolver pair (`ActorTemplateResolver` +
`ActorVisualResolver`) builds once on the first actor-bearing cell, cached on
the builder like `statIndex`. Actor body/head mesh keys join `CellScene.assets`
-> evict with the cell; skeletons live outside cell assets (`MeshLibrary`
retains `actorSkeletons` + character skeleton across evictions).

Accounting is exact per cell: `discovered = rendered + disabledSkips +
failures`. Discovered = non-deleted ACHRs owned by the cell; disabled =
initially-disabled header flag (intentional skip, no script state yet);
failures = malformed record, unresolved chain, or assembly with zero
geometry. Every failure also records a reason string
(`ACHR <id>: <why>`) — M5.6 zero-unexplained rule:
`failures == failureReasons.count`, gated. Counts + reasons land in
`CellLoadSummary` (summary-line actor clause) + `CellBuildMetric`;
`bench --fly-path` gates both invariants and the actor-build p95 budget,
printing per-cell accounting ([CLI](/tools/cli.md)). Streaming lifecycle
detail: [cell streaming](/engine/cell-streaming.md).

## Verification

Real install via `openskycli actor`: WhiterunWorld (5,-3) radius 2 -> 31/31
ACHRs template+visual resolved (radius 4: 75/75); female Stormcloak guards
get full armor bundles through LVLI expansion with male-boot fallback; cow
resolves skin without FaceGen. Named residents live in interior home cells,
so `actor --npc <formid-or-edid>` resolves bases directly: Heimskr,
Belethor, Ysolda, Nazeem, AdrianneAvenicci, Ulfberth all resolve skeleton,
parts, slots + FaceGen paths matching files confirmed present in the BSAs.
M5.4 offscreen probe: Heimskr NPC_ `00013BAC`, ACHR `0001A682` at
`(249.9946, -69.73085, 68)`, XSCL 1. Deterministic models = monk boots, robes, hood,
visible male hands + 6-mesh FaceGen head. Production assembly rendered 10.8%
non-background at 800x800; visual check confirmed clothed body + complete head at one pose.
Synthetic fixtures: `openskyTests/ActorRecordTests.swift`,
`openskyTests/AppearanceRecordTests.swift`,
`openskyTests/ActorVisualResolutionTests.swift`, `openskyTests/ActorAssemblyTests.swift`.

## Milestone acceptance (5.6)

`make probe` 2026-07-20, full pass: actor-enabled fly bench 55 ACHRs discovered =
27 rendered + 27 disabled + 1 failed, exact accounting + per-cell report in all 35
touched cells, zero unexplained failures. The single failure was reason-tagged:
`ACHR 000DC8DE: no renderable geometry (invalidAsset, noCoreGeometry)` — sabre cat
(`LvlAnimalPlainsPredator` -> `SabreCat.nif`), whose `NiSkinPartition` carried a
global influence index our flattener wrongly remapped through the partition
palette. Resolved by issue #64 (see [nif](/formats/nif.md) skin blocks): re-verified
2026-07-23, the fly bench reports 55 = 28 rendered + 27 disabled + 0 failed and ACHR
`000DC8DE` renders (static — the creature idle-path tag for
`meshes\actors\sabrecat\character assets\skeleton.nif` is animation, not geometry).
Interior gate: ChillfurrowFarm reports 1 actors (1 drawn). Frame budget:
5,614 stream frames avg 3.15 ms / p95 5.79 ms @ 640x360; actor build p95 2190.79 ms
vs 3000 ms budget; footprint peak 702 / 1,024 MB cap. Generated render captures stay
local; accounting + frame metrics are the repository acceptance evidence.

Issue #56 follow-up, 2026-07-28: the serial actor phase was dominated by DDS
payload decompression from BSA archives, not resolver indexing or Metal upload.
System-decoding independent LZ4 blocks reduced the 35-cell Debug actor phase
from 577.33 ms average / 3093.60 ms p95 / 7218.41 ms maximum to
378.44 / 2224.46 / 4427.78 ms. Actor accounting remained exactly 55 discovered
= 28 rendered + 27 disabled + 0 failed, including 11 animated + 17
reason-tagged static fallbacks. The default p95 gate is 3000 ms again.
