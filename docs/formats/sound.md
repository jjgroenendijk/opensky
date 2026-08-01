---
type: File Format
title: Sound records
description: Skyrim SE SNDR, SNCT, and SOUN fields, category hierarchy, links, and paths.
tags: [format, plugin, audio, sound]
timestamp: 2026-08-01T00:00:00Z
---

# Sound records

OpenSky decodes `SNDR` sound descriptors, `SNCT` sound categories, and `SOUN` sound
markers from the [ESM container](/formats/esm.md). A marker names one descriptor; the
descriptor supplies ordered track paths and playback metadata, and its category link
places it in the authored mixer hierarchy.

The field inventory follows the UESP
[`SNDR`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR) and
[`SNCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNCT) and
[`SOUN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN) pages. Field widths and
signedness are cross-checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).
The Creation Kit
[`Sound Descriptor`](https://ck.uesp.net/wiki/Sound_Descriptor) page describes the
authoring meaning of the decoded controls.

## SNDR sound descriptor

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `CNAM` | uint32 | optional raw descriptor type |
| `GNAM` | FormID | optional sound category |
| `SNAM` | FormID | optional alternate descriptor |
| `ANAM` | zstring | one ordered track path; field may repeat |
| `ONAM` | FormID | optional output model |
| `LNAM` | 4 bytes | looping selector in byte 1 |
| `BNAM` | 6 bytes | frequency, priority, variance, and attenuation parameters |

`LNAM` byte 1 maps `0` to no loop, `8` to loop, `16` to fast envelope, and `32` to slow
envelope. OpenSky preserves any other selector as an unknown raw value rather than
inventing behavior for it. The other three bytes are currently retained only by the
record framing.

`BNAM` is decoded in this order:

| offset | type | meaning |
| --- | --- | --- |
| 0 | int8 | frequency shift, percent |
| 1 | int8 | frequency variance, percent |
| 2 | uint8 | priority |
| 3 | uint8 | decibel variance |
| 4 | uint16 | static attenuation, stored as hundredths of a decibel |

The public attenuation value divides the stored uint16 by 100 and exposes decibels as a
`Float`. Signed int8 frequency values remain signed percentages.

## SNCT sound category

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `FULL` | lstring | optional authored name |
| `FNAM` | uint32 flags | bit 0 mute when submerged; bit 1 show on menu |
| `PNAM` | FormID | optional parent `SNCT` |
| `VNAM` | uint16 / 65535 | optional static volume multiplier |
| `UNAM` | uint16 / 65535 | optional default menu value |

`SNCT.PNAM` forms a hierarchy. `SoundRecordStore` starts at `SNDR.GNAM`, follows parents,
and maps the first menu-visible vanilla node to an `AudioCategory`. A visited FormID set
terminates malformed mod cycles. Missing nodes, cycles, and unknown menu category editor
IDs produce no mapping; the world-sound director falls back to Effects rather than
crashing or inventing a hierarchy.

A read-only Skyrim.esm probe on 2026-07-28 found 18 `SNCT` records, of which 13 are direct
`SNDR.GNAM` targets. Four nodes carry `Should Appear on Menu`; these are the runtime
category set:

| `SNCT.EDID` | authored English label | `AudioCategory` |
| --- | --- | --- |
| `AudioCategorySFX` | Effects | `effects` |
| `AudioCategoryVOCGeneral` | Voice | `voice` |
| `AudioCategoryMUS` | Music | `music` |
| `AudioCategoryFST` | Footsteps | `footsteps` |

`_AudioCategoryMaster` is the parent master node, not another `AudioCategory`; it remains
the engine's separate master-volume factor. The decoded static and default-menu
multipliers are retained on `SoundCategory`, but issue #235 deliberately leaves the
existing master x category x source x fade gain model and its defaults unchanged.

## SOUN sound marker

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `SDSC` | FormID | optional link to an `SNDR` descriptor |

Legacy `SOUN FNAM` and `SOUN SNDD` payloads are intentionally ignored. Skyrim SE uses the
`SDSC` descriptor link, and interpreting legacy layouts is outside this decoder's scope.

## Resolution and paths

`SoundRecordStore` indexes top-level `SNDR`, `SNCT`, and `SOUN` records by FormID.
Resolving a `SOUN` first requires the marker, then its `SDSC` link, then the corresponding
descriptor. Missing markers and missing linked descriptors are distinct typed errors so
callers can report which part of the chain failed.

Each repeated `ANAM` is resolved in record order. The Creation Kit authoring form may be
relative to `Data\Sound`, already start at `Sound`, or carry a leading separator before
either root. The separator is a Windows root-relative marker rather than a drive or
volume, so the store strips it along with an outer `Data\` and otherwise prefixes
`sound\` when needed. It then applies the
[VFS canonical path rules](/formats/vfs.md): backslash separators, lowercase names, and
rejection of unsafe components. Paths carrying a `:` after normalization are discarded
as drive or volume paths. Tracks that fail normalization are discarded without changing
the order of valid tracks. The decoder and store do not start playback; later runtime
integration consumes these resolved records.

A read-only `Skyrim.esm` probe found 4951 `ANAM` entries. The old path policy retained
4641: it dropped 308 separator-led entries plus two genuine `C:` authoring-machine paths.
The separator-led entries represent 291 of the 4490 distinct filenames. With the marker
accepted and the two volume paths still rejected, 4949 entries canonicalize and 4930
resolve through the VFS; 19 name absent development assets. The change restores the
systematic path-normalization loss without weakening the safety checks.

## Defensive policy

Every decoder verifies its record FourCC. Unknown fields are skipped. `SNCT FNAM`, `PNAM`,
`VNAM`, `UNAM`, `SNDR LNAM`, `BNAM`, and `SOUN SDSC` are decoded only at their exact
documented widths; a field with another width is ignored so malformed optional metadata
cannot shift reads or crash the engine. Missing optional fields produce `nil`, empty
flags, or an empty track list.
