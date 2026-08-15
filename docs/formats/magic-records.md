---
type: File Format
title: Magic records
description: MGEF, SPEL and SCRL layout, spell cost calculation, defensive decode policy,
  and load-order resolution.
tags: [format, esm, magic, record]
timestamp: 2026-08-15T00:00:00Z
---

# Magic records

MGEF is the leaf record behind every EFID in a spell, enchantment, potion or ingredient.
OpenSky decodes the effect definition and resolves those raw links through the active plugin
load order. SPEL and SCRL, the two casting containers, are decoded here as well, with the
cost the game charges recomputed from their effect lists. ENCH and the shout family remain
later M19 work; ALCH and INGR expose the shared effect list described in
[record decoders](/formats/records.md).

## Contents

- Sources and observed data
- MGEF record fields
- DATA layout
- Enum and actor-value policy
- Load-order resolution
- SPEL and SCRL record fields
- SPIT layout
- Spell cost calculation
- SpellStore and resolved links
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

## SPEL and SCRL record fields

A spell and a scroll are the same payload: identity, a 36-byte casting header, and the
shared EFID/EFIT/CTDA effect list. A scroll adds the inventory fields any carried item has,
so `Scroll` composes the same `InventoryItemFields` decoder MISC and BOOK use.

| field | type | SPEL | SCRL |
|---|---|---|---|
| `EDID` | zstring | editor ID | editor ID |
| `OBND` | 12 bytes | `ObjectBounds` | `ObjectBounds` |
| `FULL` | lstring | display name | display name |
| `MODL`/`MODT` | zstring + bytes | not present | model path; `MODT` unread |
| `KSIZ` + `KWDA` | count + FormID array | `KeywordList` | `KeywordList` |
| `MDOB` | FormID | menu display object | menu display object |
| `ETYP` | FormID | equip-type link | equip-type link |
| `DESC` | lstring | spell description | spell description |
| `YNAM`/`ZNAM` | FormID | not present | pickup and drop sounds |
| `DATA` | 8 bytes | not present | `ItemValue` (uint32 value, float32 weight) |
| `SPIT` | 36 bytes | `SpellItemData` below | `SpellItemData` below |
| `EFID`/`EFIT`/`CTDA` | repeated run | `MagicItemEffectList` | `MagicItemEffectList` |

## SPIT layout

All integers and floats are little-endian. A zero `halfCostPerk` becomes `nil`.

| offset | type | meaning |
|---|---|---|
| `0x00` | uint32 | base cost, authoritative only under the manual-cost flag |
| `0x04` | uint32 | flags |
| `0x08` | uint32 | spell type |
| `0x0C` | float32 | charge time |
| `0x10` | uint32 | casting type |
| `0x14` | uint32 | delivery |
| `0x18` | float32 | cast duration, the minimum for a concentration spell |
| `0x1C` | float32 | range, used by the target-actor and target-location deliveries |
| `0x20` | FormID | `PERK` that halves the cost |

Flag bits: 0 manual cost calculation, 16 unknown, 17 PC start spell, 18 unknown, 19 area
effect ignores line of sight, 20 ignore resistance on SPEL and script effect always applies
on SCRL, 21 disallow absorb and reflect, 22 unknown, 23 no dual-cast modifications. The two
names on bit 20 are both exposed on `SpellFlags`, because xEdit names that bit differently
in the two records and neither name is a safe guess for the other.

Spell types are 0 spell, 1 disease, 2 power, 3 lesser power, 4 ability, 5 poison, 10
addiction and 11 voice, with `unknown(raw:)` for anything else. Casting type and delivery
reuse the MGEF vocabulary, since xEdit types them with the same `wbCastEnum` and
`wbDeliveryEnum`. Scrolls write casting type 3, which xEdit exposes as a scroll-only enum
member; `MagicEffectCastingType` therefore carries a `.scroll` case no MGEF ever uses.

## Spell cost calculation

`SpellCost` is a pure routine over the resolved effect list. One effect costs

```text
effect_base_cost * (magnitude * duration / 10) ^ 1.1
```

