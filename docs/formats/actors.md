---
type: File Format
title: Actor records (ACHR, NPC_, LVLN) + template resolution
description: Placed-actor and actor-base record layouts plus the TPLT template chain policy.
tags: [format, plugin, actors, achr, npc, leveled, template]
timestamp: 2026-07-19T00:00:00Z
---

# Actor records, Skyrim SE

Milestone 5.1 subset: enough decode to place actors and resolve who they look
like — no stats, AI, factions, spells, or inventory items yet. Container
framing: [ESM/ESP plugin container](/formats/esm.md); decode policy (skip
unknown fields, `ESMError.malformed` only on structurally unusable input):
[record decoders](/formats/records.md).

Reference: UESP "Skyrim Mod:Mod File Format" subpages `/ACHR`, `/NPC_`,
`/LVLN`, `/LVLI` (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>);
xEdit dev-4.1.6 `wbDefinitionsTES5.pas` (template flag masks) +
`wbDefinitionsCommon.pas` (`wbLeveledListEntry`); CK wiki "Template Data"
(flag -> tab coverage). Impl: `opensky/Formats/ESM/Records/` +
`opensky/World/ActorResolution.swift`.

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

## LVLN -> LeveledActor

| field | type   | decoded                                    |
| ----- | ------ | ------------------------------------------ |
| EDID  | zstring| `editorID`                                 |
| LVLD  | uint8  | `chanceNone` (always 0 for LVLN per UESP)  |
| LVLF  | uint8  | `flags`: 0x01 all levels, 0x02 each        |
| LVLO  | struct | `entries[]`, one per subrecord             |

LVLO: UESP documents 12 bytes (uint32 level, formID reference — NPC_ or
nested LVLN, uint32 count). xEdit's `wbLeveledListEntry` reads uint16 level +
2 pad + formID and accepts an 8-byte form with count defaulting 1 —
byte-identical for sane values; OpenSky decodes the lenient shape. COED owner
data (own subrecord after an LVLO) + OBND/LLCT/MODL are skipped.

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
convention); cross-plugin identity waits for load-order support.

Verified against the real install via `openskycli actor` (Tamriel (6,-2)
radius 3: 107/107 ACHRs resolved; WhiterunWorld (5,-3) radius 2: 31/31,
guard chains route through LVLN lists as expected). Synthetic fixtures:
`openskyTests/ActorRecordTests.swift`.
