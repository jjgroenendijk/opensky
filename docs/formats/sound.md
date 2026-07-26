---
type: File Format
title: Sound records
description: Skyrim SE SNDR and SOUN fields, parameters, links, and VFS path resolution.
tags: [format, plugin, audio, sound]
timestamp: 2026-07-26T00:00:00Z
---

# Sound records

OpenSky decodes `SNDR` sound descriptors and `SOUN` sound markers from the
[ESM container](/formats/esm.md). A marker names one descriptor; the descriptor supplies
the ordered track paths and playback metadata that later runtime work can consume.

The field inventory follows the UESP
[`SNDR`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR) and
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

## SOUN sound marker

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `SDSC` | FormID | optional link to an `SNDR` descriptor |

Legacy `SOUN FNAM` and `SOUN SNDD` payloads are intentionally ignored. Skyrim SE uses the
`SDSC` descriptor link, and interpreting legacy layouts is outside this decoder's scope.

## Resolution and paths

`SoundRecordStore` indexes top-level `SNDR` and `SOUN` records by FormID. Resolving a
`SOUN` first requires the marker, then its `SDSC` link, then the corresponding descriptor.
Missing markers and missing linked descriptors are distinct typed errors so callers can
report which part of the chain failed.

Each repeated `ANAM` is resolved in record order. The Creation Kit authoring form may be
relative to `Data\Sound` or already start at `Sound`; the store strips an outer `Data\`
and otherwise prefixes `sound\` when needed. It then applies the
[VFS canonical path rules](/formats/vfs.md): backslash separators, lowercase names, and
rejection of unsafe components. Absolute authoring-machine paths are also discarded.
Tracks that fail normalization are discarded without changing the order of valid tracks.
The decoder and store do not start playback; later runtime integration consumes these
resolved records.

## Defensive policy

Every decoder verifies its record FourCC. Unknown fields are skipped. `LNAM`, `BNAM`, and
`SDSC` are decoded only at their exact documented widths; a field with another width is
ignored so malformed optional metadata cannot shift reads or crash the engine. Missing
optional fields produce `nil` or an empty track list.
