---
type: File Format
title: Game settings (GMST)
description: Typed GMST DATA decoding, selected movement settings, load-order precedence,
  and fallback policy.
tags: [format, plugin, esm, gmst, movement, load-order]
timestamp: 2026-07-28T00:00:00Z
---

# Game settings (GMST)

A GMST record is keyed by its `EDID`; unlike ordinary overrides, its FormID is not the
setting identity. OpenSky decodes the EDID and DATA fields into `GameSetting`, then
`GameSettingStore` resolves selected values from low to high plugin priority.

The format source is xEdit's open Skyrim definitions:
[`wbGMSTUnionDecider`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
and the
[`GMST` record definition](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Typed DATA

The first EDID character chooses the exact DATA representation:

| Prefix | Value | DATA |
|---|---|---|
| `s` | string | localized `uint32` string-table ID, otherwise inline zstring |
| `i` | integer | signed little-endian `int32` |
| `f` | floating point | little-endian IEEE-754 `float32` |
| `b` | Boolean | little-endian `uint32`, exactly `0` or `1` |

EDID and DATA are each required exactly once. EDID and inline strings must consume their
whole fields. Numeric values require exactly four bytes; unknown prefixes and Boolean values
outside zero and one throw `GameSettingError`. A malformed record is skipped by the store
and cannot erase a previously valid value.

## Movement settings and units

The Creation Kit's open
[settings catalog](https://ck.uesp.net/wiki/Category:Settings) identifies these movement
settings and defaults:

| Controller value | Editor ID | Units | Missing/invalid fallback |
|---|---|---|---:|
| Walk speed | `fMoveCharWalkBase` | world units/second | 100 |
| Run speed | `fMoveCharRunBase` | world units/second | 370 |
| Step height | no confirmed Skyrim SE GMST | world units | 32 |

The installed Skyrim SE data was probed read-only on 2026-07-28. `Skyrim.esm` contains a
valid `fMoveCharWalkBase = 100` GMST. It contains no `fMoveCharRunBase`, so OpenSky uses the
documented engine default. Neither the open definitions nor the installed official plugins
confirmed a step-height GMST Editor ID; OpenSky retains its 32-unit fallback and labels that
source explicitly rather than guessing a name.

For one fixed physics substep, horizontal distance is:

```text
distance = (running ? runSpeed : walkSpeed) * fixedTimeStep
```

The step solver accepts support no higher than `feetHeight + stepHeight` and separately
checks full raised-capsule clearance.

## Selected load order and override policy

`PluginLoadOrder` resolves installed official masters first, then installed `Skyrim.ccc`
entries, then starred active entries from
`~/Library/Application Support/Skyrim Special Edition/plugins.txt`. Names resolve
case-insensitively to the spelling in `Data/`; missing and duplicate entries are skipped.
Within that ordered set, later valid GMST records win by case-insensitive EDID even when
their FormIDs differ.

This is intentionally a selected GMST consumer, not the engine-wide plugin merge promised by
issue #73. World, cell, asset, archive, and FormID resolution still use their existing
single-plugin or provisional paths.

## Verification

`GameSettingTests` covers float, integer, Boolean, inline/localized string, wrong sizes,
unknown prefixes, invalid Boolean values, missing/duplicate fields, and trailing bytes.
`GameSettingStoreTests` covers missing settings, malformed later records, EDID-based override
precedence, and movement fallbacks. `PluginLoadOrderTests` covers official, Creation Club,
starred active, absent, duplicate, and case-insensitive entries.

`openskycli gmst movement` is the read-only real-data surface. It prints the resolved
walk/run/step value, units, and winning source for every controller input.
