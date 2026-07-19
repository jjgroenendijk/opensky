---
type: File Format
title: Actor records (ACHR, NPC_, LVLN/LVLI, RACE, ARMO, ARMA, OTFT) + resolution
description: Actor record layouts, TPLT template chains, and visual appearance resolution incl. FaceGen paths.
tags: [format, plugin, actors, achr, npc, leveled, template, race, armor, outfit, facegen]
timestamp: 2026-07-19T00:00:00Z
---

# Actor records, Skyrim SE

Milestones 5.1 + 5.2 subset: enough decode to place actors, resolve who they
look like, and turn that into renderable inputs (skeleton, body-part model
paths, FaceGen paths) — no stats, AI, factions, spells, or carried inventory
yet. Container framing: [ESM/ESP plugin container](/formats/esm.md); decode
policy (skip unknown fields, `ESMError.malformed` only on structurally
unusable input): [record decoders](/formats/records.md).

Reference: UESP "Skyrim Mod:Mod File Format" subpages `/ACHR`, `/NPC_`,
`/LVLN`, `/LVLI`, `/RACE`, `/ARMO`, `/ARMA`, `/OTFT`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>);
xEdit dev-4.1.6 `wbDefinitionsTES5.pas` (template flag masks) +
`wbDefinitionsCommon.pas` (`wbLeveledListEntry`); CK wiki "Template Data"
(flag -> tab coverage); NifTools `nif.xml` `BSDismemberBodyPartType`
(biped slot numbering). Impl: `opensky/Formats/ESM/Records/` +
`opensky/World/ActorResolution.swift` +
`opensky/World/ActorVisualResolution.swift`.

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

Skipped for now: VMAD script, XEZN encounter zone, patrol data, XRGD/XRGB
ragdoll, XLCM level modifier, XESP enable parent, XOWN owner, XLCN/XLRL
location, XLKR link (4- or 8-byte). Header flags of note (undecoded, listed
for 5.5): 0x200 starts dead, 0x800 initially disabled.

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

How a piece displays on a body: per-gender models + applicable races.
MOD4/MOD5 first-person models, texture swaps (NAM0-3), DNAM priorities, and
MODT hashes are skipped.

| field     | type    | decoded                                       |
| --------- | ------- | --------------------------------------------- |
| EDID      | zstring | `editorID`                                    |
| BOD2/BODT | struct  | `bodyTemplate` — slots the armature covers    |
| RNAM      | formID  | `primaryRace`                                 |
| MODL      | formID  | `additionalRaces[]` (base + vampire variants) |
| MOD2      | zstring | `maleModelPath` (3rd person)                  |
| MOD3      | zstring | `femaleModelPath` (3rd person)                |

Probed: ARMA records at form version 40 emit 12-byte BODT while ARMO/RACE at
44 emit 8-byte BOD2 — the shared decoder accepts both.

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

Failure policy (milestone gate): broken chains throw typed
`ActorVisualError`s — dangling race/skin/outfit/item FormIDs, empty or
cyclic leveled lists. Never a silent naked fallback. Missing optional parts
degrade to reason-tagged `AppearanceSkip`s (dangling armature, no compatible
armature, no model, masked by outfit, duplicate armature, missing skeleton
or body slots) so accounting stays exact.

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

## Verification

Real install via `openskycli actor`: WhiterunWorld (5,-3) radius 2 -> 31/31
ACHRs template+visual resolved (radius 4: 75/75); female Stormcloak guards
get full armor bundles through LVLI expansion with male-boot fallback; cow
resolves skin without FaceGen. Named residents live in interior home cells,
so `actor --npc <formid-or-edid>` resolves bases directly: Heimskr,
Belethor, Ysolda, Nazeem, AdrianneAvenicci, Ulfberth all resolve skeleton,
parts, slots + FaceGen paths matching files confirmed present in the BSAs.
Synthetic fixtures: `openskyTests/ActorRecordTests.swift`,
`openskyTests/AppearanceRecordTests.swift`,
`openskyTests/ActorVisualResolutionTests.swift`.
