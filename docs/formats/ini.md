---
type: File Format
title: Skyrim INI settings
description: Read-only INI decode, precedence, localization, typed values, and overrides.
tags: [format, ini, config, localization, lod]
timestamp: 2026-08-14T00:00:00Z
---

# Skyrim INI settings

OpenSky reads Skyrim INI files as external config. It never edits them. Parser supports
case-insensitive section/key names, comments, blank lines, and any text encoding the
engine-wide policy covers ([string decoding](/decisions/string-decoding.md)).
Repeated values use last declaration in one file. Files layer from low to high priority:

1. install `Skyrim_Default.ini`;
2. install-root `SkyrimPrefs.ini`;
3. install `Skyrim/SkyrimPrefs.ini` launcher profile;
4. install-root then profile `Skyrim.ini`;
5. install-root then profile `SkyrimCustom.ini`;
6. complete OpenSky override stored in OpenSky user defaults.

Missing files/keys fall through. Malformed typed values also fall through to next valid
lower-priority value. A setting reports its winning filename for app inspection.

`[General] sLanguage` selects the language segment in localized plugin table paths such as
`Strings/Skyrim_french.strings`. Localization reads `Skyrim.ini` and then
`SkyrimCustom.ini`, including the install-root and `Skyrim/` profile copies. The value is
trimmed, lowercased, and accepted only when it is a single filename-safe segment. Missing
or invalid values use `english`. App Settings shows the resolved value and source, accepts
a persistent OpenSky override, and reloads all string-table consumers immediately.

The typed `[TerrainManager]` consumer reads:

| key | use |
| --- | --- |
| `fBlockLevel0Distance` | L4 terrain/object outer distance |
| `fBlockLevel1Distance` | L8 terrain/object outer distance |
| `fBlockMaximumDistance` | far terrain outer distance |
| `fTreeLoadDistance` | traditional tree billboard outer distance |

Validation requires finite positive distances, level 0 <= level 1 <= maximum. Incomplete
or invalid groups use safe defaults `35000/70000/250000/75000` world units. Sidebar writes
all four OpenSky values atomically; `Use Skyrim INI` clears them and reloads read-only files.

Semantic reference: STEP SkyrimPrefs INI
[`[TerrainManager]`](https://stepmodifications.org/wiki/Guide%3ASkyrimPrefs_INI/TerrainManager)
documents each distance's Skyrim use. INI tokenization itself is text config, not a binary
layout claim.
