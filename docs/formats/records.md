---
type: File Format
title: Record decoders
description: The decode rules every record follows, localized strings, and the small shared
  records - FLST, GLOB, DOBJ, MOVT, COLL, and ECZN.
tags: [format, esm, records, form-list, global, defaults, collision, encounter-zone]
---

# Record decoders

A record decoder reads one record type from the [ESM container](/formats/esm.md). This page has
the shared rules and the small records. Other record pages:

- [World records](/formats/world-records.md): `WRLD`, `CELL`, `REFR`, `STAT`, and placeable
  base objects.
- [Item records](/formats/item-records.md): carried items, weapons, ammunition, projectiles,
  and containers.
- [Quest records](/formats/quest-records.md): `QUST`.
- [Actor records](/formats/actors.md), [magic records](/formats/magic-records.md),
  [conditions](/formats/conditions.md), and the other pages under `formats/`.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format) pages,
one per record, and xEdit `dev-4.1.6` `Core/wbDefinitionsTES5.pas`.

## Decode rules

- Read the fields in a loop. Decode the known ones and skip the rest. An unknown field from a mod
  is never an error.
- Throw `ESMError.malformed` only when the record cannot be used at all: a wrong record type, a
  cut-off field, or a missing required field. The caller logs it and skips the record.
- An optional field with a bad size costs only that field.
- A stored count, such as `KSIZ` for keywords or `COCT` for container entries, never sizes a
  read. The real length is the field size divided by the entry size. A count that disagrees is
  recorded, but the data present is decoded.

## Localized strings (lstring)

A display text field depends on the plugin's TES4 localized flag (`0x80`):

- Localized: the field is a uint32 string ID in the [string tables](/formats/strings.md). The
  field decides the table: `FULL` uses `.strings`, `DESC` and book text use `.dlstrings`, and
  dialogue uses `.ilstrings`.
- Not localized: the field is an inline zero-terminated string. It is decoded with the
  [string decoding](/decisions/string-decoding.md) rules.

The tables are at `strings\<plugin name>_<language>.<ext>`. The language comes from
`[General] sLanguage` in the game INI files, then an optional OpenSky setting. The default is
`english`. A missing table gives no text and one logged error.

## FLST (form list)

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `LNAM` | FormID, repeats | One entry each |

Entries keep file order, because Papyrus can read a form list by index. A zero FormID is a real
empty slot, and is kept. A last `LNAM` of 1 to 3 bytes is dropped and counted.

An override replaces the whole list. Entries do not add up across plugins. Each `LNAM` resolves
against the plugin that supplied the winning list.

A list can contain other lists. The flattened view replaces each inner list with its entries, in
order. A loop is cut. A chain stops at depth 32. Vanilla lists nest at most 2 deep. Example:
`AtrFrgAtronachForgeRecipeList` contains `Skyrim.esm:03AD5E` only through an inner list.

## GLOB (global)

A named number that conditions, scripts, and records read. The runtime copy is on the
[runtime state](/engine/runtime-state.md) page.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FNAM` | uint8 | Type: `s` (0x73) short, `l` (0x6C) long, `f` (0x66) float |
| `FLTV` | float32 | Value |

Record header flag `0x40` means constant. It is recorded, not enforced.

`FLTV` is a float32 whatever `FNAM` says. A short or long global is a float that holds a whole
number. UESP warns that a long global loses precision above 2^24. OpenSky keeps the same form:
one float and the declared type. Every write converts to the type. Whole-number types round half
away from zero. Nothing is clamped to 16 or 32 bits, because a mod can store a larger value.

A bad `FNAM` leaves the type as float, the xEdit default. A bad or missing `FLTV` leaves 0.
UESP lists `OBND` and `VMAD` as unused on `GLOB`, and both are skipped. Globals are found by
editor ID without regard to case, as scripts and the console do.

## DOBJ (default objects)

`DNAM` is an array of 8-byte entries: a 4-byte use tag, then a FormID. Example: tag `GOLD` names
the gold item. A zero tag is an empty slot. A nonzero tag with a zero FormID is a real "none",
so a later plugin can clear a default. A tail of 1 to 7 bytes is ignored and counted. Real
records have no `EDID`. xEdit uses the name `DefaultObjectManager`, and so does OpenSky.

The tag names come from xEdit's table of 372 tags. An unknown tag from a mod is kept.

Overrides work per entry, not per record. All the master files share one `DOBJ`
(`Skyrim.esm:000031`). The later copies contain empty slots and only the entries they add or
change. Replacing the whole record would lose `Skyrim.esm`'s defaults. So OpenSky walks every
copy in load order and replaces only a repeated tag.

## MOVT (movement type)

How fast an actor moves with one gait. The player's gaits feed [walk mode](/engine/walk-mode.md).

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `MNAM` | zstring | Name used by the Creation Kit and behavior graphs |
| `SPED` | float32 x 11 | Speeds |
| `INAM` | float32 x 3 | Direction change limits. Not read |

`SPED` order, from xEdit: left walk, left run, right walk, right run, forward walk, forward run,
back walk, back run, turn in place walk, turn in place run, turn while moving run. The first
eight are units per second. The last three are radians per second.

The data confirms the order: `NPC_Sprinting_MT` is 0 in every side slot and 500 in the forward
pair. That only fits if forward is at float 4 and 5. Other vanilla forward speeds (walk, run):
`NPC_Default_MT` 80.1 and 370, `NPC_Sneaking_MT` 47.2 and 222.

A `SPED` shorter than 11 floats is dropped whole. Zero padding would read as "cannot move".

## COLL (collision layer)

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `DESC` | lstring | Description |
| `BNAM` | uint32 | Layer index |
| `FNAM` | RGBA bytes | Editor debug color |
| `GNAM` | uint32 | Flags: `0x01` trigger volume, `0x02` sensor, `0x04` navmesh obstacle |
| `MNAM` | zstring | Layer name |
| `INTV` | uint32 | Interactables count |
| `CNAM` | FormID list | Layers this one collides with |

A `CNAM` whose size is not a multiple of 4 gives no links and is counted. A `PROJ` can name a
layer (see [item records](/formats/item-records.md)). Physics filtering does not use this record
yet.

## ECZN (encounter zone)

| Field | Offset | Type | Meaning |
| --- | --- | --- | --- |
| `EDID` | - | zstring | Editor ID |
| `DATA` | 0x00 | FormID | Owner: `NPC_` or `FACT` |
| `DATA` | 0x04 | FormID | Location (`LCTN`) |
| `DATA` | 0x08 | int8 | Required faction rank. -1 when not used |
| `DATA` | 0x09 | int8 | Minimum level |
| `DATA` | 0x0A | uint8 | Flags: `0x01` never resets, `0x02` match player below minimum, `0x04` no combat boundary |
| `DATA` | 0x0B | int8 | Maximum level |

xEdit uses an 8-byte `DATA` before form version 34, and UESP reports two such records in the
game. So each member is read only if the field reaches its offset. An 8-byte field keeps both
links. `CELL` and `WRLD` link to a zone through `XEZN`. Level scaling, respawn, and cleared state
are not done yet.
