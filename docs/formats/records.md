---
type: File Format
title: Record decoders (decode rules, lstring, FLST, GLOB, DOBJ, ECZN, COLL, MOVT)
description: The shared rules every record decoder follows, localized strings, and the
  layouts of small reference records.
tags: [format, plugin, records, encounter-zone, collision, defaults, form-list, global]
---

# Record decoders

A plugin ([ESM](/formats/esm.md)) is a list of records. This page gives the rules that every
record decoder follows, and the layouts of several small records. Other records have their
own pages:
[world records](/formats/world-records.md), [placed references](/formats/placed-references.md),
[item records](/formats/item-records.md), [projectiles](/formats/projectiles.md),
[quest records](/formats/quest-records.md), [actor records](/formats/actors.md),
[magic records](/formats/magic-records.md), and the other pages under `docs/formats/`.

The main sources are the UESP "Skyrim Mod:Mod File Format" pages, one per record
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), and xEdit `dev-4.1.6`
`Core/wbDefinitionsTES5.pas`.

## Decode rules

- A decoder reads every field the spec names. A field it does not read, such as one a
  mod adds, is never an error: it is counted in the decoder's `skipped` tally, so a
  real-data sweep can report it. A field whose decode fails is counted as malformed and
  reads as absent.
- A decoder throws only when a record cannot be used at all: the wrong record type, a
  missing required field, or a field too short for its required members. The caller logs
  the record and skips it.
- Count fields such as `KSIZ` (for `KWDA`) and `COCT` (for `CNTO`) never size a read. The
  real count is the field size divided by the entry size. A count that disagrees is
  recorded.
- When a later plugin overrides a record, the whole record is replaced. DOBJ is the one
  exception (below).
- A FormID in a record is relative to the plugin that holds the record
  ([FormID](/formats/formid.md)).

## lstring

A display-text field ("lstring" on UESP) depends on the localized flag (`0x80`) in the
plugin's TES4 header:

- Localized: the field is a uint32 string ID into a per-language
  [string table](/formats/strings.md). The field picks the table: `FULL` uses `.strings`,
  long body text such as `DESC` and book text uses `.dlstrings`, and dialogue uses
  `.ilstrings`.
- Not localized: the field is an inline zstring. OpenSky decodes it as UTF-8, else
  windows-1252, else ISO 8859-1 ([string decoding](/decisions/string-decoding.md)).

A table's path is `strings\<plugin stem>_<language>.<ext>`. The language comes from
`[General] sLanguage` in the Skyrim INI files ([INI](/formats/ini.md)), then an optional
OpenSky setting. A missing or unknown value means `english`.

## FLST

Sources: UESP `/FLST` and xEdit `wbRecord(FLST, ...)`. Both give an `EDID` and zero or
more `LNAM` FormIDs; xEdit calls the array `FormIDs`.

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID; optional |
| `LNAM` | FormID | one entry; repeated |

The order matters, because Papyrus can read a form list by index. A zero FormID is a valid
empty slot and is kept. The active official load order has no empty slot, but a mod can
have one. A partial `LNAM` of 1 to 3 bytes is dropped.

A form list can contain other form lists. An override replaces the whole list. Each `LNAM`
resolves relative to the plugin that holds its list, also inside a nested list. OpenSky
stops on a loop and at depth 32.

On the active load order: 1,219 lists. The largest has 308 entries
(`BYOHRelationshipAdoptionPlayerGiftChildFemale`). The deepest nesting is 2
(`ccBGSSSE001_FishCatchDataListTemperateStreamClear`). For example,
`AtrFrgAtronachForgeRecipeList` does not list `Skyrim.esm:03AD5E` directly, but its nested
lists give 152 entries that include it.

## GLOB

