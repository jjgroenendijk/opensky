---
type: File Format
title: Message records
description: Skyrim SE MESG messages with their buttons.
tags: [format, plugin, ui]
---

# Message records

`MESG` is a notification or a message box with buttons. Loading screens (`LSCR`) are on
the [loading screen records](/formats/loading-screens.md) page.

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

How OpenSky builds the text and shows it is on the [messages](/engine/messages.md) page.
