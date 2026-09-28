---
type: File Format
title: Magic records
description: MGEF, SPEL, and SCRL layouts, and the spell cost formula and its rounding.
tags: [format, esm, magic, record]
---

# Magic records (MGEF, SPEL, SCRL)

- `MGEF`, a magic effect, is the leaf behind every `EFID` in a spell, enchantment, potion, or
  ingredient.
- `SPEL` is a spell and `SCRL` is a scroll. Both are casting containers with an effect list.
- `ENCH` is an enchantment. It is on the [enchantment records](/formats/enchantment-records.md)
  page.

Potions and ingredients (`ALCH`, `INGR`) use the same effect list (see
[records](/formats/records.md)). Shouts and equip slots are on the
[shout and equip records](/formats/shout-records.md) page. The runtime is on the
[magic](/engine/magic.md) page.

Sources: UESP [MGEF](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF), SPEL, and SCRL
pages; xEdit `dev-4.1.6` `Core/wbDefinitionsTES5.pas`. xEdit gives the field order,
flags, enum names, and link types. UESP gives the byte offsets and the fixed 152-byte size of
`MGEF DATA`.

## MGEF fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `MDOB` | FormID | Menu display object |
| `KSIZ`, `KWDA` | count, FormID list | Keywords |
| `DATA` | 152 bytes | Below |
| `ESCE` | FormID, repeats | Counter effects |
| `SNDD` | 8-byte entries | uint32 sound kind and `SNDR` link |
| `DNAM` | lstring | Description |
| `CTDA`, `CITC`, `CIS1`, `CIS2` | conditions | The effect's own conditions |
| `VMAD` | varies | Not read |

An empty `SNDD` is an empty list. A `SNDD` whose size is not a multiple of 8 is malformed.

## MGEF DATA (152 bytes)

Little-endian. Actor values are signed indices, and -1 means none. A zero FormID means no link.

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint32 | Flags |
| `0x04` | float32 | Base cost |
| `0x08` | FormID | Associated item. Its type depends on the archetype |
| `0x0C` | int32 | Magic skill actor value |
| `0x10` | int32 | Resistance actor value |
| `0x14` | uint16 + 2 | Counter effect count, padding |
| `0x18` | FormID | Casting light |
| `0x1C` | float32 | Taper weight |
| `0x20` | FormID | Hit shader |
| `0x24` | FormID | Enchant shader |
| `0x28` | uint32 | Minimum skill level |
| `0x2C` | uint32 | Spellmaking area |
| `0x30` | float32 | Casting time |
| `0x34` | float32 | Taper curve |
| `0x38` | float32 | Taper duration |
| `0x3C` | float32 | Second actor value weight |
| `0x40` | uint32 | Archetype |
| `0x44` | int32 | Primary actor value |
| `0x48` | FormID | Projectile |
| `0x4C` | FormID | Explosion |
| `0x50` | uint32 | Casting type |
| `0x54` | uint32 | Delivery |
| `0x58` | int32 | Second actor value |
| `0x5C` | FormID | Casting art |
| `0x60` | FormID | Hit effect art |
| `0x64` | FormID | Impact data set |
| `0x68` | float32 | Skill usage multiplier |
| `0x6C` | FormID | Dual cast data |
| `0x70` | float32 | Dual cast scale |
| `0x74` | FormID | Enchant art |
| `0x78` | FormID | Hit visuals |
| `0x7C` | FormID | Enchant visuals |
| `0x80` | FormID | Equip ability |
| `0x84` | FormID | Image space modifier |
| `0x88` | FormID | Perk to apply |
| `0x8C` | uint32 | Casting sound level |
| `0x90` | float32 | Script effect AI score |
| `0x94` | float32 | Script effect AI delay |

Named flags (xEdit bits with a clear meaning): hostile, recover, detrimental, snap to navmesh,
no hit event, dispel with keywords, no duration, no magnitude, no area, effects persist, gory
visuals, hide in UI, no recast, power affects magnitude, power affects duration, painless, no
hit effect, no death dispel. Other bits are kept.

