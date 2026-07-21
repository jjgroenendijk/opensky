---
type: File Format
title: Weather records (WTHR, CLMT, REGN)
description: Field layouts of the weather-core records and OpenSky's engine types.
tags: [format, plugin, records, weather, climate, region]
timestamp: 2026-07-21T00:00:00Z
---

# Weather records, Skyrim SE

Record decoders over the [ESM container](/formats/esm.md) for the data-driven
weather core (milestone 7.2.1): weather visuals (WTHR), climate weather
lists + timing (CLMT), region weather overrides (REGN). Decode policy follows
[record decoders](/formats/records.md): loop fields, pick known types, skip
the rest; `ESMError.malformed` only on structurally unusable input; unknown
field sizes -> nil/skip, never guess. Impl: `opensky/Formats/ESM/Records/`
(`Weather.swift`, `Climate.swift`, `Region.swift`).

Reference: UESP "Skyrim Mod:Mod File Format" subpages `/WTHR`, `/CLMT`,
`/REGN` (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>).
WTHR DATA + NAM0 cross-checked against xEdit dev-4.1.5
`Core/wbDefinitionsTES5.pas` (wbWeatherColors, DATA) — UESP's DATA field list
sums to 18 bytes vs the stated 19; xEdit shows two Visual Effect uint8s at
offsets 15-16 that UESP collapses into one "unknown".

## WTHR — weather

Decoded fields (`Weather`):

* `EDID` — editor ID, zstring.
* `NAM0` — color layers: array of 16-byte structs, one per component, each =
  sunrise/day/sunset/night RGBX (X pad dropped, exposed 0-1 `SIMD3<Float>`).
  Component count = size/16 — skyrim.esm carries 208/224/272-byte variants
  (13/14/17 components); size not a positive multiple of 16 -> nil.
  Component order (UESP/xEdit wbWeatherColors): 0 sky-upper, 1 fog near,
  2 unknown/cloud layer (ignored, PNAM overrides), 3 ambient, 4 sunlight,
  5 sun, 6 stars, 7 sky-lower, 8 horizon, 9 effect lighting, 10 cloud LOD
  diffuse, 11 cloud LOD ambient, 12 fog far, 13 sky statics, 14 water
  multiplier, 15 sun glare, 16 moon glare.
* `FNAM` — fog distances: 8 floats (day near/far, night near/far, day pow,
  night pow, day max, night max). Legacy 16-byte variant = first 4 only
  (pow/max nil). Other sizes -> nil.
* `DATA` — 19 bytes, all uint8: wind speed (/255 -> 0-1), 2 unused,
  trans delta (/255*0.25), sun glare (/255), sun damage (/255),
  precipitation begin fade-in + end fade-out (/255), thunder begin + end
  fade (/255), thunder frequency (raw; 255 low .. 15 high), classification
  flags, lightning RGB (3 bytes, /255), 2 Visual Effect bytes (unused),
  wind direction (/255*360 deg), wind direction range (/255*180 deg).
  Classification low nibble (at most one set): 0x01 pleasant, 0x02 cloudy,
  0x04 rainy, 0x08 snow -> `Precipitation` enum; none set -> `.none`.
  Non-19-byte DATA -> nil.

Skipped (out of 7.2.1 scope): cloud textures (`00TX`..`L0TX`), cloud-layer
speeds/colors/alphas (`LNAM`/`MNAM`/`NNAM`/`RNAM`/`QNAM`/`PNAM`/`JNAM`),
`NAM1` disabled-layer bits, sounds (`SNAM`/`TNAM`), image spaces (`IMSP`),
directional ambient (`DALC`), statics/spells (`NAM2`/`NAM3`/`MODL` etc.).

## CLMT — climate

Decoded fields (`Climate`):

* `EDID` — editor ID, zstring.
* `WLST` — weather list: 12-byte structs, `formid` weather + `uint32` chance
  (percent, sums to 100) + `formid` global (0 = none). Size not multiple of
  12 -> field skipped.
* `TNAM` — timing, 6 bytes: sunrise begin/end, sunset begin/end (uint8, x10
  = minutes past midnight), volatility (0-100), moons byte (bits 0-5 phase
  length days, 0x40 Masser, 0x80 Secunda). Non-6-byte -> nil.
* `FNAM`/`GNAM` — sun / sun-glare texture paths, zstring.
* `MODL` — night-sky model path, zstring (`MODT` skipped).

## REGN — region (weather scope)

A region holds data areas, each an `RDAT` header followed by area-specific
fields streaming sequentially; the decoder tracks the last RDAT type and
binds payload fields to it. Decoded (`Region`):

* `EDID` — editor ID, zstring. `WNAM` — owning worldspace formid.
* `RCLR` — editor map color, 4-byte RGBX.
* `RDAT` — 8 bytes: `uint32` type (2 objects, 3 weather, 4 map, 5 landscape,
  6 grass, 7 sound), `uint8` flags (0x01 override), `uint8` priority,
  `uint16` 0. Short header -> area context dropped.
* `RDWT` (type-3 area only) — 12-byte structs: `formid` weather + `uint32`
  chance (percent) + `formid` global (unused, 0 = none). Size not multiple
  of 12, or outside a weather area -> skipped.

Other area payloads (`RPLI`/`RPLD`, `RDOT`, `RDMP`, `RDGS`,
`RDSA`/`RDMO`/`RDMD`) stream past untouched.

## Verification

Synthetic-fixture tests: `WeatherRecordTests`, `ClimateRecordTests`,
`RegionRecordTests`, `RecordTextDumpTests` (WTHR/CLMT/REGN decoded
summaries in CLI `record` + Asset Browser). Env-gated vanilla sweep
(`WeatherRealDataTests`, run via `tools/realtest.sh`): Skyrim.esm decodes
84 WTHR / 6 CLMT / 317 REGN with no throws; NAM0 layer counts 13:1 14:11
17:72; every WTHR DATA is 19 bytes; all 6 CLMT WLST + 175 REGN RDWT weather
references resolve to WTHR records; 53/317 regions carry weather areas.
Log: `logs/weather-sweep.log`.

Consumers: weather runtime (7.2.2) selects from CLMT/REGN lists and blends
NAM0/FNAM/DATA into the sky + fog + ambient; wind published from DATA.
