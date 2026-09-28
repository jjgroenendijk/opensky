---
type: File Format
title: Skyrim INI settings
description: How OpenSky reads Skyrim INI files - file order, language selection, and the
  terrain distance keys.
tags: [format, ini, config, localization, lod]
---

# Skyrim INI settings

OpenSky reads the Skyrim INI files as settings. It never writes them. Section and key names
are case-insensitive. Text encoding follows the
[string decoding](/decisions/string-decoding.md) policy.

## File order

When a key appears twice in one file, the last value wins. Across files, a later file in
this list wins over an earlier one:

1. `Skyrim_Default.ini` in the install.
2. `SkyrimPrefs.ini` in the install root.
3. `Skyrim/SkyrimPrefs.ini`, the launcher profile.
4. `Skyrim.ini`: first the install root, then the profile.
5. `SkyrimCustom.ini`: first the install root, then the profile.
6. The OpenSky override, stored in OpenSky user defaults.

A missing file or key falls through to the file before it. A value with the wrong type (for
example `abc` for a number) also falls through.

## Language

`[General] sLanguage` picks the language part of a string-table path, for example
`Strings/Skyrim_french.strings`. OpenSky reads it from `Skyrim.ini` and `SkyrimCustom.ini`
only. The value is trimmed and lowercased. It must be one segment that is safe in a file
name. A missing or bad value gives `english`.

## Terrain distances

OpenSky reads four `[TerrainManager]` keys. The STEP guide
[`[TerrainManager]`](https://stepmodifications.org/wiki/Guide%3ASkyrimPrefs_INI/TerrainManager)
explains what each one does in Skyrim.

| Key | Use in OpenSky |
| --- | --- |
| `fBlockLevel0Distance` | Outer distance of LOD level 4 terrain and objects |
| `fBlockLevel1Distance` | Outer distance of LOD level 8 terrain and objects |
| `fBlockMaximumDistance` | Outer distance of far terrain |
| `fTreeLoadDistance` | Outer distance of tree billboards |

All four must be finite and positive, with level 0 <= level 1 <= maximum. If one is bad,
all four use the defaults 35000, 70000, 250000, and 75000 world units. The sidebar writes
all four OpenSky overrides together.
