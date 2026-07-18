---
type: File Format
title: Record decoders (WRLD, CELL, REFR, STAT, ModelBase)
description: Field layouts of decoded plugin records and OpenSky's engine types.
tags: [format, plugin, records, worldspace, cell]
timestamp: 2026-07-18T00:00:00Z
---

# Record decoders, Skyrim SE

Record decoders over the [ESM container](/formats/esm.md): worldspace listing, cell
grids, placed references, static + placeable model base objects — the data needed to
build an exterior cell scene (milestone 2, widened in 3.2). TES4 decode lives in
[FormID + TES4 header](/formats/formid.md).

Reference: UESP "Skyrim Mod:Mod File Format" per-record pages
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>, subpages `/WRLD`,
`/CELL`, `/REFR`, `/STAT`, `/MSTT`, `/TREE`, `/FURN`, `/ACTI`, `/CONT`, `/DOOR`).
Water-specific
fields + WATR layout: [exterior water records](/formats/water.md). Impl:
`opensky/Formats/ESM/Records/`.

Decode policy: loop over fields, pick known types, skip the rest — unknown
modder fields are never an error. Decoders throw `ESMError.malformed` only on
structurally unusable input (truncated field, missing required field); callers
log + skip per mod-quirk rule. Each decoder guards the record type.

## lstring / LString

Display-text fields ("lstring" in UESP terms) depend on the owning plugin's
TES4 localized flag (0x80):

* localized -> field holds uint32 string ID into per-language
  [string tables](/formats/strings.md); which table depends on the field
  (FULL -> `.strings`, DESC/book -> `.dlstrings`, dialogue -> `.ilstrings`).
* not localized -> inline zstring, lenient decode (`GameText`: UTF-8 when
  valid, else windows-1252).

`LString` (enum: `.inline` / `.tableID`) carries this; `LocalizedStrings`
(`GameData/LocalizedStrings.swift`) resolves IDs through the VFS at
`strings\<plugin stem>_<language>.<ext>`, lazy per kind, missing table ->
nil + one os_log error. Language defaults to "english" until a setting
exists (open question in [roadmap](/todo.md)).

## WRLD -> Worldspace

| field | type     | decoded                                |
| ----- | -------- | -------------------------------------- |
| EDID  | zstring  | `editorID` ("Tamriel")                 |
| FULL  | lstring  | `name` ("Skyrim")                      |
| WNAM  | formID   | `parent` worldspace (inheritance link) |
| PNAM  | uint16   | `parentFlags` inheritance categories   |
| DATA  | uint8    | `flags`                                |
| DNAM  | float[2] | default land + water heights           |
| NAM2  | formID   | default WATR record                    |

DATA flag bits: 0x01 small world, 0x02 no fast travel, 0x08 no LOD water,
0x10 no landscape, 0x20 no sky, 0x40 fixed dimensions, 0x80 no grass.

Skipped for now: RNAM large refs, MNAM map size, NAM0/NAM9 bounds, climate /
LOD fields. WRLD record is followed by a world-children GRUP holding
exterior cell blocks (traversal in [ESM container](/formats/esm.md)).

## CELL -> Cell

| field | type                                | decoded                    |
| ----- | ----------------------------------- | -------------------------- |
| EDID  | zstring                             | `editorID`                 |
| FULL  | lstring                             | `name` (interior cells)    |
| DATA  | uint16                              | `flags`                    |
| XCLC  | int32 x, int32 y, uint32 quad flags | `grid` (exterior cells)    |
| XCLW  | float32 bits                        | `waterHeight` override     |
| XCWT  | formID                              | `waterType` WATR override  |

DATA flag bits: 0x01 interior, 0x02 has water, 0x08 no LOD water, 0x80 show
sky, more in UESP. Some records store one byte only (UESP note) — decoder
accepts both sizes.

XCLC: exterior grid slot, one cell = 4096 game units. The quad-flags uint32
is absent in some form-version-43 records (8-byte field -> flags 0); its
high bits carry CK noise, kept verbatim.

