---
type: File Format
title: Loading screen records
description: Skyrim SE LSCR loading screens, and how OpenSky picks one for a destination.
tags: [format, plugin, ui]
---

# Loading screen records

`LSCR` is a loading screen: a model, a tip, and the conditions for showing it. How a screen
shows during a transition is on the [loading screens](/engine/loading-screens.md) page.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `DESC` | lstring | Tip text. A localized plugin keeps it in the `.strings` table, not `.dlstrings` |
| `CTDA` | conditions | When the screen may show |
| `NNAM` | FormID | `STAT` shown behind the text |
| `SNAM` | float | Initial scale |
| `RNAM` | 3 int16 | Initial rotation, degrees |
| `ONAM` | 2 int16 | Rotation offset min and max |
| `XNAM` | 3 floats | Initial translation |
| `MOD2` | zstring | Camera path file |

Header flag 0x400 shows the screen in the main menu.

## Selection

The game picks a random screen among those whose conditions pass. OpenSky does the same, with
these choices:

- The conditions run on the player.
- While the screen is chosen, the player's current location is the destination's `XLCN`
  location, not the location being left. A tip about Whiterun should show on the way into
  Whiterun.
- `ConditionDataResolution` gives the conditions the location store and the form lists, so
  `GetInCurrentLocation`, `GetInCurrentLocAlias`, `LocationHasKeyword`, and form-list
  conditions can pass.

## On the install

The five masters hold 371 `LSCR` records. Their conditions run on the subject 380 times and
on a reference 4 times. The most common functions are `GetInCurrentLoc` (191) and
`GetRandomPercent` (133); quest stage and global checks make up most of the rest.

With the destination's location as the current location, 237 of the 351 resolved screens pass
with no location, 254 for `WhiterunLocation` and `SolitudeLocation`, 238 for
`BleakFallsBarrowLocation`, and 247 for `WhiterunBanneredMareLocation`. Many screens have no
location condition, so a general tip can show anywhere.
