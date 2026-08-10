---
type: File Format
title: Record decoders (WRLD, CELL, REFR, STAT, ModelBase, GLOB, inventory items, QUST)
description: Field layouts of decoded plugin records and OpenSky's engine types.
tags: [format, plugin, records, worldspace, cell, globals, inventory, items, quests]
timestamp: 2026-08-02T00:00:00Z
---

# Record decoders, Skyrim SE

Record decoders over the [ESM container](/formats/esm.md): worldspace listing, cell
grids, placed references, static + placeable model base objects — the data needed to
build an exterior cell scene (milestone 2, widened in 3.2). TES4 decode lives in
[FormID + TES4 header](/formats/formid.md).

Reference: UESP "Skyrim Mod:Mod File Format" per-record pages
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>, subpages `/WRLD`,
`/CELL`, `/REFR`, `/STAT`, `/MSTT`, `/TREE`, `/FURN`, `/ACTI`, `/CONT`, `/DOOR`,
and — for the M12.1.1 inventory families — `/MISC`, `/BOOK`, `/ALCH`, `/INGR`,
`/WEAP`, `/AMMO`, `/ARMO`).
Water-specific
fields + WATR layout: [exterior water records](/formats/water.md). Impl:
`opensky/Engine/Formats/ESM/Records/`.

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
* not localized -> inline zstring, lenient decode (`GameText`: UTF-8, else
  windows-1252, else ISO 8859-1; see
  [string decoding](/decisions/string-decoding.md)).

