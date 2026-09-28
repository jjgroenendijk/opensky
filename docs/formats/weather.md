---
type: File Format
title: Weather records (WTHR, CLMT, REGN)
description: WTHR color layers, fog, DATA, and directional ambient; CLMT weather lists and
  timing; REGN data areas for weather, sound, and music.
tags: [format, esm, records, weather, climate, region]
---

# Weather records (WTHR, CLMT, REGN)

- `WTHR` is one weather: its sky colors, fog, wind, and light.
- `CLMT` is a climate: a list of weathers with chances, and the sun times.
- `REGN` is a region. It can replace the climate's weather list for part of a world.

A worldspace names its climate with `WRLD` `CNAM`. An exterior cell names its regions with
`CELL` `XCLR` (see [world records](/formats/world-records.md)). The runtime is on the
[weather](/engine/weather.md) page.

Sources: UESP [WTHR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WTHR),
[CLMT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLMT), and
[REGN](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN); xEdit
`Core/wbDefinitionsTES5.pas` (`wbWeatherColors`, `wbAmbientColors`, WTHR `DATA`).

UESP's `DATA` list adds up to 18 bytes, but it says the field is 19. xEdit shows two "Visual
Effect" bytes at offsets 15 and 16, where UESP shows one "unknown". OpenSky follows xEdit.

## WTHR NAM0: color layers

An array of 16-byte entries, one per sky part. Each entry is four RGBX colors: sunrise, day,
sunset, night. The X byte is padding. The number of parts is the size / 16. Vanilla has 13, 14,
and 17 parts. A size that is not a multiple of 16 gives no colors.

Order (UESP and xEdit): 0 upper sky, 1 near fog, 2 unknown (cloud layer, not used, `PNAM` sets
cloud colors), 3 ambient, 4 sunlight, 5 sun, 6 stars, 7 lower sky, 8 horizon, 9 effect
lighting, 10 cloud LOD diffuse, 11 cloud LOD ambient, 12 far fog, 13 sky statics, 14 water
multiplier, 15 sun glare, 16 moon glare.

## WTHR FNAM: fog

Eight floats: day near, day far, night near, night far, day power, night power, day maximum,
night maximum. An older 16-byte form has only the first four.

## WTHR DATA (19 bytes)

All bytes are uint8.

| Offset | Meaning | Scale |
| --- | --- | --- |
| 0 | Wind speed | / 255 |
| 1, 2 | Unused | |
| 3 | Transition delta | / 255 * 0.25 |
| 4 | Sun glare | / 255 |
| 5 | Sun damage | / 255 |
| 6, 7 | Precipitation fade in, fade out | / 255 |
| 8, 9 | Thunder fade in, fade out | / 255 |
| 10 | Thunder frequency | Raw. 255 is rare, 15 is often |
| 11 | Classification flags | Below |
| 12-14 | Lightning color RGB | / 255 |
| 15, 16 | Visual effect | Not used |
| 17 | Wind direction | / 255 * 360 degrees |
| 18 | Wind direction range | / 255 * 180 degrees |

Classification (low 4 bits, at most one set): `0x01` pleasant, `0x02` cloudy, `0x04` rainy,
`0x08` snow. None set means no precipitation. Every vanilla `DATA` is 19 bytes.

## WTHR DALC: directional ambient

Four `DALC` fields, in the order sunrise, day, sunset, night. Each is a 32-byte
`wbAmbientColors`: six RGBX colors, one per direction (X+, X-, Y+, Y-, Z+, Z-), one specular
RGBX color, and a float xEdit calls "Scale". Some community notes call it a specular power.

With fewer than four full `DALC` fields there is no directional ambient, because no time of day
can be matched to them.

Not read: cloud textures (`00TX` to `L0TX`), cloud layer speeds, colors, and alphas (`LNAM`,
`MNAM`, `NNAM`, `RNAM`, `QNAM`, `PNAM`, `JNAM`), `NAM1` disabled layers, sounds (`SNAM`,
`TNAM`), image spaces (`IMSP`), and statics and spells.

## CLMT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `WLST` | 12 bytes, repeats | Weather FormID, uint32 chance in percent, `GLOB` FormID (0 is none) |
| `TNAM` | 6 bytes | Timing, below |
| `FNAM`, `GNAM` | zstring | Sun and sun glare textures |
| `MODL` | zstring | Night sky model |

The chances add up to 100. Neither UESP nor xEdit says what the game does with the global. OpenSky
lets the global replace the chance when it resolves. This is flagged on the
[weather](/engine/weather.md) page.

`TNAM`: sunrise begin, sunrise end, sunset begin, sunset end (uint8, times 10 minutes after
midnight), volatility (0 to 100), and a moons byte. The moons byte: bits 0 to 5 are the phase
length in days, `0x40` Masser, `0x80` Secunda.

## REGN

A region holds data areas. Each area is an `RDAT` header, then the fields for that area. The
decoder remembers the last `RDAT` type and gives the next fields to it.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `WNAM` | FormID | Worldspace |
| `RCLR` | RGBX | Editor map color |
| `RDAT` | 8 bytes | uint32 type, uint8 flags (`0x01` override), uint8 priority, uint16 0 |
| `RDWT` | 12 bytes, repeats | Weather area only: weather, uint32 chance, global (not used) |
| `RDSA` | 12 bytes, repeats | Sound area only: sound, uint32 weather states, float32 chance |
| `RDMO` | FormID | Region music (`MUSC`) |

Area types: 2 objects, 3 weather, 4 map, 5 land, 6 grass, 7 sound.

`RDSA` weather states: `0x01` pleasant, `0x02` cloudy, `0x04` rainy, `0x08` snowy. No bit set
means every state. The chance is a weight from 0 to 1. In vanilla it runs from 0.01 to 1.0. The
sound is an `SNDR` or an old `SOUN`.

`RDMO` is accepted in any area, because UESP says it "can appear with RDSA under same RDAT or on
its own". A wrong size or a zero link is skipped. See [music](/formats/music.md).

Other area fields (`RPLI`, `RPLD`, `RDOT`, `RDMP`, `RDGS`) are skipped. `RDMD` is left over from
Oblivion and SSE does not use it.

In vanilla, every weather link in every `CLMT` and `REGN` names a `WTHR`.