with three substitutions before the arithmetic: a magnitude below 1 counts as 1, a duration
of 0 counts as 10, and a concentration spell's duration counts as 10 whatever the effect
says. `effect_base_cost` is the MGEF `DATA` base cost, so the calculation is only possible
once the EFID links resolve; an unresolved link contributes nothing and is counted, which
keeps a genuinely free spell distinguishable from an unresolvable one.

UESP does not say where the fractional part goes. The load-order gate answers it by
comparing each variant against the cost vanilla stores in `SPIT` for the 1,223 records that
do not set the manual-cost flag:

| variant | records reproduced |
|---|---|
| truncate each effect, then sum | 1,091 |
| sum, then truncate | 1,024 |
| round each effect, then sum | 790 |
| sum, then round | 755 |

OpenSky implements the first. The remaining 132 disagreements are not rounding noise: they
are records whose stored value the effect list alone does not reproduce, such as
`DLC1nVampireEnhancements`, whose stored cost is far outside what its effects imply. Perk
and skill modifiers on the charged cost are M20 work and are not part of this routine; the
`PERK` link that halves a spell's cost is decoded and left unresolved.

A record with the manual-cost flag charges the authored `SPIT` value. `SpellCostResult`
still reports what the formula would have produced, so the two can be compared in an
inspector.

## SpellStore and resolved links

`RecordIndex.referenceRecordTypes` includes SPEL and SCRL. `SpellStore` holds both in one
map, in the same shape as `MagicEffectStore`: lookup by canonical `ResolvedFormID`,
case-insensitive editor-ID lookup, deterministic ordering through `RecordStoreOrdering`, and
a loader over `ActivePluginFiles`. Both record types share the store because they are the
same payload and every consumer that follows a link wants the casting header and the
resolved effects rather than the record tag; `MagicCastingRecord` keeps the two decoders
apart where the difference matters. Each entry is joined against `MagicEffectStore` and
costed once, at construction.

Two links that were decoded but unresolvable before this store existed now name their
target in record summaries: `BOOK`'s spell tome (`teaches spell Firebolt`) and `WEAP`'s
critical effect (`critical effect Firebolt`).

## Defensive policy and measured coverage

Wrong record type throws `ESMError.malformed`. A malformed individual field is tallied and
the remaining fields continue decoding. DATA shorter than 152 bytes leaves `data == nil`;
unknown fields, including currently unmodelled VMAD, increment `MagicEffectTally` rather
than disappearing silently. Unknown enum values remain in their typed `unknown(raw:)` cases.

The active-load-order gate measured 1,812 MGEF definitions, 1,812 decoded, 1,731 winning
identities, 595 unread fields, zero malformed fields and zero unknown enum values. It pins
`AlchRestoreHealth`, `AlchDamageHealth`, `AlchDamageMagicka` and `AlchDamageStamina` to
their Skyrim.esm identities.

The same gate covers SPEL and SCRL: 1,560 SPEL and 109 SCRL definitions, all decoded, into
1,452 winning spells and 104 winning scrolls. Every `SPIT` field was exactly 36 bytes. The
109 unread fields are all `MODT` on scrolls; there were no malformed fields and no unknown
spell types, casting types or deliveries. 333 records set the manual-cost flag and 1,223 do
not, of which 1,091 reproduce their stored cost exactly. The gate pins `Flames`, `Healing`
and `Firebolt` to their Skyrim.esm identities, casting types, deliveries and effect editor
IDs.

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

```text
Milestone: M19.2
Sidebar path: Library > Asset Browser > Reference records (load order) > SPEL — Spells,
and > SCRL — Scrolls
Destination id: Destination-assetBrowser
Controls exercised: AssetCategory, AssetPluginControl, AssetRecordTypeControl, AssetFilter,
AssetTable
Readout: AssetRecordInspectorStatsLabel
Deterministic tests: SpellTests, SpellStoreTests, ReferenceRecordCatalogTests,
M18AcceptancePanelTests, DestinationRegistryTests
Local A/B (optional, never committed): none
```