`LString` (enum: `.inline` / `.tableID`) carries this; `LocalizedStrings`
(`GameData/LocalizedStrings.swift`) resolves IDs through the VFS at
`strings\<plugin stem>_<language>.<ext>`, lazy per kind, missing table ->
nil + one os_log error. Language defaults to "english" until a setting
exists (open question, GitHub issue #441).

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
| XOWN  | formID   | `owner` — owning NPC_ or FACT (M12.1.1)    |
| XRNK  | int32    | `ownerFactionRank` (M12.1.1)               |
| XCNT  | int32    | `itemCount` stack size (M12.1.1)           |
| VMAD  | struct   | `scriptData` attachment accumulator        |

DATA: x/y/z position in game units, then x/y/z rotation in radians. Missing
NAME or DATA throws — a reference without them cannot be placed. XTEL is exact-size:
destination door REFR FormID (uint32), destination position float3, rotation float3 in
radians, flags uint32. Flag 0x01 = no alarm. Any other size throws malformed instead of
silently shifting fields. Remaining activation fields stay skipped. Refs:
UESP REFR page; xEdit `wbDefinitionsTES5.pas` XTEL `wbStruct`.

Ownership (M12.1.1): `XOWN` is a plain 4-byte FormID in Skyrim — xEdit's
[`wbOwnership`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
only widens it to a 12-byte struct for Fallout 4 and later. A null XOWN decodes as
unowned rather than "owned by FormID 0". `XRNK` is the faction rank the player needs to
use the reference freely, and is meaningful only when the owner is a FACT. `XCNT` is the
stack size of a placed inventory item; absent means one. All three degrade to nil on a
payload shorter than four bytes rather than throwing, because losing an ownership tag is
recoverable and refusing to place the reference is not.

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

One shared `ModelBase` (`opensky/Engine/Formats/ESM/Records/ModelBase.swift`) decodes six
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
ACTI water type, TREE billboard/leaf-curve fields (CVPA/BSNM/...), and remaining
DOOR flags. `ModelBase.recordType` retains source record type so callers can
distinguish them without redecoding. CONT inventory is decoded by `Container`
(below), which composes `ModelBase` rather than replacing it.

## Shared inventory subrecords (M12.1.1)

The seven carryable families below plus ARMO repeat the same run of fields, so three
helpers decode it once. Impl: `ObjectBounds.swift`, `KeywordList.swift`,
`InventoryItemFields.swift`.

| helper                | fields                                            |
| --------------------- | ------------------------------------------------- |
| `ObjectBounds`        | OBND — six int16, min corner then max corner       |
| `KeywordList`         | KSIZ uint32 count + KWDA packed KYWD FormID array  |
| `ItemValue`           | the 8-byte DATA: int32 gold value, float32 weight  |
| `InventoryItemFields` | EDID, FULL, MODL, OBND, KSIZ/KWDA, ICON, MICO, YNAM, ZNAM |

`ObjectBounds` is the authority of xEdit `wbOBND`
([`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
line 8634); UESP lists the field on every placeable base record.

Advisory-count policy: **KSIZ never sizes the KWDA read**, and neither does COCT for
CNTO. The real length is the payload divided by the entry size. A plugin whose authored
count disagrees is recorded (`KeywordList.countMismatch`,
`Container.entryCountMismatch`) but decodes from the bytes present, so a stale count
cannot truncate a list or run the reader past the field.

DATA is deliberately *not* in `InventoryItemFields`: its layout is type-specific —
8 bytes on MISC/INGR/ARMO, 4 on ALCH, 10 on WEAP, 16 on BOOK, 16 or 20 on AMMO — so each
record owns that case.

## MISC -> MiscItem

The plain carryable object: gems, ingots, tools, gold, clutter. Nothing beyond the shared
fields plus the 8-byte value/weight DATA. Reference: UESP
"[Skyrim Mod:Mod File Format/MISC](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MISC)";
xEdit `wbDefinitionsTES5.pas` line 8303. Skipped: VMAD, DEST.

## BOOK -> Book

| field | type     | decoded                                    |
| ----- | -------- | ------------------------------------------ |
| DESC  | lstring  | `text` — the book's body                    |
| CNAM  | lstring  | `inventoryDescription` blurb                |
| DATA  | 16 bytes | flags, kind, teaches union, value, weight   |

DATA layout: uint8 flags (0x01 teaches skill, 0x02 can't be taken, 0x04 teaches spell),
uint8 kind (0 book/tome, 255 note/scroll — always 0 since SSE), two unused bytes, a
uint32 "teaches" word, uint32 gold value, float32 weight.

The teaches word is a union read per the flags: an actor-value skill index when 0x01 is
set, a SPEL FormID when 0x04 is set, otherwise unused. It decodes into
`Book.Teaches` (`.nothing` / `.skill` / `.spell`) rather than being read twice, and 0x04
wins when a mod sets both. Book body text resolves through the `.dlstrings` table, not
`.strings` — see [string tables](/formats/strings.md).

Reference: UESP
"[.../BOOK](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/BOOK)"; xEdit
`wbDefinitionsTES5.pas` line 4220. Skipped: VMAD, DEST, INAM inventory art.

## ALCH -> Ingestible

Food, drink, potions and poisons. The one carryable family whose DATA is **not** value +
weight: DATA is a bare float32 weight and the gold value lives in ENIT. The decoder fills
one engine-level `itemValue` from both, so consumers never special-case it.

ENIT, 20 bytes: int32 value, uint32 flags (0x00001 no auto-calc, 0x00002 food,
0x10000 medicine, 0x20000 poison), FormID addiction, float32 addiction chance, FormID
consume SNDR.

Reference: UESP
"[.../ALCH](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ALCH)"; xEdit
`wbDefinitionsTES5.pas` line 4042. Skipped: DEST, ETYP.

## INGR -> Ingredient

Alchemy ingredients: the same MagicItem shape as ALCH, but with the ordinary 8-byte
value/weight DATA and an 8-byte ENIT — int32 auto-calc value (distinct from the gold
value in DATA) and uint32 flags (0x001 no auto-calc, 0x002 food, 0x100 references
persist).

Reference: UESP
"[.../INGR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INGR)"; xEdit
`wbDefinitionsTES5.pas` line 7909. Skipped: VMAD, DEST, ETYP.

### Effect lists (EFID/EFIT/CTDA)

ALCH and INGR carry effects as a *run* of subrecords, not a struct: EFID names the MGEF,
the EFIT that follows carries its numbers, and any CTDA after that conditions that one
effect. The run repeats. `MagicItemEffectList` folds it into `[MagicItemEffect]`;
conditions decode through the shared [`ConditionList`](/formats/conditions.md) so CITC
and CIS1/CIS2 behave as they do everywhere else.

| field | type     | decoded                                    |
| ----- | -------- | ------------------------------------------ |
| EFID  | formID   | `effect` — the MGEF applied                 |
| EFIT  | 12 bytes | float32 magnitude, uint32 area, uint32 duration |
| CTDA  | 32 bytes | `conditions` on this effect                 |

Scope: effects decode as **links only**. MGEF semantics and the auto-calc cost formula
belong to the magic milestone. Degrade policy: an EFIT with no EFID before it is dropped;
an EFID whose EFIT never arrives still yields an entry with zero magnitude, because the
MGEF link is the part inventory needs. Neither case throws.

Reference: xEdit `wbDefinitionsTES5.pas` `wbEFID` line 3832, `wbEFIT` 3834,
`wbEffect` 4030.

## WEAP -> Weapon

| field | type      | decoded                                   |
| ----- | --------- | ----------------------------------------- |
| DATA  | 10 bytes  | uint32 value, float32 weight, uint16 damage |
| DNAM  | 100 bytes | animation type, speed, reach, flags, skill, stagger |
| CRDT  | 16 or 24  | critical damage, multiplier, on-death, SPEL |
| EITM  | formID    | `enchantment` (ENCH)                        |
| EAMT  | uint16    | `enchantmentCharge`                         |
| ETYP  | formID    | `equipType` (EQUP)                          |
| CNAM  | formID    | `template` — another WEAP                   |
| INAM  | formID    | `impactDataSet` (IPDS) — normal swing impact |
| BIDS  | formID    | `blockBashImpactDataSet` (IPDS) — block bash |

DNAM offsets read: `00` uint8 animation type (0 other, 1 one-hand sword ... 9 crossbow),
`04` float32 speed, `08` float32 reach, `0C` uint16 flags (0x08 can't drop, 0x20 embedded,
0x80 non-playable), `4C` int32 governing skill as an actor value (-1 = none, decoded as
nil), `60` float32 stagger. The rest is padding, obsolete Fallout carry-over, or rumble.

CRDT is the one field whose SSE layout differs from Skyrim classic, so the **payload size
picks the layout** rather than the plugin's form version — an SSE-only engine still reads
classic-era mod records:

| bytes | layout                                                              |
| ----- | ------------------------------------------------------------------- |
| 16    | uint16 damage, 2 unused, float32 % mult, uint8 on-death, 3 unused, formID SPEL |
| 24    | as above but 7 unused after on-death, SPEL at `0x10`, 4 trailing unused |

Any other length decodes as no critical data rather than being force-fit.

Reference: UESP
"[.../WEAP](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WEAP)"; xEdit
`wbDefinitionsTES5.pas` record at line 10499, DATA 10530, DNAM 10535, CRDT 10604.
DNAM `reach` is a multiplier, not a distance: UESP states the melee reach formula as
`fCombatDistance * NPCScale * WeaponReach`, which is what
[melee combat](/engine/melee-combat.md) resolves it through.

INAM and BIDS are the two IPDS links a landed hit resolves its impact sound through, added
by roadmap item 15.4. UESP names INAM "Normal weapon swing impact set" and BIDS "Block bash
impact data set", so an ordinary swing reads INAM and only a shield bash reads BIDS; a null
link means the weapon names no set and the hit is silent, which is normal vanilla data.

Skipped: VMAD, DEST, MOD3 scope model, BAMT bash material, the seven SNDR attack
sounds, NNAM, WNAM, VNAM.

## AMMO -> Ammunition

DATA grew by one field in SSE, so — as with WEAP CRDT — the payload size picks the layout:

| offset | type    | decoded                                              |
| ------ | ------- | ---------------------------------------------------- |
| 00     | formID  | `projectile` (PROJ)                                   |
| 04     | uint32  | flags: 0x01 ignores weapon resistance, 0x02 non-playable, 0x04 non-bolt |
| 08     | float32 | `damage`                                              |
| 0C     | uint32  | gold value                                            |
| 10     | float32 | weight — **SSE only**; the classic 16-byte form ends at 0x0C |

A classic payload decodes with weight 0, which is what the engine would use anyway:
vanilla SSE writes 0.1 for every arrow and the carry system treats arrows as weightless.

Reference: UESP
"[.../AMMO](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AMMO)"; xEdit
`wbDefinitionsTES5.pas` record at line 4087, the `IsSSE` DATA pair at 4101.
Skipped: DEST, ONAM.

## PROJ -> Projectile

The record an AMMO launches, added by roadmap item 15.5. Everything the flight
model needs is in one DATA struct, and UESP and xEdit agree on it member for
member. Vanilla writes 92 bytes:

| offset | type    | decoded                                       |
| ------ | ------- | --------------------------------------------- |
| 00     | uint16  | `flags` — 0x01 hitscan, 0x02 explosion, 0x04 alt. trigger, 0x08 muzzle flash, 0x20 can be disabled, 0x40 can be picked up, 0x80 supersonic, 0x100 pins limbs, 0x200 pass through small transparent, 0x400 disable combat aim correction, 0x800 rotation |
| 02     | uint16  | `kind` — 0x01 missile, 0x02 lobber, 0x04 beam, 0x08 flame, 0x10 cone, 0x20 barrier, 0x40 arrow |
| 04     | float32 | `gravityFactor` — a **multiplier** over world gravity, not an acceleration |
| 08     | float32 | `speed` — launch speed, world units per second |
| 0C     | float32 | `range` — travel past which the projectile is given up on |
| 10, 14 | formID  | LIGH light, LIGH muzzle-flash light — skipped |
| 18-20  | float32 | tracer chance, explosion proximity, explosion timer — skipped |
| 24     | formID  | `explosion` (EXPL)                             |
| 28     | formID  | `sound` (SNDR), played in flight               |
| 2C, 30 | float32 | muzzle-flash duration, fade duration — skipped |
| 34     | float32 | `impactForce`                                  |
| 38     | formID  | countdown sound (SNDR) — skipped               |
| 3C     | formID  | `disableSound` (SNDR)                          |
| 40     | formID  | default weapon source (WEAP) — skipped         |
| 44     | float32 | cone spread — skipped                          |
| 48     | float32 | `collisionRadius`                              |
| 4C     | float32 | `lifetime`, seconds                            |
| 50     | float32 | relaunch interval — skipped                    |
| 54, 58 | formID  | TXST decal data, COLL collision layer — **optional**, skipped |

The two trailing FormIDs are the only optional members: xEdit marks the DATA
struct "optional from element 22", which is the decal link, so an 84-byte payload
is as valid as the full 92. The decoder therefore reads what the payload carries
rather than demanding one size, and accepts anything from 16 bytes — flags
through `range`, the whole flight model — upward.

One member the two sources spell differently: UESP calls offset 0x3C "uint32
always 0" where xEdit names it `Sound - Disable`, a SNDR link. The offsets are
identical either way, so nothing downstream shifts; xEdit's reading is carried
because "always 0" is an observation about vanilla data rather than a statement
about the field.

`gravity` has no documented unit and is settled by measurement rather than
assumption — over the 20 arrow-type PROJ in `Skyrim.esm` it is bounded by 1 while
`speed` runs to the thousands, which is a dimensionless scale. The full census
and the arithmetic behind the reading are in
[archery and projectiles](/engine/archery.md).

Reference: UESP
"[.../PROJ](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PROJ)"; xEdit
`wbDefinitionsTES5.pas` `wbRecord(PROJ, ...)` at line 5449, DATA at 5454 with
member offsets in its own comments.
Skipped: FULL, DEST, NAM1/NAM2 muzzle-flash model, VNAM is decoded as
`soundLevel`.

## CONT contents -> Container

`Container` **composes** `ModelBase` rather than replacing it: `base` is the same decode
the cell builder and interaction path already use, and this type adds only the inventory
half. Contents are a run, not one array:

| field | type     | decoded                                       |
| ----- | -------- | --------------------------------------------- |
| COCT  | uint32   | `declaredEntryCount` (advisory, see above)     |
| CNTO  | 8 bytes  | formID item + int32 count, repeating           |
| COED  | 12 bytes | owner data for the CNTO immediately before it  |
| DATA  | uint8+   | flags: 0x01 allow sounds, 0x02 respawns, 0x04 show owner |

A CNTO item may be a carryable base *or* an LVLI, which the inventory runtime expands.
COED's middle word is a union — a GLOB FormID when the owner is an NPC_, a required
faction rank when it is a FACT — and resolving that needs a cross-record type lookup the
decoder does not have, so it is carried raw as `ownerCondition`. A COED with no preceding
CNTO is dropped; a CNTO under 8 bytes costs one entry, not the container. DATA's trailing
float is documented as a misaligned weight that is always 0 and is not decoded.

Reference: UESP
"[.../CONT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT)"; xEdit
`wbDefinitionsTES5.pas` `wbCOED` line 2305, `wbCNTO` 2315, `wbCOCT` 2329,
`wbRecord(CONT, ...)` 4505.

## ARMO inventory fields (M12.1.1)

`Armor` already decoded the appearance subset ([actor records](/formats/actors.md)).
M12.1.1 adds the inventory-facing half so ARMO can join the item index: `DATA` (the shared
`ItemValue` 8-byte struct), the `KSIZ`/`KWDA` keyword array, and `DNAM`, the base armor
rating stored as rating * 100 — despite being a uint32, only the low 16 bits are used.
Still skipped: MOD2/MOD4 ground models, EITM enchantment, TNAM template.

## Item definition index -> ItemDefinitionStore

`opensky/Engine/Inventory/ItemDefinitionStore.swift` indexes one plugin's carryable base records
behind one view, so the inventory runtime resolves an item FormID without knowing which
of the seven families it came from. Immutable, built once from an `ESMFile`, following
the `WeatherStore` / `SoundRecordStore` convention.

`ItemDefinition` exposes `formID`, `family` (ARMO, AMMO, BOOK, ALCH, INGR, MISC, WEAP),
`editorID`, `name`, `value`, `weight` and `keywords`. Containers are indexed *separately*
(`container(_:)`): a CONT is not carryable and has neither a gold value nor a weight, but
its starting contents are exactly what the runtime needs. `skippedCounts` reports records
that failed to decode per family, so the sweep can assert zero rather than silently
indexing fewer items.

**Stackability, v1**: every item stacks by base FormID (`ItemDefinition.stackKey`). That
is correct only while no per-instance data exists. Tempering, enchanting, charge level and
item health all make two instances of the same base FormID distinct, so the key grows into
a compound one when per-instance data lands. The rule is provisional by design, not an
oversight.

## GLOB -> Global

Global variables: a named, typed number the rest of the data set reads through
conditions, scripts and record links. Decoded by
`opensky/Engine/Formats/ESM/Records/Global.swift`; the mutable layer above it is
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

`GlobalStore` (`opensky/Engine/World/GlobalStore.swift`) indexes the GLOB top group by
raw FormID, by editor ID (case-insensitively, because scripts and the console
have always matched global names that way) and by session-stable `ReferenceKey`.

## MOVT -> MovementType

Movement types: how fast an actor using this gait moves in each direction. Decoded by
`opensky/Engine/Formats/ESM/Records/MovementType.swift`; the player's four gaits feed
`PlayerMovementConfiguration` and through it the locomotion bridge of
[walk mode](/engine/walk-mode.md).

Reference: UESP "Skyrim Mod:Mod File Format/MOVT"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MOVT>) and xEdit `dev-4.1.6`
`wbDefinitionsTES5.pas` `wbRecord(MOVT, ...)`.

| field | type | decoded |
| ----- | ---- | ------- |
| EDID | zstring | `editorID`, the name the index is keyed by |
| MNAM | zstring | `name`, the Creation Kit and behavior-graph name |
| SPED | 11 x float32 | `speeds`, the directional speed struct |
| INAM | 3 x float32 | skipped; directional-change thresholds nothing reads yet |

SPED is a fixed struct with no count field. Its order is the one xEdit names — left walk,
left run, right walk, right run, forward walk, forward run, back walk, back run, rotate in
place walk, rotate in place run, rotate while moving run — and the shipped data corroborates
it: `NPC_Sprinting_MT` is `0` in every lateral slot and `500` in the forward pair, which is
only consistent with forward sitting at float indices 4 and 5. The first eight are units per
second; the last three are radians per second.

A SPED shorter than 11 floats is dropped whole rather than zero-padded, because a
half-decoded speed reads as a legitimate "this actor cannot move".

`MovementTypeStore` indexes the MOVT top group across the active load order, keyed by
lowercased editor ID, later plugin winning — the same override rule `GameSettingStore`
applies to GMSTs, over the shared load-order walk in `ActivePluginFiles`.

Observed in `Skyrim.esm` on 2026-08-03, forward walk / forward run in units per second:

| Editor ID | MNAM | Forward walk | Forward run |
| --- | --- | --- | --- |
| `NPC_Default_MT` | `NPCDefault` | 80.1 | 370.0 |
| `NPC_Sneaking_MT` | `NPCSneaking` | 47.2 | 222.0 |
| `NPC_Sprinting_MT` | `NPCSprinting` | 0.0 | 500.0 |
| `NPC_Swimming_MT` | `NPCSwimming` | 80.1 | 370.0 |

## NAVM/NAVI -> Navmesh, NavmeshInfoMap

The walkable surface, and the plugin-wide index over it. NAVM is a cell child like LAND
and REFR are, carrying one oversized `NVNM` payload; NAVI is a single top-level record
listing every navmesh with its location and its links. Both have their own page —
[navmesh records](/formats/navmesh.md) — because the layout is large and the parent-cell
union needed settling between two disagreeing sources.

| record | field | decoded |
| ------ | ----- | ------- |
| NAVM   | NVNM  | `NavmeshGeometry`: version, parent cell or grid, vertices, triangles with per-edge neighbours and flags, edge links, door links |
| NAVI   | NVER  | `version` |
| NAVI   | NVMI  | `NavmeshInfo` per navmesh: flags, approximate centre, edge links, door links, location |
| NAVI   | NVSI  | `deletedNavmeshes` |

Skipped: `NAVM` ONAM/PNAM/NNAM, the cover-triangle and navmesh-grid lists, the NVMI island
block, and NAVI's NVPP — each tallied rather than silently dropped, and each listed with its
reason on the navmesh page.

`CellSceneBuilder.collectNavmeshes` picks NAVM out of a cell's children groups; it is the
other half of the deliberate NAVM skip in `collectTaggedReferences`, and stays off the scene
build path because nothing rendered or collided reads a navmesh. `NavmeshIndex` is the NAVI
store, built once in `CellProviderIndexes`.

## QUST -> Quest

Quests: journal stages, objectives, and the alias slots a quest resolves world objects
through. Decoded by `opensky/Engine/Formats/ESM/Records/Quest.swift` and its three satellites
(`QuestComponents.swift`, `QuestDecoder.swift`, `QuestDecoderGroups.swift`,
`QuestAliasDecoder.swift`). The stage *scripts* are not in the record: they live in the
QUST tail of VMAD, decoded into `QuestFragmentSection`
([Papyrus attachment data](/formats/vmad.md)).

Reference: UESP
"[.../QUST](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/QUST)"; xEdit
`dev-4.1.6` `wbDefinitionsTES5.pas` `wbRecord(QUST, 'Quest', ...)` line 8759 — DNAM 8763,
stages 8797, objectives 8840, reference aliases 8869, location aliases 8971.

QUST is the most **order-dependent** record in the format. Almost nothing in it is a
self-describing struct; a marker subrecord opens a group and every following subrecord
belongs to that group until the next marker. Three such sequences stack up, and two
separator fields drive the rest.

| field | type | decoded |
| ----- | ---- | ------- |
| EDID  | zstring | `editorID` |
| VMAD  | VMAD | `script`, including the decoded quest fragment tail |
| FULL  | lstring | `name` |
| DNAM  | 12 bytes | `uint16` flags, `uint8` priority, `uint8` form version, 4 unused, `uint32` type |
| ENAM  | char[4] | `event`, the story-manager event short name |
| QTGL  | formid | `textDisplayGlobals`, repeating |
| FLTR  | zstring | `objectWindowFilter`, Creation Kit folder path |
| CTDA  | struct[32] | `dialogueConditions` before NEXT, `storyManagerConditions` after |
| NEXT  | empty | separator between those two condition runs |
| INDX  | 4 bytes | opens a `Stage`: `uint16` index, `uint8` flags, 1 unused |
| QSDT  | uint8 | opens a `LogEntry` in the open stage; flags 0x01 complete, 0x02 fail |
| CNAM  | lstring | the open log entry's journal text |
| NAM0  | formid | the open log entry's next quest |
| QOBJ  | uint16 | opens an `Objective` and ends the stage run |
| FNAM  | uint32 | the open objective's flags (0x01 ORed with previous) |
| NNAM  | lstring | the open objective's display text — see below |
| QSTA  | 8 bytes | opens a `Target`: `int32` alias, `uint8` ignores locks, 3 unused |
| ANAM  | uint32 | `nextAliasID`; ends the objective run and opens the alias run |
| ALST / ALLS | uint32 | opens a reference / location `Alias` |
| ALED  | empty | closes the open alias |

Inside an alias, the field names shadow quest-level ones: `FNAM` is alias flags, `CTDA` is
the alias's own match conditions, and `KSIZ`/`KWDA` and `COCT`/`CNTO` are the keywords and
items given to the alias target for the quest's duration. The decoder therefore routes
every field to the open alias first, which is what keeps the two readings apart.

`NNAM` is the one genuinely ambiguous spelling: it is an lstring objective display text
inside the objective run and a plain zstring quest description (`questDescription`) after
ANAM has ended that run. `QSTA` is similarly re-read after ANAM as a record-level legacy
target whose word is a reference FormID rather than an alias ID (`legacyTargets`); vanilla
`Skyrim.esm` writes none.

### Alias fill types

The Creation Kit presents an alias as having exactly one "fill type", but on disk that
choice is implied by which of a dozen mutually exclusive subrecords appear. Rather than
guess the intent while parsing, each slot decodes into its own property and
`Alias.fillType` reports the choice afterwards, in the Creation Kit's own union order.

| fill type | subrecords | applies to |
| --------- | ---------- | ---------- |
| specific reference | ALFR | Ref |
| unique actor | ALUA | Ref |
| specific location | ALFL | Loc |
| location alias reference | ALFA + ALRT | Ref |
| reference alias location | ALFA + KNAM | Loc |
| external alias | ALEQ + ALEA | Loc/Ref |
| create reference to object | ALCO + ALCA + ALCL | Ref |
| near alias | ALNA + ALNT | Ref |
| from event | ALFE + ALFD | Loc/Ref |
| none | — | filled by script, by ALFI, or on conditions alone |

### Decode policy

A wrong-size subrecord costs its own entry, a subrecord arriving with no group open costs
itself, an alias cut off without its ALED terminator is kept and recorded, and an unknown
or later-game subrecord is skipped. All four are counted in `QuestTally` so a sweep can
assert against them rather than discover the loss silently. Only a non-QUST record throws.

`QuestStore` (`opensky/Engine/World/QuestStore.swift`) indexes the QUST top group by raw FormID,
by editor ID (case-insensitively, for the same reason `GlobalStore` does) and by
session-stable `ReferenceKey`, following the same immutable-index convention. Quest
*state* belongs to the runtime (issue #182) and deliberately does not live there.

`RecordTextDump.questSummary` puts the decode on both dev surfaces:
`openskycli record --type QUST` and the Asset Browser detail pane print name, type,
priority, flags, and the stage, objective, alias and fragment counts.

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

### Inventory records (M12.1.1)

Unit tests, all synthetic fixtures: `InventoryRecordTests.swift` (shared subrecords, MISC,
BOOK), `MagicItemRecordTests.swift` (ALCH, INGR, effect runs),
`EquipmentRecordTests.swift` (WEAP, AMMO, ARMO inventory fields),
`ContainerRecordTests.swift` (CONT contents, REFR ownership),
`ItemDefinitionStoreTests.swift` (the index), with payload builders in
`InventoryRecordFixtures.swift`. Every family covers the wrong-type-throws,
truncated-field and empty-record cases.

Env-gated sweep `InventoryRecordRealDataTests.swift`
(`make realtest T='InventoryRecordRealDataTests/sweepsEveryInventoryRecord()'`), against
vanilla Skyrim.esm on 2026-08-01:

| measure | value |
| ------- | ----- |
| items decoded, zero throws | 6930 (ARMO 2762, WEAP 2484, BOOK 821, ALCH 363, MISC 371, INGR 94, AMMO 35) |
| decode skips | 0 |
| containers | 436 CONT, 9597 CNTO entries |
| CNTO entries resolving into the item index | 6753; the rest are LVLI/KEYM/LIGH/SLGM/APPA/SCRL |
| CNTO entries targeting an unexpected record type | 0 |
| COCT/CNTO count mismatches | 0 |
| value range / weight range | 0...5000 gold, 0.0...50.0 |
| placed references with XOWN / XCNT | 7765 / 118 |

The zero unexpected-target count is what pins the CNTO layout: every one of the 9597
entries resolves to a record whose type is in the set xEdit constrains the slot to, which
would not hold if item and count were being read in the wrong order. The sweep writes its
summary to gitignored `logs/inventory-sweep.log`.

Decoded output is reachable from both dev surfaces through
`RecordTextDump.itemSummary` — `openskycli record <formid-or-editorid>` and the Asset
Browser detail pane. Spot checks on 2026-08-01: `IronSword` (WEAP 00012EB7) prints value
25, weight 9.00, damage 7, `oneHandSword`, speed 1.00, reach 1.00, critical 3;
`SkillSmithing1` (BOOK 0001AFCE) prints teaches skill 10 with text present; `Wheat`
(INGR 0004B0BA) prints 4 effects and auto-calc value 47; `IronArrow` (AMMO 0001397D)
prints damage 8.0 and projectile 0003BE11; `BarrelFood01` (CONT 00000845) prints 1 entry
and flags 0x2.

### Quests (M13.1)

Unit tests, all synthetic fixtures (`QuestFixture.swift`): `QuestRecordTests.swift`
(header, both condition runs, stage grouping, objective/target pairing, wrong-type-throws,
truncated-field and empty-record cases), `QuestAliasRecordTests.swift` (alias open and
terminate, alias-level field shadowing, every fill type),
`QuestFragmentTests.swift` (fragment table, alias script sections, both object formats,
malformed tail) and `QuestStoreTests.swift` (the index).

Env-gated sweep `QuestRealDataTests.swift`
(`make realtest T='QuestRealDataTests/sweepsEveryQuestInSkyrimESM()'`), against vanilla
`Skyrim.esm` on 2026-08-02:

| measure | value |
| ------- | ----- |
| quests decoded, zero throws | 1811 |
| stages / with journal text | 5220 / 726 |
| log entries / with CNAM text | 5294 / 771 |
| objectives / objective targets | 1452 / 1808 |
| record-level legacy targets | 0 |
| aliases (reference / location) | 12,891 (11,999 / 892) |
| duplicate alias IDs within a quest | 0 |
| fragment tables / stage fragments / alias script sections | 856 / 5108 / 2149 |
| fragment tails lost to a malformed layout | 0 |
| subrecords skipped | 53, all vestigial SCHR/SCTX/QNAM |
| conditions / distinct raw function indices | 11,427 / 90 |
| condition traffic the standard registry answers | 32.7% |

Alias fill types used: unique actor 2900, specific reference 2687, from event 2065, none
2062, location alias reference 2036, create reference to object 630, near alias 218,
specific location 162, external alias 83, reference alias location 48. Every fill type the
decoder models is exercised by vanilla data, which is what pins the union to xEdit's
reading of it.

Three link invariants are asserted rather than printed, and they are the real proof the
grouping state machine attributes each subrecord to the right parent: every objective
target names an alias its own quest declares (0 misses), every fragment names a stage its
own quest declares (0 misses), and every alias script section names its own quest
(0 misses). The 53 skipped subrecords are exactly the three the Creation Kit wrote in an
earlier version and xEdit marks unused (`wbUnused(SCHR/SCTX/QNAM)` under 'Log Entry').

The sweep doubles as the M13 target-quest shortlist and writes it to gitignored
`logs/quest-census.log`: 62 quests need no condition function outside
`ConditionFunctionRegistry.standard`, show journal text, and carry stage fragments. The
cheapest are `MGRArniel01` (0006A086, 2 stages, 1 objective, 1 forced-reference alias, 2
fragments, no conditions), `DBEviction` (0006F9A5) and `TGCrownMisc` (0006D585). The
milestone picks from that list, against real data rather than memory.
