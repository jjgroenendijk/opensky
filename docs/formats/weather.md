---
type: File Format
title: Weather records (WTHR, CLMT, REGN)
description: Field layouts of the weather, climate, and region records.
tags: [format, plugin, records, weather, climate, region]
---

# Weather records (WTHR, CLMT, REGN)

Three records drive the weather:

- `WTHR`: how one weather looks (colors, fog, wind, rain).
- `CLMT`: a climate, which is a list of weathers with chances, plus sunrise and sunset times.
- `REGN`: a region. It can replace the climate's weather list inside its area.

A worldspace names its climate in `WRLD CNAM`. An exterior cell names its regions in
`CELL XCLR`. See [record decoders](/formats/world-records.md) for those, and
[weather runtime](/engine/weather.md) for how the weather is picked and blended.

Reference: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format),
pages `/WTHR`, `/CLMT`, `/REGN`. `WTHR DATA` and `NAM0` were checked against xEdit
dev-4.1.5 `Core/wbDefinitionsTES5.pas` (`wbWeatherColors`, `DATA`). The UESP `DATA` list
adds up to 18 bytes, but UESP says 19. xEdit shows two Visual Effect bytes at offsets 15
and 16, where UESP shows one "unknown".

## WTHR

### NAM0: colors

An array of 16-byte entries, one per component. Each entry is four RGBX colors: sunrise,
day, sunset, night. The count is size / 16. `Skyrim.esm` has 208, 224, and 272-byte
versions (13, 14, and 17 components). Any size that is not a multiple of 16 is ignored.

Component order (UESP and xEdit `wbWeatherColors`):

| Index | Component | Index | Component |
| --- | --- | --- | --- |
| 0 | Sky upper | 9 | Effect lighting |
| 1 | Fog near | 10 | Cloud LOD diffuse |
| 2 | Unknown (cloud layer; `PNAM` wins) | 11 | Cloud LOD ambient |
| 3 | Ambient | 12 | Fog far |
| 4 | Sunlight | 13 | Sky statics |
| 5 | Sun | 14 | Water multiplier |
| 6 | Stars | 15 | Sun glare |
| 7 | Sky lower | 16 | Moon glare |
| 8 | Horizon | | |

### FNAM: fog

Eight float32 values: day near, day far, night near, night far, day power, night power, day
maximum, night maximum. An older 16-byte version has only the first four. Other sizes are
ignored.

### DATA: 19 bytes

All values are uint8.

| Offset | Meaning | Conversion |
| --- | --- | --- |
| 0 | Wind speed | / 255 |
| 1-2 | Unused | |
| 3 | Transition delta | / 255 * 0.25 |
| 4 | Sun glare | / 255 |
| 5 | Sun damage | / 255 |
| 6 | Precipitation begin fade in | / 255 |
| 7 | Precipitation end fade out | / 255 |
| 8 | Thunder begin fade in | / 255 |
| 9 | Thunder end fade out | / 255 |
| 10 | Thunder frequency | Raw. 255 is low, 15 is high |
| 11 | Classification flags | Below |
| 12-14 | Lightning RGB | / 255 |
| 15-16 | Visual effect | Not used |
| 17 | Wind direction | / 255 * 360 degrees |
| 18 | Wind direction range | / 255 * 180 degrees |

Classification: at most one of `0x01` pleasant, `0x02` cloudy, `0x04` rainy, `0x08` snow.
None set means no class. A `DATA` of another size is ignored.

### DALC: directional ambient

Four `DALC` fields, in the order sunrise, day, sunset, night. Each is 32 bytes (xEdit
`wbAmbientColors`): six RGBX colors for +X, -X, +Y, -Y, +Z, -Z, one specular RGBX, and one
float32 scale. Some community notes call the scale a Fresnel or specular power. With fewer
than four full `DALC` fields, OpenSky has no time-of-day mapping and ignores them all.

### Clouds, sounds, and links

Source: xEdit `dev-4.1.6` (commit `9fb0168`) `wbRecord(WTHR, ...)` and the `wbWeather*` helpers. A
weather has 32 cloud layers. Layer textures use the signatures `00TX` to `@0TX` (layers 0 to 16) and
`A0TX` to `O0TX` (layers 17 to 31): the first byte counts, the rest spell `0TX`.

