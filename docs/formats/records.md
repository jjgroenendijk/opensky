---
type: File Format
title: Record decoders (WRLD, CELL, REFR, STAT, ModelBase, GLOB)
description: Field layouts of decoded plugin records and OpenSky's engine types.
tags: [format, plugin, records, worldspace, cell, globals]
timestamp: 2026-07-31T00:00:00Z
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
exists (open question, GitHub issue #72).

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
| XCLL  | lighting struct                     | `lighting`                 |
| LTMP  | formID                              | `lightingTemplate` LGTM    |
| XCLR  | formID array                        | `regions` REGN overlap     |
| XCAS  | formID                              | `acousticSpace` ASPC (M9.2.2) |

DATA flag bits: 0x01 interior, 0x02 has water, 0x08 no LOD water, 0x80 show
sky, more in UESP. Some records store one byte only (UESP note) — decoder
accepts both sizes.

XCLC: exterior grid slot, one cell = 4096 game units. The quad-flags uint32
is absent in some form-version-43 records (8-byte field -> flags 0); its
high bits carry CK noise, kept verbatim.

Lighting layout + inheritance: [interior lighting records](/formats/lighting.md). XCLW
sentinel policy, WRLD inheritance, and WATR colors:
[exterior water records](/formats/water.md).

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
| XRDS  | float32  | optional point-light radius override       |
| XEMI  | formID   | optional LIGH/REGN emittance               |
| XLKR  | struct   | `linkedReferences`, repeating (see below)  |
| XPRM  | 32 bytes | `primitive` volume bounds + shape (below)  |
| VMAD  | struct   | `scriptData` attachment accumulator        |

DATA: x/y/z position in game units, then x/y/z rotation in radians. Missing
NAME or DATA throws — a reference without them cannot be placed. XTEL is exact-size:
destination door REFR FormID (uint32), destination position float3, rotation float3 in
radians, flags uint32. Flag 0x01 = no alarm. Any other size throws malformed instead of
silently shifting fields. Ownership + remaining activation fields stay skipped. Refs:
UESP REFR page; xEdit `wbDefinitionsTES5.pas` XTEL `wbStruct`.
XRDS/XEMI lighting policy: [interior lighting records](/formats/lighting.md).
VMAD layout and PEX binding:
[Papyrus attachment data](/formats/vmad.md).

### `REFR XLKR` — linked references

`XLKR` is the link `ObjectReference.GetLinkedRef(akKeyword)` follows. It is a *repeating*
subrecord, not a packed array: one field per link, and a reference may carry several.
`PlacedReference.linkedReferences` keeps them all in file order;
`linkedReference(keyword:)` is the read path.

Two payload sizes exist:

| bytes | layout                                              | decoded as              |
| ----- | --------------------------------------------------- | ----------------------- |
| 8     | formID keyword (0 or `KYWD`), formID linked ref      | `keyword` + `ref`       |
| 4     | formID linked ref only                              | untagged link, `ref`    |

A keyword slot holding the null FormID means the link carries no keyword, so it decodes
identically to the 4-byte form (`keyword == nil`). Lookups therefore never mix the two:
`linkedReference(keyword:)` matches a tagged link only on an exact keyword, and
`linkedReference()` — the Papyrus default — matches only an untagged one.

Unlike XTEL, a wrong-size XLKR payload does not throw. XLKR is an optional repeating link,
so an unreadable payload costs one link; a wrong-size XTEL would teleport a door to the
wrong place. Under 4 bytes the field is skipped; 5 to 7 bytes are read as the 4-byte form
with the remainder ignored.

Real-data evidence (`PlacedReferenceLinkedRefRealDataTests`, `Skyrim.esm`, observed
2026-07-31): 12477 XLKR subrecords on 11287 of 693333 REFR records. Every payload is
exactly 8 bytes (12467) or exactly 4 (10) — the 10 matches the count UESP's REFR page
states independently. 10244 of the 8-byte payloads carry a null keyword slot, so the
untagged link is the common case, not an edge case. All 56 distinct non-null keyword slots
are `KYWD` records and no second FormID ever is, which is what pins the field order to
keyword-then-ref rather than the reverse; the 10 four-byte FormIDs are likewise never
keywords. No reference repeats a keyword and none carries more than one untagged link, so
first-match and only-match agree and `linkedReference(keyword:)` needs no tiebreak rule.
The deepest list observed is 19 links on one reference.

Flagged uncertainty: xEdit types the first member `Keyword/Ref` and admits `PLYR`, `ACHR`,
`REFR` there alongside `KYWD`, because in the 4-byte form that slot *is* the ref. Skyrim.esm
never puts a reference in slot 0 of an 8-byte payload, so OpenSky reads an 8-byte slot 0 as
a keyword unconditionally. A mod that broke that convention would have its link read as
tagged with a non-keyword rather than rejected.

Refs: UESP REFR page XLKR row ("8-byte struct: formid 0 or KYWD ..., formid REFR ...; 10
instances of 4 byte struct with just a formid in Skyrim.esm"); xEdit `dev-4.1.6`
`Core/wbDefinitionsTES5.pas` line 9910
`wbRArray('Linked References', wbStruct(XLKR, 'Linked Reference', [wbFormIDCk('Keyword/Ref',
...), wbFormIDCk('Ref', ...)], cpNormal, False, nil, 1))`, whose trailing `1` is
`aOptionalFromElement` (`Core/wbInterface.pas` line 4345) — that parameter is what makes the
second FormID droppable and the 4-byte form legal.

### `REFR XPRM` — primitive volume

`XPRM` is the invisible volume a reference encloses: trigger boxes, activation volumes,
portal boxes and occlusion volumes all carry one. Unlike XLKR it does not repeat — one
reference has at most one primitive — so `PlacedReference.primitive` is an optional, nil
when the field is absent.

One payload size exists:

| bytes | layout                                                          | decoded as     |
| ----- | --------------------------------------------------------------- | -------------- |
| 32    | float[3] bounds, float[3] color, float unknown, uint32 type       | `Primitive`    |

Field by field:

| offset | type      | member        | meaning                                       |
| ------ | --------- | ------------- | --------------------------------------------- |
| 0      | float[3]  | `halfExtents` | half the volume's size on each axis, pre-scale |
| 12     | float[3]  | `color`       | Creation Kit wireframe color, stored 0...1     |
| 24     | float     | `unknown`     | xEdit "Alpha"; one of four constants on disk   |
| 28     | uint32    | `type`        | shape enum, `PrimitiveType`                    |

The bounds are half-extents, not a full size: UESP labels the row "Bounds / 2" and xEdit
displays it through a float scale of 2. `XSCL` still multiplies them at placement time, so
the decoded values are pre-scale and in native Skyrim world units. A zero axis is legal —
Skyrim.esm writes 129 of them — so a degenerate volume decodes instead of being rejected.

`PrimitiveType` follows xEdit's `wbEnum` verbatim: 0 `none`, 1 `box`, 2 `sphere`, 3
`portalBox`, 4 `line`. `halfExtents` reads as a box's half-size for `box` and `portalBox`
and as a radius triple for `sphere`.

Decode policy follows XTEL rather than XLKR. XPRM is one non-repeating struct of
fixed-width members, so a payload of any other length can only be read by shifting every
field, and a shifted read gives a trigger volume the wrong size and the wrong shape. Any
length other than 32 throws `ESMError.malformed`, and the caller logs and skips the
reference. An out-of-enum `type` throws for the same reason: xEdit's enumeration is closed
at 0...4, so a value outside it means the payload is not a primitive this decoder
understands, and guessing `box` would place a solid-looking volume of unknown shape. Both
throws are bounded to the one reference carrying the bad field, and vanilla contains
neither case.

Real-data evidence (`PlacedReferenceXPRMRealDataTests`, `Skyrim.esm`, observed 2026-07-31):
13668 XPRM subrecords on 13668 of 693333 REFR records — exactly one per carrying reference,
which is what makes the non-repeating reading right. Every payload is exactly 32 bytes.
The type histogram is box 10163, sphere 137, portal box 3135, line 233; value 0 (`none`)
never appears and nothing falls outside the enum, so both throw paths are unreachable on
vanilla data. Every half-extent is finite and non-negative, 129 axes are exactly zero, and
the largest is 18027.004 units. Every color channel of every payload lies in 0...1, which
makes UESP's "Color / 255" a Creation Kit display note rather than an on-disk scale. The
`unknown` float takes exactly four distinct values across all 13668 payloads — 0.15, 0.2,
0.25 and 1.0 — matching the set UESP states independently; that agreement is the strongest
check that the field order is bounds, then color, then the unknown, then the type.

Flagged uncertainty: the fourth float is named "Alpha" by xEdit's `wbFloatRGBA` and left
unnamed by UESP, and its four observed values look more like a wireframe opacity or an
editor draw hint than anything the runtime reads. OpenSky carries it verbatim as
`Primitive.unknown` and interprets nothing. The `line` type is likewise unclear: xEdit names
it, UESP lists value 4 as unknown, and how a line volume uses three half-extents is not
established here — the 233 vanilla instances decode, but nothing downstream should assume
box semantics for them.

Refs: UESP REFR page XPRM row ("32 byte struct: float[3] - x,y,z Bounds / 2; float[3] -
r,g,b Color / 255; float - unknown: 0.15, 0.2, 0.25, 1.0 seen, same for any given base
object; uint32 - unknown: 1-4 seen, 1 Box, 2 Sphere, 3 Portal Box, 4 Unknown"); xEdit
`dev-4.1.6` `Core/wbDefinitionsTES5.pas` line 9701 `wbStruct(XPRM, 'Primitive',
[wbStruct('Bounds', [wbFloat('X', cpNormal, True, 2, 4), ...]), wbFloatRGBA,
wbInteger('Type', itU32, wbEnum(['None', 'Box', 'Sphere', 'Portal Box', 'Line']))])`, whose
`wbFloatRGBA` expands to Red/Green/Blue/Alpha in `Core/wbDefinitionsCommon.pas` line 6484 —
that fourth member is what the `unknown` float actually is — and whose bounds floats carry
`aScale = 2`, which is where the half-extent reading comes from.

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
placeable base types beyond STAT. M3.6 added DOOR draw coverage; M8.4.1 adds display and
activation metadata; M9.2.2 adds the sound links that drive activator/door/container SFX
(issue #155).

| field | type    | decoded                                        |
| ----- | ------- | ---------------------------------------------- |
| EDID  | zstring | `editorID`                                     |
| FULL  | lstring | `name`; inline or localized `.strings` ID      |
| MODL  | zstring | `modelPath` (nil = no model)                   |
| RNAM  | lstring | ACTI-only `activateTextOverride`               |
| FNAM  | uint8   | DOOR flags; bit 1 means automatic              |
| MNAM  | uint32  | FURN marker flags; bit 25 disables activation  |
| SNAM  | formID  | sound link; per-type meaning (see table below) |
| ANAM  | formID  | DOOR close sound                               |
| BNAM  | formID  | DOOR loop sound                                |
| VNAM  | formID  | ACTI activation sound                          |
| QNAM  | formID  | CONT close sound (not ANAM — cross-record trap)|
| VMAD  | struct  | `scriptData` attachment accumulator             |

Per-type reference, all UESP "Skyrim Mod:Mod File Format":

* MSTT (moveable static) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MSTT>
* TREE (tree/plant) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/TREE>
* FURN (furniture) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN>
* ACTI (activator) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ACTI>
* CONT (container) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT>
* DOOR (door) — <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOOR>

The cross-type field and flag authority is xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/fd1e36020b2b5b6217e553dc0038983146a2e2dd/Core/wbDefinitionsTES5.pas):
ACTI at lines 3297-3332, CONT at 4492-4521, DOOR at 4908-4933, FURN at 5205-5260,
MSTT at 5409-5437, and TREE at 10221-10253. In addition to the field flags above,
ACTI record-header bit 20 means `Ignore Object Interaction`. These three suppression
values produce `allowsManualInteraction = false`.

### Sound links (M9.2.2)

`ModelBase.Sounds` groups the per-type sound fields by runtime semantics so the
audio director reads one field per concept:

| semantic | DOOR | ACTI | CONT |
| -------- | ---- | ---- | ---- |
| `activation` (one-shot on use-key) | `SNAM` | `VNAM` | `SNAM` |
| `close` (one-shot on close) | `ANAM` | — | `QNAM` |
| `loop` (continuous positional loop) | `BNAM` | `SNAM` | — |

Each FormID stores either a SNDR descriptor (the modern record) or a SOUN legacy
marker (whose `SDSC` redirects to a SNDR). The decoder does not pin which one;
runtime `SoundRecordStore.resolveAny` follows the `SOUN -> SDSC -> SNDR` hop
when present. A probe against Skyrim.esm (`make probe`, 2026-07-26) found all
497 activator/door/container sound references target SNDR directly — vanilla SSE
ships no SOUN markers on these records, but the decoder still supports them.

Probe counts (Skyrim.esm 2026-07-26):

| record type | sound slot | bases carrying it |
| ----------- | ---------- | ----------------- |
| DOOR        | open       | 92                |
| DOOR        | close      | 86                |
| DOOR        | loop       | 0                 |
| ACTI        | activation | 33                |
| ACTI        | loop       | 18                |
| CONT        | open       | 135               |
| CONT        | close      | 133               |

Type-specific fields still skipped: remaining FURN furniture-marker/animation fields,
CONT inventory (CNTO), ACTI water type, TREE billboard/leaf-curve fields
(CVPA/BSNM/...), and remaining DOOR flags. `ModelBase.recordType` retains source
record type so callers can distinguish them without redecoding.

## GLOB -> Global

Global variables: a named, typed number the rest of the data set reads through
conditions, scripts and record links. Decoded by
`opensky/Formats/ESM/Records/Global.swift`; the mutable layer above it is
[runtime reference identity and world state](/engine/runtime-state.md).

Reference: UESP "Skyrim Mod:Mod File Format/GLOB"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/GLOB>) and xEdit
`dev-4.1.6` `wbDefinitionsTES5.pas` `wbRecord(GLOB, 'Global', ...)`.

| field  | type    | decoded                                            |
| ------ | ------- | -------------------------------------------------- |
| EDID   | zstring | `editorID`                                          |
| FNAM   | uint8   | `valueType`: `s` (0x73) short, `l` (0x6C) long, `f` (0x66) float |
| FLTV   | float32 | `defaultValue.value`, coerced onto `valueType`       |

Record-header flag 0x40 means the global is constant; it decodes into
`isConstant` and is recorded rather than enforced.

The layout's one trap is that **FLTV is a float32 whatever FNAM declares**. A
short or long global is a float on disk that happens to hold an integral value,
which is why UESP's page warns at length that a long global loses precision past
2^24 (values there round to multiples of 2, then 4, then 8). OpenSky keeps the
same representation — one `Float` plus the declared type in `GlobalValue` — and
coerces on every write instead of inventing a wider integer the file cannot
round-trip. Integer types round half away from zero; nothing is clamped to 16 or
32 bits, because a mod can legitimately store a value the type's nominal width
would not hold.

Decode policy: a wrong-size FNAM, or a type character outside the documented
`s`/`l`/`f` set, leaves the xEdit editor default (Float) in place rather than
costing the record its identity, and a wrong-size or absent FLTV leaves the
value at 0. UESP lists OBND and VMAD as vestigial on GLOB — checked for by the
game, never present in shipped data — and both are skipped. Only a non-GLOB
record throws.

`GlobalStore` (`opensky/World/GlobalStore.swift`) indexes the GLOB top group by
raw FormID, by editor ID (case-insensitively, because scripts and the console
have always matched global names that way) and by session-stable `ReferenceKey`.

## Verification

Unit tests: `openskyTests/RecordDecoderTests.swift`,
`GlobalRecordTests.swift`, `GlobalStoreTests.swift`,
`ModelBaseInteractionTests.swift`,
`LocalizedStringsTests.swift` (synthetic fixtures). Runtime probe 2026-07-09
against vanilla Skyrim.esm (milestone 1 acceptance): 37 worldspaces listed
with EDID + FULL resolved via string tables from `Skyrim - Interface.bsa`
(e.g. Tamriel "Skyrim", 11 187 cells); 16 978 exterior-group cells decoded,
all carrying XCLC grids; 9 720 STAT records (9 712 with MODL); cell
WhiterunExterior01 (0000961B, grid 4,-3) dumped 100 STAT refs with FormIDs,
positions, rotations, scales, model paths (52 non-STAT refs skipped).
Positions all lie inside the cell's 4096-unit grid extent.
