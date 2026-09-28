---
type: File Format
title: Game settings (GMST)
description: How GMST DATA is typed, which movement settings OpenSky reads, and which plugin
  wins.
tags: [format, plugin, esm, gmst, movement, load-order]
---

# Game settings (GMST)

A `GMST` record is one game setting. Its identity is its `EDID` (editor ID), not its
FormID. Two plugins can define the same setting with different FormIDs.

Sources: xEdit
[`wbGMSTUnionDecider`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
and the
[`GMST` definition](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## DATA type

The first letter of the `EDID` gives the type of `DATA`:

| Prefix | Type | DATA |
| --- | --- | --- |
| `s` | string | A uint32 string-table ID if the plugin is localized, else a zstring |
| `i` | integer | int32 |
| `f` | float | float32 |
| `b` | Boolean | uint32, must be `0` or `1` |

A record must have exactly one `EDID` and one `DATA`. A number must be exactly 4 bytes. An
unknown prefix, or a Boolean other than 0 or 1, is an error. A bad record is skipped. It
never removes a good value from an earlier plugin.

## Movement settings

The Creation Kit [settings list](https://ck.uesp.net/wiki/Category:Settings) gives these
names and defaults:

| Value | Editor ID | Units | Fallback |
| --- | --- | --- | --- |
| Walk speed | `fMoveCharWalkBase` | world units per second | 100 |
| Run speed | `fMoveCharRunBase` | world units per second | 370 |
| Step height | none found | world units | 32 |

`Skyrim.esm` has `fMoveCharWalkBase = 100`. It has no `fMoveCharRunBase`, so OpenSky uses
the documented default. No source names a step-height setting for Skyrim SE. OpenSky uses 32
and marks the source as a fallback. It does not guess a name.

In one physics step, the player moves:

```text
distance = (running ? runSpeed : walkSpeed) * fixedTimeStep
```

The player can step onto ground no higher than `feetHeight + stepHeight`, and only if the
raised capsule fits.

## Which plugin wins

Plugins follow the [load order](/formats/plugins-txt.md). A later valid `GMST` wins over an
earlier one with the same `EDID`, compared case-insensitively.

`openskycli gmst movement` prints each movement value, its units, and the plugin it came
from.