A global is a named number that conditions, scripts, and records read. The runtime layer is
on [runtime state](/engine/runtime-state.md). Sources: UESP `/GLOB` and xEdit
`wbRecord(GLOB, 'Global', ...)`.

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FNAM` | uint8 | type: `s` (0x73) short, `l` (0x6C) long, `f` (0x66) float |
| `FLTV` | float32 | value |

Record-header flag `0x40` marks the global as constant.

`FLTV` is a float32 for every type. A short or long global is a float that holds a whole
number. So UESP warns that a long global loses precision above 2^24: values round to
multiples of 2, then 4, then 8. OpenSky stores the same float plus the type, and rounds
whole-number types half away from zero on every write. It does not clamp to 16 or 32 bits,
because a mod can store a larger value.

A bad `FNAM` leaves the xEdit default type, float. A missing `FLTV` gives 0. UESP lists
`OBND` and `VMAD` on GLOB as unused; vanilla has neither. Scripts and the console match
global names without regard to case.

## DOBJ

Sources: UESP `/DOBJ` and xEdit `wbDOBJObjectsTES5` and `wbRecord(DOBJ, ...)`, lines
6560-6976.

`DNAM` is an array of 8-byte entries: a 4-byte use tag, then a FormID. A zero tag is an
empty slot. A nonzero tag with a null FormID is a real entry that clears the default, so a
later plugin can remove one. A tail of 1 to 7 bytes is ignored. Real records have no
`EDID`; xEdit uses the name `DefaultObjectManager`.

xEdit's table has 372 tag names, for example `GOLD` for Gold. A tag from a mod that is not
in the table is kept.

Overrides work per entry, not per record. All masters share one record,
`Skyrim.esm:000031`. Later `DNAM` arrays hold zero padding plus only the entries they add
or change. Replacing the whole record would lose the `Skyrim.esm` defaults. So OpenSky
walks every version in load order, skips empty slots, and replaces only a repeated tag.

| plugin | DNAM bytes / slots | tags used |
| --- | --- | --- |
| Skyrim.esm | 2424 / 303 | 303 |
| Update.esm | 2928 / 366 | 12 |
| Dawnguard.esm | 2592 / 324 | 17 |
| HearthFires.esm | 2768 / 346 | 12 |
| Dragonborn.esm | 2768 / 346 | 27 |
| ccQDRSSE001-SurvivalMode.esl | 2928 / 366 | 7 |

Together they use 369 different tags. The three xEdit tags not used are `GCK8`, `GCK9`, and
`MHFL`.

## ECZN

Sources: UESP `/ECZN` and xEdit `wbRecord(ECZN, ...)`, lines 6286-6306.

| field | offset | type | meaning |
| --- | --- | --- | --- |
| `EDID` | - | zstring | editor ID; optional |
| `DATA` | 0x00 | FormID | owner, an NPC_ or FACT |
| `DATA` | 0x04 | FormID | location (`LCTN`) |
| `DATA` | 0x08 | int8 | required faction rank, -1 when not used |
| `DATA` | 0x09 | int8 | minimum level |
| `DATA` | 0x0A | uint8 | flags: `0x01` never resets, `0x02` match player below minimum level, `0x04` disable combat boundary |
| `DATA` | 0x0B | int8 | maximum level |

Before form version 34, xEdit uses an older 8-byte `DATA`, and UESP reports two such
records in the shipped files. So OpenSky reads each member only when the field is long
enough for it. CELL and WRLD link to an encounter zone with `XEZN`.

The active load order has 358 ECZN records, 356 unique. For example, `BleakFallsBarrowZone`
is `Skyrim.esm:038AB1`.

## COLL

Sources: UESP `/COLL` and xEdit `wbRecord(COLL, ...)`, lines 7614-7637.

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID; optional |
| `DESC` | lstring | description for the editor |
| `BNAM` | uint32 | collision layer index |
| `FNAM` | RGBA bytes | debug color for the editor |
| `GNAM` | uint32 | flags: `0x01` trigger volume, `0x02` sensor, `0x04` navmesh obstacle |
| `MNAM` | zstring | layer name |
| `INTV` | uint32 | number of interactable layers |
| `CNAM` | FormID array | the COLL layers this one collides with |

A `CNAM` whose size is not a multiple of 4 is malformed. The active load order has 55
layers. All have 4-byte `DESC`, `BNAM`, `FNAM`, `GNAM`, and `INTV`. All but one have `CNAM`,
with 1 to 41 links. PROJ `DATA` offset 0x58 can link to a COLL
([projectiles](/formats/projectiles.md)).

## MOVT

A movement type says how fast an actor moves in each direction. The player's gaits feed
[walk mode](/engine/walk-mode.md). Sources: UESP `/MOVT` and xEdit `wbRecord(MOVT, ...)`.

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `MNAM` | zstring | name used by the Creation Kit and the behavior graph |
| `SPED` | 11 x float32 | speeds |
| `INAM` | 3 x float32 | direction-change thresholds (not read) |

`SPED` has no count. xEdit gives the order: left walk, left run, right walk, right run,
forward walk, forward run, back walk, back run, rotate in place walk, rotate in place run,
rotate while moving run. The first eight are units per second, the last three radians per
second. The data agrees: `NPC_Sprinting_MT` is 0 in every side slot and 500 in the forward
pair, which fits only if forward is at float index 4 and 5. A shorter `SPED` is not used,
because zeros would mean "this actor cannot move".

`Skyrim.esm`, forward walk and run in units per second:

| editor ID | MNAM | forward walk | forward run |
| --- | --- | --- | --- |
| `NPC_Default_MT` | `NPCDefault` | 80.1 | 370.0 |
| `NPC_Sneaking_MT` | `NPCSneaking` | 47.2 | 222.0 |
| `NPC_Sprinting_MT` | `NPCSprinting` | 0.0 | 500.0 |
| `NPC_Swimming_MT` | `NPCSwimming` | 80.1 | 370.0 |

## Shared field groups

Source: xEdit `dev-4.1.6` (commit `9fb0168`). Several groups repeat across record types. Each group
member belongs to the opener just before it, so these groups are read in file order.

| Group | Fields | Used by |
| --- | --- | --- |
| Model | `MODL` path, then `MODT` texture hashes and `MODS` alternate textures | Most base records; other slots use `MOD2`/`MO2T`/`MO2S` and so on |
| Destruction | `DEST` header (int32 health, uint8 stage count, uint8 VATS targetable, 2 bytes), then per stage `DSTD` (20 bytes), `DMDL`/`DMDT`/`DMDS` model, `DSTF` end marker | `NPC_` and many base objects |
| Attack | `ATKD` (44 bytes: damage multiplier, chance, spell, flags, attack angle, strike angle, stagger, attack type, knockdown, recovery time, stamina multiplier), then `ATKE` event name | `RACE`, `NPC_` |
| Inventory | `COCT` count, `CNTO` (FormID, int32 count), optional `COED` (owner, uint32 rank or global, float health) | `CONT`, `NPC_` |

`MODT` and `MODS` belong to a model only when they follow its path directly. `MODS` is a
uint32 count, then per entry a uint32-length shape name, a `TXST` FormID, and an int32
shape index. `MODT` changes layout with the form version, so it stays raw.

A placed `STAT`, or another base with a model, draws each `MODS` entry: the shape with that
name takes the diffuse and normal map of the `TXST`. OpenSky matches shapes by name, without
case, and ignores the shape index. A slot the `TXST` leaves empty keeps the shape's own
texture. Example: `MountainCliffSlopeFieldGrass01` draws `MountainCliffSlope.nif` with the
field-grass textures instead of the mesh's slab and rock textures.

## Coverage

Every record type in the five masters and the Creation Club plugins has a decoder: 120
types, `TES4` included. The decoder registry maps each type to its decoder. The
real-data coverage sweep walks every group of every plugin, decodes every live record
through the registry, and fails on a type with no decoder or a decode that throws. It
also fails on a decoder that keeps no skip tally, and it pins the number of fields no
decoder reads: 4,893 over the whole install. All of them sit in three types: `INFO`
(`SCHR`, `QNAM`, `NEXT`, which older Creation Kit versions left), `QUST` (`QNAM`, `SCHR`,
`SCTX`), and `MGEF` (`VMAD`). Each other type reads every field its install records
carry. A field xEdit names but does not explain, such as `TES4 INTV` or `PACK PFOR`, is
kept as raw bytes. The CLI `record` command and the app's record inspector print the
decoded fields of any record, with links shown as editor IDs.

A second sweep, the field census, checks that each decoded field is set by at least one
record of the install. A field that no record sets would point at a decoder that never
reaches its bytes. 45 fields are never set, and each was checked against the raw bytes:
the field is absent, empty, or zero on every record. Examples are `WRLD MNAM` usable
dimensions, which are 0 on all 11 worldspaces, and the explodable and severable parts of
`BPTD BPND`, which no vanilla body part uses.
