---
type: File Format
title: Skyrim INI settings
description: How OpenSky reads Skyrim INI files, which file wins, and which keys it uses.
tags: [format, ini, config, localization, lod]
---

# Skyrim INI settings

OpenSky reads the Skyrim INI files as settings. It never writes them.

Section names and key names are case-insensitive. Comments and blank lines are skipped. Text
uses the engine-wide [string decoding](/decisions/string-decoding.md) rules. When one file
sets a key twice, the last value wins.

## Which file wins

Files are layered from low to high priority:

1. `Skyrim_Default.ini` in the install.
2. `SkyrimPrefs.ini` in the install root.
3. `Skyrim/SkyrimPrefs.ini`, the launcher profile.
4. `Skyrim.ini`: the install root, then the profile copy.
5. `SkyrimCustom.ini`: the install root, then the profile copy.
6. An OpenSky override, stored in the OpenSky user defaults.

A missing file or key falls through to the next lower file. A value that does not parse as
its type also falls through. Each setting remembers the file that supplied it, so the app can
show the source.

## Language

`[General] sLanguage` picks the language part of a string table path, for example
`Strings/Skyrim_french.strings`. Only `Skyrim.ini` and `SkyrimCustom.ini` are read for it.

The value is trimmed and lowercased. It must be one file-name-safe segment. A missing or
invalid value becomes `english`. In the app, Settings shows the language and its source. An
override there reloads every string table at once.

## Terrain distances

OpenSky reads four keys from `[TerrainManager]`:

| Key | Use |
| --- | --- |
| `fBlockLevel0Distance` | Outer distance of LOD level 4 terrain and objects |
| `fBlockLevel1Distance` | Outer distance of LOD level 8 terrain and objects |
| `fBlockMaximumDistance` | Outer distance of the far terrain |
| `fTreeLoadDistance` | Outer distance of tree billboards |

All four must be finite and positive, with level 0 <= level 1 <= maximum. Otherwise all four
use the defaults 35000, 70000, 250000, and 75000 world units. The sidebar writes all four
overrides together. `Use Skyrim INI` clears them.

Source for what each distance means: STEP
[SkyrimPrefs INI, TerrainManager](https://stepmodifications.org/wiki/Guide%3ASkyrimPrefs_INI/TerrainManager).
