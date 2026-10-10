---
type: Subsystem
title: Player settings
description: How the player's settings are stored, where their defaults come from, and which
  system each one reaches.
tags: [engine, settings, ui, menu]
---

# Player settings

One store owns every player setting at runtime. The System menu Settings page, the sidebar,
and the Controls page read and write the same store. A write is clamped, saved, and sent to
the system that uses it at once.

## Storage and defaults

- The values live in `~/Library/Application Support/OpenSky/Settings.json`. OpenSky never
  writes the game's INI files.
- A missing value uses the catalog default. The catalog takes its defaults from the
  install's `Skyrim/SkyrimPrefs.ini` where a key has a valid value, for example
  `fAudioMasterVolume`, `iDifficulty`, and `bCrosshairEnabled` ([INI](/formats/ini.md)).
- `fMouseHeadingSensitivity` 0.0125 is the slider middle. OpenSky picked this mapping; the
  game's own curve is not documented.
- The Save on Pause timer reads `bSaveOnPause` and `fAutosaveEveryXMins`.

## Where each value goes

| Setting | Reaches |
| --- | --- |
| Sound | Starts or stops the audio engine |
| Master and category volumes | The audio engine, again after it is rebuilt |
| Look sensitivity, invert Y | The camera input |
| Crosshair, compass, floating markers, HUD opacity | The HUD movie and the SWF layer |
| Difficulty | The combat damage multipliers, from the `fDiffMult*` GMSTs |
| Key bindings | The game view's key table ([control map](/formats/controlmap.md)) |
| Save on rest, wait, travel, pause | The autosave policy |
| Start at title screen | Whether the session opens on the title menu |

The two subtitle settings choose which lines the HUD shows
([dialogue menu](/engine/dialogue-menu.md), "Subtitles").

## Autosaves

Autosaves rotate over three slots, `Autosave 1` to `Autosave 3`: an empty slot first,
else the oldest. Quicksave writes the slot `Quicksave`. A pause save waits until the
chosen number of minutes has passed since the last save of any kind.
