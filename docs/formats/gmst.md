---
type: File Format
title: Game settings (GMST)
description: Typed GMST DATA, the movement settings, and which plugin wins.
tags: [format, plugin, esm, gmst, movement, load-order]
---

# Game settings (GMST)

A `GMST` record is one game setting. Its identity is its `EDID` (editor ID), not its
FormID. When two plugins have a GMST with the same `EDID`, the later plugin in load order
wins, even when the FormIDs differ. `EDID` matching ignores case.

Sources: xEdit
[`wbGMSTUnionDecider`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
and the
[`GMST` record definition](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Typed DATA

The first letter of the `EDID` sets the type of `DATA`:

| Prefix | Type | `DATA` |
| --- | --- | --- |
| `s` | string | uint32 string-table ID if the plugin is localized, else a zstring |
| `i` | integer | int32 |
| `f` | float | float32 |
| `b` | Boolean | uint32, only `0` or `1` |

`EDID` and `DATA` must each appear once. Numbers must be exactly 4 bytes. OpenSky skips a
bad record. A bad record never removes a good value from an earlier plugin.

## Movement settings

The Creation Kit [settings list](https://ck.uesp.net/wiki/Category:Settings) names these
settings:

| Value | Editor ID | Units | Fallback |
| --- | --- | --- | --- |
| Walk speed | `fMoveCharWalkBase` | world units per second | 100 |
| Run speed | `fMoveCharRunBase` | world units per second | 370 |
| Step height | none found | world units | 32 |

`Skyrim.esm` has `fMoveCharWalkBase = 100`. It has no `fMoveCharRunBase`, so OpenSky uses
the documented default. No source and no official plugin gives a GMST for step height. So
OpenSky uses 32 and labels it as its own fallback. It does not guess a name.

In one physics step, the player moves `(running ? runSpeed : walkSpeed) * fixedTimeStep`.

`openskycli gmst movement` prints each value, its units, and which plugin set it.