Lighting (XCLL) + remaining formID links stay skipped. XCLW sentinel policy, WRLD
inheritance, and WATR colors: [exterior water records](/formats/water.md).

Interior CELLs live below CELL top group -> block group type 2 -> sub-block group type 3.
xEdit `UpdateInteriorCellGroup` derives labels from low-24-bit object ID written in
decimal: block = ones digit, sub-block = tens digit. Example object ID 80074 -> block 4,
sub-block 7. OpenSky tries those groups first, then all legal type-2/type-3 siblings:
labels are an optimization hint, never identity. CELL FormID + DATA 0x01 establish
identity/interior status. Refs: UESP CELL page + xEdit `wbImplementation.pas`
(`dev-4.1.6`).

## REFR -> PlacedReference

| field | type     | decoded                                    |
| ----- | -------- | ------------------------------------------ |
| NAME  | formID   | `base` — the base object placed (required) |
| DATA  | float[6] | `placement` (required)                     |
| XSCL  | float    | `scale`, defaults 1.0 when absent          |
| XTEL  | 32 bytes | optional teleport destination              |

DATA: x/y/z position in game units, then x/y/z rotation in radians. Missing
NAME or DATA throws — a reference without them cannot be placed. XTEL is exact-size:
destination door REFR FormID (uint32), destination position float3, rotation float3 in
radians, flags uint32. Flag 0x01 = no alarm. Any other size throws malformed instead of
silently shifting fields. Ownership + remaining activation fields stay skipped. Refs:
UESP REFR page; xEdit `wbDefinitionsTES5.pas` XTEL `wbStruct`.

## STAT -> StaticObject

| field | type    | decoded                           |
| ----- | ------- | --------------------------------- |
| EDID  | zstring | `editorID`                        |
| MODL  | zstring | `modelPath` (nil = marker static) |

MODL is a mesh path relative to `Data/` (`meshes\...`), resolved through the
[VFS](/formats/vfs.md). MODT hashes, DNAM (max angle + material), MNAM LOD
models skipped until the NIF/LOD work needs them.

## MSTT/TREE/FURN/ACTI/CONT/DOOR -> ModelBase

One shared `ModelBase` (`opensky/Formats/ESM/Records/ModelBase.swift`) decodes six
placeable base types beyond STAT. All carry EDID + MODL in the same position STAT does;
scene build needs model path only. M3.6 adds DOOR draw coverage; teleport data belongs to
placed REFR XTEL, not DOOR.

| field | type    | decoded                      |
| ----- | ------- | ---------------------------- |
| EDID  | zstring | `editorID`                   |
| MODL  | zstring | `modelPath` (nil = no model) |

Per-type reference, all UESP "Skyrim Mod:Mod File Format":

* MSTT (moveable static) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MSTT>
* TREE (tree/plant) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TREE>
* FURN (furniture) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN>
* ACTI (activator) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ACTI>
* CONT (container) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT>
* DOOR (door) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOOR>

Type-specific fields skipped: FURN furniture-marker/animation fields, CONT
inventory (CNTO) + open/close sound, ACTI interaction (VNAM/activate text, sound), TREE
billboard/leaf-curve fields (CVPA/BSNM/...), DOOR sounds/flags. `ModelBase.recordType`
retains source record type so callers can distinguish them without redecoding.

## Verification

Unit tests: `openskyTests/RecordDecoderTests.swift`,
`LocalizedStringsTests.swift` (synthetic fixtures). Runtime probe 2026-07-09
against vanilla Skyrim.esm (milestone 1 acceptance): 37 worldspaces listed
with EDID + FULL resolved via string tables from `Skyrim - Interface.bsa`
(e.g. Tamriel "Skyrim", 11 187 cells); 16 978 exterior-group cells decoded,
all carrying XCLC grids; 9 720 STAT records (9 712 with MODL); cell
WhiterunExterior01 (0000961B, grid 4,-3) dumped 100 STAT refs with FormIDs,
positions, rotations, scales, model paths (52 non-STAT refs skipped).
Positions all lie inside the cell's 4096-unit grid extent.
