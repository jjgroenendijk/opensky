---
type: File Format
title: Message and load screen records
description: Skyrim SE MESG messages with their buttons and LSCR loading screens.
tags: [format, plugin, ui]
---

# Message and load screen records

`MESG` is a notification or a message box with buttons. `LSCR` is a loading screen: a
model, a tip, and the conditions for showing it.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## MESG

| Field | Type | Meaning |
| --- | --- | --- |
| `DESC` | lstring | Message text |
| `FULL` | lstring | Title |
| `INAM` | FormID | Leftover icon link, always null |
| `QNAM` | FormID | Owner `QUST` |
| `DNAM` | uint32 | Flags: 0x01 message box, 0x02 auto display |
| `TNAM` | uint32 | Seconds a notification shows |
| `ITXT` | lstring | Button text; opens a button |
| `CTDA` | condition | After an `ITXT`: a condition of that button |

## LSCR

| Field | Type | Meaning |
| --- | --- | --- |
| `DESC` | lstring | Tip text |
| `CTDA` | conditions | When the screen may show |
| `NNAM` | FormID | `STAT` shown behind the text |
| `SNAM` | float | Initial scale |
| `RNAM` | 3 int16 | Initial rotation, degrees |
| `ONAM` | 2 int16 | Rotation offset min and max |
| `XNAM` | 3 floats | Initial translation |
| `MOD2` | zstring | Camera path file |

Header flag 0x400 shows the screen in the main menu.
