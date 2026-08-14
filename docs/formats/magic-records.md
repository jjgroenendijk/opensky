---
type: File Format
title: Magic records
description: MGEF magic-effect layout, defensive decode policy, and load-order resolution.
tags: [format, esm, magic, record]
timestamp: 2026-08-14T00:00:00Z
---

# Magic records

MGEF is the leaf record behind every EFID in a spell, enchantment, potion or ingredient.
OpenSky decodes the effect definition and resolves those raw links through the active plugin
load order. Container records such as SPEL and ENCH remain later M19 work; ALCH and INGR
already expose the shared effect list described in [record decoders](/formats/records.md).

## Contents

- Sources and observed data
- MGEF record fields
- DATA layout
- Enum and actor-value policy
- Load-order resolution
- Defensive policy and measured coverage
- Verification surface

## Sources and observed data

The layout is from UESP
[`Skyrim Mod:Mod File Format/MGEF`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF)
and xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`, `wbRecord(MGEF, 'Magic Effect',
[...])`. The xEdit definition supplies the field ordering, flags, enum vocabulary and link
types; UESP supplies the byte offsets and fixed `struct[152]` size.

The env-gated real-data test checked all 1,812 MGEF definitions in this machine's active
load order. Every DATA field was exactly 152 bytes. SNDD was observed as a packed list of
8-byte entries with total sizes 0, 8, 16, 24, 32 or 40 bytes; 679 definitions carried the
valid empty form. No decoded DATA used an unknown archetype, casting type or delivery value.

## MGEF record fields

| field | type | OpenSky value |
|---|---|---|
| `EDID` | zstring | editor ID |
| `FULL` | lstring | display name |
| `MDOB` | FormID | menu display object |
| `KSIZ` + `KWDA` | count + FormID array | `KeywordList` |
| `DATA` | 152 bytes | `MagicEffectData` below |
| `ESCE` | repeated FormID | counter effects |
| `SNDD` | packed 8-byte entries | uint32 sound kind + SNDR link |
| `DNAM` | lstring | magic-item description |
| `CTDA`/`CITC`/`CIS1`/`CIS2` | condition run | effect's own `ConditionList` |
| `VMAD` | variable | tallied as unread until script attachments need it here |

An empty SNDD field is an empty list. A nonempty field whose byte count is not divisible by
8 is malformed and is tallied without discarding the rest of the MGEF.

## DATA layout

All integers and floats are little-endian. Actor-value words are signed; `-1` is the
no-actor-value sentinel. A zero FormID becomes `nil` while every nonzero link stays raw for
plugin-relative resolution by its consumer.

| offset | type | xEdit name / OpenSky value |
|---:|---|---|
| `0x00` | uint32 | flags |
| `0x04` | float32 | base cost |
| `0x08` | FormID | associated item; its record type depends on archetype |
| `0x0C` | int32 | magic skill actor-value index |
| `0x10` | int32 | resistance actor-value index |
| `0x14` | uint16 + 2 unused | counter-effect count and padding |
| `0x18` | FormID | casting light |
| `0x1C` | float32 | taper weight |
| `0x20` | FormID | hit shader |
| `0x24` | FormID | enchant shader |
| `0x28` | uint32 | minimum skill level |
| `0x2C` | uint32 | spellmaking area |
| `0x30` | float32 | casting time |
| `0x34` | float32 | taper curve |
| `0x38` | float32 | taper duration |
| `0x3C` | float32 | second actor-value weight |
| `0x40` | uint32 | archetype |
| `0x44` | int32 | related/primary actor-value index |
| `0x48` | FormID | projectile |
| `0x4C` | FormID | explosion |
| `0x50` | uint32 | casting type |
| `0x54` | uint32 | delivery |
| `0x58` | int32 | second actor-value index |
| `0x5C` | FormID | casting art |
| `0x60` | FormID | hit-effect art |
| `0x64` | FormID | impact data set |
| `0x68` | float32 | skill-usage multiplier |
| `0x6C` | FormID | dual-cast art/data |
| `0x70` | float32 | dual-cast scale |
| `0x74` | FormID | enchant art |
| `0x78` | FormID | hit visuals |
| `0x7C` | FormID | enchant visuals |
| `0x80` | FormID | equip ability |
| `0x84` | FormID | image-space modifier |
| `0x88` | FormID | perk to apply |
| `0x8C` | uint32 | casting sound level |
| `0x90` | float32 | script-effect AI score |
| `0x94` | float32 | script-effect AI delay |

The flag names implemented now are the xEdit bits with stated semantics: hostile, recover,
detrimental, snap to navmesh, no hit event, dispel with keywords, no duration, no magnitude,
no area, effects persist, gory visuals, hide in UI, no recast, power affects magnitude,
power affects duration, painless, no hit effect and no death dispel. Unknown flag bits stay
in the `OptionSet.rawValue`.

## Enum and actor-value policy

`MagicEffectArchetype` carries all xEdit values 0 through 46. Casting type carries constant
effect, fire and forget, and concentration; delivery carries self, touch, aimed, target
actor and target location. Each enum has `unknown(raw:)`, so a mod-authored value remains
diagnosable instead of being coerced to a vanilla case.

Magic skill, resistance, related actor value and second actor value are indices into the
single xEdit-derived table already held by `ActorValueIdentity`. Inspector text uses that
table, for example index 24 is `Health` and 44 is `Resist Magic`; no second name table is
maintained by the magic subsystem.

## Load-order resolution

`RecordIndex.referenceRecordTypes` includes MGEF because it is reference data used both by
stores and the Asset Browser. `MagicEffectStore` follows the same shape as `KeywordStore`:
lookup by canonical `ResolvedFormID`, case-insensitive editor-ID lookup, and a convenience
loader over `ActivePluginFiles`. A later valid override wins, while `RecordIndex.decodeIndexed`
can fall back to an earlier valid definition if an override's MGEF body is malformed.

`MagicItemEffect.resolved(fromPlugin:using:)` is the consumer seam. It resolves the EFID
relative to the plugin that carried the ALCH or INGR and returns the winning effect with its
name, archetype and actor-value indices. Item summaries print those resolved names when the
store context is present; dangling links remain explicit `[UNRESOLVED]` values.

## Defensive policy and measured coverage

Wrong record type throws `ESMError.malformed`. A malformed individual field is tallied and
the remaining fields continue decoding. DATA shorter than 152 bytes leaves `data == nil`;
unknown fields, including currently unmodelled VMAD, increment `MagicEffectTally` rather
than disappearing silently. Unknown enum values remain in their typed `unknown(raw:)` cases.

The active-load-order gate measured 1,812 definitions, 1,812 decoded, 1,731 winning
identities, 595 unread fields, zero malformed fields and zero unknown enum values. It pins
`AlchRestoreHealth`, `AlchDamageHealth`, `AlchDamageMagicka` and `AlchDamageStamina` to
their Skyrim.esm identities.

## Verification surface

```text
Milestone: M19.1
Sidebar path: Library > Asset Browser > Reference records (load order) > MGEF — Magic effects
Destination id: Destination-assetBrowser
Controls exercised: AssetCategory, AssetPluginControl, AssetRecordTypeControl, AssetFilter,
AssetTable
Readout: AssetRecordInspectorStatsLabel
Deterministic tests: MagicEffectTests, MagicEffectStoreTests, ReferenceRecordCatalogTests,
M18AcceptancePanelTests, DestinationRegistryTests
Local A/B (optional, never committed): none
```
