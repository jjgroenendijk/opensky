---
type: File Format
title: Actor records (ACHR, NPC_, LVLN/LVLI, RACE, CLAS)
description: Layouts of the actor records, the template flags, and the FaceGen asset paths.
tags: [format, plugin, actors, achr, npc, leveled, template, race, class, facegen]
---

# Actor records

These records place an actor, say what it looks like, and give its stats and AI settings.
[Actor resolution](/engine/actor-resolution.md) explains how OpenSky combines them into a
rendered actor. [Actor values](/engine/actor-values.md) explains how the stat fields become
health, magicka, and stamina. Armor, armature, and outfit records are on
[armor records](/formats/armor.md).

Sources:

- UESP "Skyrim Mod:Mod File Format" pages `/ACHR`, `/NPC_`, `/LVLN`, `/LVLI`, `/RACE`,
  and `/CLAS` (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>).
- xEdit dev-4.1.6 `wbDefinitionsTES5.pas` (template flag masks, `wbAIDT`) and
  `wbDefinitionsCommon.pas` (`wbLeveledListEntry`).
- Creation Kit wiki: "Template Data", "AI Data Tab"
  (<https://ck.uesp.net/wiki/AI_Data_Tab>), and "Race".

All integers and floats are little-endian.

## ACHR

A placed NPC. It has the same shape as REFR and lives in the same CELL child groups. An
ACHR that is persistent in a worldspace is stored under the worldspace persistent cell
([ESM groups](/formats/esm.md#worldspace-persistent-cell)).

| field | type | meaning |
| --- | --- | --- |
| `NAME` | FormID | base `NPC_`; required |
| `DATA` | float32[6] | position, then rotation in radians; required |
| `XSCL` | float32 | scale; absent means 1.0 |
| `VMAD` | struct | scripts; see [VMAD](/formats/vmad.md) |

Record-header flag `0x800` means "initially disabled": a script must enable the actor
before it appears. Header flag `0x200` means "starts dead". Not read: `XEZN`, patrol data,
`XRGD`/`XRGB`, `XLCM`, `XESP`, `XOWN`, `XLCN`/`XLRL`, and `XLKR` (4 or 8 bytes).

## NPC_

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `ACBS` | 24 bytes | flags, template flags, and stats; required |
| `CNAM` | FormID | class (`CLAS`) |
| `DNAM` | 52 bytes | skills and the editor's calculated health, magicka, and stamina |
| `TPLT` | FormID | template, an `NPC_` or an `LVLN` |
| `RNAM` | FormID | race; required |
| `VTCK` | FormID | voice type (`VTYP`) |
| `WNAM` | FormID | skin `ARMO`; absent means the race skin |
| `PNAM` | FormID | head part (`HDPT`); repeated |
| `DOFT` | FormID | default outfit (`OTFT`) |
| `PKID` | FormID | AI package; repeated, in order |
| `SNAM` | struct | faction membership; see [factions](/formats/factions.md) |
| `CRIF` | FormID | crime faction, the faction the actor reports crimes to |
| `AIDT` | 20 bytes | AI data |
| `VMAD` | struct | scripts |

`ACBS`:

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint32 | flags: `0x01` female, `0x10` auto-calc stats, `0x20` unique, `0x80` PC level multiplier |
| `0x04` | int16 | magicka offset |
| `0x06` | int16 | stamina offset |
| `0x08` | uint16 | level, or level multiplier x1000 when the PC flag is set |
| `0x0A` | uint16 | auto-calc minimum level |
| `0x0C` | uint16 | auto-calc maximum level |
| `0x0E` | uint16 | speed multiplier (actor value 30) |
| `0x10` | uint16 | disposition base |
| `0x12` | uint16 | template flags |
| `0x14` | int16 | health offset |
| `0x16` | uint16 | bleedout override |

`DNAM` holds 18 base skill bytes, 18 skill-modifier bytes, and three int16 values at
`0x24`, `0x26`, and `0x28`: health, magicka, and stamina. UESP calls them "calculated health
(if auto-calc stats is on, otherwise seems to be random)". So they are the editor's own
answer. OpenSky uses them only to check its derivation, never as input. They are signed: a
creature with a negative magicka offset stores a negative value here.

Template flags say which field groups come from the `TPLT` record: `0x0001` traits,
`0x0002` stats, `0x0004` factions, `0x0008` spell list, `0x0010` AI data, `0x0020` AI
packages, `0x0040` model and animation, `0x0080` base data, `0x0100` inventory, `0x0200`
script, `0x0400` default package list, `0x0800` attack data, `0x1000` keywords. UESP marks
`0x0040` "unused?"; xEdit names it and the Creation Kit does not, so do not rely on it.
[Actor resolution](/engine/actor-resolution.md) lists which fields each flag covers.

`AIDT` uses Creation Kit names. UESP and xEdit agree on every offset.

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint8 | aggression: 0 unaggressive, 1 aggressive, 2 very aggressive, 3 frenzied |
| `0x01` | uint8 | confidence: 0 cowardly to 4 foolhardy |
| `0x02` | uint8 | energy, how often the actor moves in a sandbox, 0 to 100 |
| `0x03` | uint8 | morality: 0 any crime to 3 no crime |
| `0x04` | uint8 | mood; the wiki calls it "Not used" |
| `0x05` | uint8 | assistance: 0 helps nobody, 1 helps allies, 2 helps friends and allies |
| `0x06` | uint8 | bit 0: uses aggro radius behavior |
| `0x07` | uint8 | xEdit "Unused"; UESP sees junk |
| `0x08` | uint32 | warn distance |
| `0x0C` | uint32 | warn-or-attack distance |
| `0x10` | uint32 | attack distance |

An `AIDT` shorter than 8 bytes gives no AI data. One that ends before `0x08` has no
distances. An actor without `AIDT` counts as unaggressive.

## LVLN and LVLI

Leveled NPC and leveled item lists share one layout. LVSP (leveled spell) uses it too; see
[shouts and equip slots](/formats/shouts-equip-slots.md).

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `LVLD` | uint8 | chance none; UESP says always 0 on LVLN |
| `LVLF` | uint8 | flags: `0x01` all levels, `0x02` each count, `0x04` use all |
| `LVLO` | struct | one entry; repeated |

With "use all" set, every entry applies together. For example, `ArmorStormcloakSet` gives
boots, cuirass, gauntlets, and a helmet list. Without it, the game picks one entry.

UESP gives `LVLO` as 12 bytes: uint32 level, FormID, uint32 count. xEdit's
`wbLeveledListEntry` reads uint16 level, 2 padding bytes, FormID, and also accepts an 8-byte
form where the count is 1. Both read the same bytes for normal values. OpenSky accepts both.
A `COED` owner subrecord may follow an `LVLO`. `OBND`, `LLCT`, and `MODL` are not read.

## RACE

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `WNAM` | FormID | default skin `ARMO` for an NPC_ without `WNAM` |
| `BOD2`/`BODT` | struct | body template; see [armor records](/formats/armor.md) |
| `DATA` | 128 or 164 bytes | form version 40 or 43 |
| `MNAM`/`FNAM` | 0 bytes | marker: the next block is male or female |
| `ANAM` | zstring | skeleton path for the current gender |
| `NAM0` | 0 bytes | opens the head-data blocks |
| `HEAD` | FormID | default head part (`HDPT`); repeated |

`DATA`, the parts OpenSky reads:

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | 7 x (uint8, uint8) + uint16 | skill bonuses: actor value, then bonus |
| `0x10` | float32 x 4 | male and female height and weight (not read) |
| `0x20` | uint32 | flags: `0x1` playable, `0x2` FaceGen head |
| `0x24` | float32 x 3 | starting health, magicka, stamina |
| `0x30` | float32 x 2 | base carry weight, base mass |
| `0x54` | float32 x 3 | health, magicka, stamina regen |
| `0x60` | float32 | unarmed damage |

A skill pair with a bonus of zero is an empty slot. `NordRace` gives Two-Handed +10 and
One-Handed, Block, Smithing, Light Armor, and Speech +5, which matches UESP. Every playable
vanilla race has 300 carry weight, mass 1, unarmed damage 4, starting values 50/50/50, and
regen 0.7/3/5 percent of the maximum per second. The Creation Kit says: "Health Regen: The
percentage of total Health that is regenerated each second".

Skeleton blocks come in this order (seen on `NordRace`): `MNAM`, male `ANAM` + `MODT`,
`FNAM`, female `ANAM` + `MODT`. Later `MNAM`/`FNAM` markers open other blocks, but those
carry `MODL`, not `ANAM`. So each `ANAM` pairs with the marker just before it.

For head data, `NAM0` opens a block, `MNAM` or `FNAM` picks the gender, and each `HEAD`
names a default head part. An `HDPT` pairs each `NAM0` kind with the next `NAM1` path: 0 is
the race morph, 1 is the expression TRI, 2 is the chargen morph. The `HDPT` `EDID` is the
name of the baked `BSDynamicTriShape`. See [TRI](/formats/tri.md).

## CLAS

`DATA` is 36 bytes:

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint32 | unknown, "possibly flags" |
| `0x04` | uint8 x 2 | trainer skill and level |
| `0x06` | uint8 x 18 | skill weights, for actor values 6 to 23 |
| `0x18` | float32 | bleedout default |
| `0x1C` | uint32 | voice points |
| `0x20` | uint8 x 3 | health, magicka, stamina weights |
| `0x23` | uint8 | flags; UESP: "0x1 seems to indicate guard" |

## FaceGen paths

Each NPC's baked head has two files. The key is the NPC_ that supplies the traits:

```text
meshes\actors\character\facegendata\facegeom\<plugin>\<id8>.nif
textures\actors\character\facegendata\facetint\<plugin>\<id8>.dds
```

`<plugin>` is the lowercased file name of the defining plugin (`skyrim.esm`). `<id8>` is the
FormID as 8 hex digits with the load-order byte set to `00`. The files exist only when the
race has the FaceGen head flag `0x2`. Playable races set it; creature races (cow, dog, bear)
do not. An NPC without head parts (Nazeem has no `PNAM`) still has files.