Archetypes are the xEdit values 0 to 46. Casting types: constant effect, fire and forget,
concentration. Deliveries: self, touch, aimed, target actor, target location. Unknown values
are kept raw.

The actor value fields index the one actor value table (see
[actor values](/engine/actor-values.md)). Example: 24 is Health, 44 is Resist Magic.

In vanilla every `MGEF DATA` is exactly 152 bytes, and there are no unknown archetypes,
casting types, or deliveries.

## SPEL and SCRL fields

A spell and a scroll hold the same payload: identity, a 36-byte `SPIT` header, and the effect
list. A scroll adds the fields of any carried item.

| Field | Type | SPEL | SCRL |
| --- | --- | --- | --- |
| `EDID` | zstring | Editor ID | Editor ID |
| `OBND` | 12 bytes | Bounds | Bounds |
| `FULL` | lstring | Name | Name |
| `MODL`, `MODT` | zstring, bytes | - | Model path. `MODT` not read |
| `KSIZ`, `KWDA` | keywords | Keywords | Keywords |
| `MDOB` | FormID | Menu display object | Menu display object |
| `ETYP` | FormID | Equip slot | Equip slot |
| `DESC` | lstring | Description | Description |
| `YNAM`, `ZNAM` | FormID | - | Pickup and drop sounds |
| `DATA` | 8 bytes | - | uint32 value, float32 weight |
| `SPIT` | 36 bytes | Below | Below |
| `EFID`, `EFIT`, `CTDA` | effect list | Effects | Effects |

## SPIT (36 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint32 | Base cost. Used only with the manual cost flag |
| `0x04` | uint32 | Flags |
| `0x08` | uint32 | Spell type |
| `0x0C` | float32 | Charge time |
| `0x10` | uint32 | Casting type |
| `0x14` | uint32 | Delivery |
| `0x18` | float32 | Cast duration. The minimum for a concentration spell |
| `0x1C` | float32 | Range, for target actor and target location |
| `0x20` | FormID | `PERK` that halves the cost |

Flag bits: 0 manual cost, 16 unknown, 17 player start spell, 18 unknown, 19 area effect ignores
line of sight, 20 (see below), 21 no absorb or reflect, 22 unknown, 23 no dual-cast changes.
xEdit names bit 20 "ignore resistance" on `SPEL` and "script effect always applies" on `SCRL`.
OpenSky exposes both names, because neither is a safe guess for the other record.

Spell types: 0 spell, 1 disease, 2 power, 3 lesser power, 4 ability, 5 poison, 10 addiction,
11 voice. Casting type and delivery use the `MGEF` values. Scrolls use casting type 3, a
scroll-only value that no `MGEF` uses.

## Spell cost

One effect costs:

```text
effect_base_cost * (magnitude * duration / 10) ^ 1.1
```

Before the math: a magnitude below 1 counts as 1, a duration of 0 counts as 10, and a
concentration spell's duration always counts as 10. The base cost is the `MGEF DATA` base cost.
An effect whose `MGEF` does not resolve adds nothing, and is counted. So a free spell and an
unresolvable spell look different.

UESP does not say how to round. The vanilla stored costs answer it. For the spells without the
manual cost flag, each rounding choice was compared with the stored `SPIT` cost:

| Rounding | Matches |
| --- | --- |
| Truncate each effect, then add | about 89% |
| Add, then truncate | about 84% |
| Round each effect, then add | about 65% |
| Add, then round | about 62% |

OpenSky truncates each effect, then adds. The spells that still differ are not rounding
errors. Their stored cost does not follow from their effects at all. Example:
`DLC1nVampireEnhancements` stores a cost far from what its effects give.

With the manual cost flag, the spell costs the stored `SPIT` value. OpenSky still computes the
formula value, so an inspector can show both.

Perk and skill changes to the cost are applied later, at cast time (see [perks](/engine/perks.md)).

## Bad input

A wrong record type is an error. A broken field is counted, and the other fields still decode.
An `MGEF DATA` shorter than 152 bytes leaves the data empty. Unknown fields are counted. Unknown
enum values are kept raw.