| Field | Size | Meaning |
| --- | --- | --- |
| `LNAM` | 4 | Max cloud layers |
| `MNAM` | 4 | Precipitation, an `SPGD` ([environment shading](/formats/environment-shading.md)) |
| `NNAM` | 4 | Visual effect, an `RFCT` ([visual effects](/formats/visual-effects.md)) |
| `RNAM`, `QNAM` | 32 | Y and X speed per layer, uint8; 127 is no movement |
| `PNAM` | 512 | Color per layer: 4 times of day, RGBA bytes |
| `JNAM` | 512 | Alpha per layer: 4 floats |
| `NAM1` | 4 | Disabled layers, one bit per layer |
| `SNAM` | 8 | A sound and its type (0 default, 1 precipitation, 2 wind, 3 thunder); repeated |
| `TNAM` | 4 | A sky `STAT`; repeated |
| `IMSP` | 16 | 4 `IMGS`, one per time of day ([image spaces](/formats/image-spaces.md)) |
| `HNAM` | 16 | 4 `VOLI`, one per time of day |
| `NAM2`, `NAM3` | 16 | Sun and moon glare: 4 RGBA colors |
| `MODL` | model group | Aurora mesh |
| `DNAM`, `CNAM`, `ANAM`, `BNAM` | zstring | Older 4-layer cloud textures |
| `ONAM` | 4 | Older cloud speeds, unused |

One `PNAM` on the install is 64 bytes (4 layers), from an older form version. A `NAM0`,
`FNAM`, or `DATA` of an unknown size is tallied.

## CLMT

| Field | Meaning |
| --- | --- |
| `EDID` | Editor ID |
| `WLST` | Weather list. 12-byte entries: weather FormID, uint32 chance in percent, global FormID (0 = none) |
| `TNAM` | Timing, 6 bytes, below |
| `FNAM` | Sun texture path |
| `GNAM` | Sun glare texture path |
| `MODL` | Night sky model path. `MODT` is skipped |

The chances in `WLST` add up to 100. A `WLST` size that is not a multiple of 12 is ignored.
UESP and xEdit do not say what the global does. OpenSky's choice is on the
[weather runtime](/engine/weather.md) page.

`TNAM`: sunrise begin, sunrise end, sunset begin, sunset end (uint8 each, times 10 gives
minutes after midnight), volatility (0 to 100), and a moons byte. In the moons byte, bits
0-5 are the phase length in days, `0x40` is Masser, and `0x80` is Secunda.

## REGN

A region has data areas. Each area is an `RDAT` header followed by fields for that area.
OpenSky remembers the type of the last `RDAT` and gives the next fields to it.

| Field | Meaning |
| --- | --- |
| `EDID` | Editor ID |
| `WNAM` | Worldspace FormID |
| `RCLR` | Map color in the editor, RGBX |
| `RDAT` | 8 bytes: uint32 type, uint8 flags (`0x01` override), uint8 priority, uint16 0 |
| `RDWT` | Weather area only. 12-byte entries: weather FormID, uint32 chance in percent, global FormID (not used) |
| `RDSA` | Sound area only. 12-byte entries: sound FormID, uint32 weather conditions, float32 chance |
| `RDMO` | Region music, a `MUSC` FormID |

Area types: 2 objects, 3 weather, 4 map, 5 landscape, 6 grass, 7 sound. A short `RDAT`
drops the area.

`RDSA` details: the sound is an `SNDR` or an old `SOUN` marker. The conditions are
`0x01` pleasant, `0x02` cloudy, `0x04` rainy, `0x08` snowy, and no bits means every
weather. The chance is a weight from 0 to 1. In `Skyrim.esm` it runs from 0.01 to 1.0.

`RDMO` is read in any area, because UESP says it "can appear with RDSA under same RDAT or on
its own". A wrong size or a null link is skipped, and an earlier value stays. See
[music records](/formats/music.md).

`RDWT` or `RDSA` with a size that is not a multiple of 12, or outside its area type, is
skipped. OpenSky does not read `RPLI`, `RPLD`, `RDOT`, `RDMP`, or `RDGS`. `RDMD` comes from
Oblivion and Skyrim SE does not use it.

## Vanilla Skyrim.esm

84 `WTHR`, 6 `CLMT`, and 317 `REGN` records decode. Every `WTHR DATA` is 19 bytes. Every
weather FormID in `WLST` and `RDWT` points at a `WTHR`. 53 regions have weather areas.
