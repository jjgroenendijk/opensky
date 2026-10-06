---
type: File Format
title: Skyrim Save (.ess)
description: The container of a Skyrim SE save, its ref ids, and its global data tables, as OpenSky reads them for a read-only import.
tags: [format, save, ess, lz4]
---

# Skyrim save (`.ess`)

A `.ess` file is a save the game wrote. OpenSky reads it, never writes it, and imports what
it can into its own save format ([ESS import](/engine/ess-import.md)). A save holds the
user's game data, so no save, part of a save, or save screenshot is ever committed. Tests
build saves in code.

References: UESP
[Save File Format](https://en.uesp.net/wiki/Skyrim_Mod:Save_File_Format) and
[Save File Format/Global Data](https://en.uesp.net/wiki/Skyrim_Mod:Save_File_Format/Global_Data).
All integers are little-endian unless a section says otherwise.

The change forms have their own page: [ESS change forms](/formats/ess-change-forms.md).
The Papyrus table has its own page: [ESS Papyrus](/formats/ess-papyrus.md).

## Basic types

| Name | Layout |
| --- | --- |
| `wstring` | `uint16` length, then that many bytes. Decoded by the [string decoding](/decisions/string-decoding.md) policy |
| `vsval` | Variable size. The low two bits of the first byte give the width: 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes. The value is the whole little-endian number shifted right by 2. Width bits 3 are an error |
| `refID` | 3 bytes, big-endian. The top 2 bits are the kind, the low 22 bits the value |
| vector | 3 `float32`: x, y, z |

## Ref ids

| Kind | Meaning of the value |
| --- | --- |
| 0 | Index into the form id array, plus one. Value 0 is the null form |
| 1 | An object id in `Skyrim.esm` |
| 2 | A form the game created at run time, such as an enchanted item |
| 3 | Unknown. OpenSky counts it and maps nothing |

The form id array holds runtime form ids. The top byte is the plugin index in the save's
plugin list. `0xFE` marks a light plugin: then the next 12 bits are the light plugin index
and the low 12 bits the object id. `0xFF` marks a created form.

## File layout

| Part | Layout |
| --- | --- |
| Magic | `TESV_SAVEGAME`, 13 bytes |
| Header size | `uint32` |
| Header | The table below |
| Screenshot | width × height pixels. RGB before header version 12, RGBA from version 12 |
| Lengths | Only for version 12 with compression: `uint32` uncompressed length, `uint32` compressed length |
| Body | The rest. Compressed when the header says so |

### Header

| Field | Type | Notes |
| --- | --- | --- |
| version | `uint32` | 7, 8, 9 Legendary Edition; 12 Special Edition |
| saveNumber | `uint32` | |
| playerName | `wstring` | |
| playerLevel | `uint32` | |
| playerLocation | `wstring` | The display name, not an editor ID |
| gameDate | `wstring` | As the load menu shows it |
| playerRaceEditorID | `wstring` | |
| playerSex | `uint16` | 0 male, 1 female |
| playerCurExp | `float32` | |
| playerLvlUpExp | `float32` | |
| filetime | `uint64` | Windows `FILETIME`, 100 ns since 1601 |
| shotWidth | `uint32` | |
| shotHeight | `uint32` | |
| compressionType | `uint16` | Version 12 only. 0 none, 1 zlib, 2 LZ4 |

The LZ4 body is one raw LZ4 block, not an LZ4 frame. OpenSky reads it with the Compression
framework's raw-block mode. A body over 1 GiB is refused before decompression.

The load list reads only the header and the screenshot, so listing a folder never
decompresses a body.

## Body

| Field | Type | Notes |
| --- | --- | --- |
| formVersion | `uint8` | 74 is SE 1.5.97. 78 adds the light plugin list. OpenSky reads 57 to 79 |
| pluginInfoSize | `uint32` | |
| plugins | `uint8` count, then `wstring` names | The save's load order |
| lightPlugins | `uint16` count, then `wstring` names | Version 12 and form version 78 or later |
| file location table | 100 bytes | Below |
| global data table 1 | entries | Types 0 to 8 |
| global data table 2 | entries | Types 100 to 114 |
| change forms | entries | [ESS change forms](/formats/ess-change-forms.md) |
| global data table 3 | entries | Types 1000 to 1005 |
| formIDArray | `uint32` count, then `uint32` ids | |
| visitedWorldspaceArray | `uint32` count, then `uint32` ids | |
| unknown table 3 | | Not read |

### File location table

Six `uint32` offsets, four `uint32` counts, and fifteen unused `uint32` words.

| Word | Field |
| --- | --- |
| 0 | formIDArrayCountOffset |
| 1 | unknownTable3Offset |
| 2 | globalDataTable1Offset |
| 3 | globalDataTable2Offset |
| 4 | changeFormsOffset |
| 5 | globalDataTable3Offset |
| 6 | globalDataTable1Count |
| 7 | globalDataTable2Count |
| 8 | globalDataTable3Count |
| 9 | changeFormCount |

UESP gives the offsets as file offsets. In a compressed save the offsets count from a base
that UESP does not state. OpenSky does not guess it: global data table 1 starts right after
the location table, so the base is `globalDataTable1Offset` minus that position. Every
other offset is moved by the same base, then checked: each section must start at or after
the one before it and inside the body. A table that fails the check stops the read with a
typed error, never a crash. The file keeps both the derived base and the expected one
(the body's file offset) so a real-data run can show whether they agree.

`globalDataTable3Count` is one less than the entries present. UESP calls this a known bug.
OpenSky reads table 3 by position, up to the form id array, and ignores its count.

## Global data tables

Each entry is a `uint32` type, a `uint32` length, and that many bytes. OpenSky decodes the
types the import uses and keeps the others as bytes.

| Type | Name | What OpenSky reads |
| --- | --- | --- |
| 0 | Misc Stats | `uint32` count, then `wstring` name, `uint8` category, `int32` value |
| 1 | Player Location | `uint32` next object id, `refID` worldspace, `int32` cell x, `int32` cell y, `refID` worldspace or cell, vector position |
| 3 | Global Variables | `vsval` count, then `refID` global and `float32` value |
| 4 | Created Objects | Four lists in order: weapon enchantments, armor enchantments, potions, poisons. Each is a `vsval` count of entries: `refID` form, `uint32` times used, `vsval` count of effects. An effect is `refID` effect, `float32` magnitude, `uint32` duration, `uint32` area, `float32` price |
| 6 | Weather | The first six `refID`s (climate, weather, previous weather, two unnamed, region weather) and three `float32`s (hour, start, transition). The rest is undocumented |
| 1001 | Papyrus | [ESS Papyrus](/formats/ess-papyrus.md) |

The other types are listed by name in the inspector and kept undecoded.

## Confirmed on real data

Not yet. No Skyrim save exists on the development machine
([environment](/tools/environment.md)). The layouts above come from UESP and are checked
only against synthetic saves built from the same tables. `make test-real` with
`OPENSKY_SKYRIM_SAVES` set runs `ESSRealDataTests`, which decodes every save in the folder
and imports the newest. The first run on real saves must confirm:

- the offset base of an LZ4 save, derived against expected;
- that light plugin ids decode as `0xFE`, 12-bit index, 12-bit object id;
- that every save's Papyrus table reads with 4-byte ids.
