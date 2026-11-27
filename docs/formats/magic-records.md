---
type: File Format
title: Magic records
description: MGEF, SPEL, and SCRL layouts, the spell cost formula, and what the vanilla
  install contains.
tags: [format, esm, magic, record]
---

# Magic records

MGEF (magic effect) is the leaf record behind every `EFID` in a spell, scroll, enchantment,
potion, or ingredient. SPEL (spell) and SCRL (scroll) are the two casting containers. ENCH
(enchantment) is on [enchantments](/formats/enchantments.md). ALCH and
INGR use the same effect list; see [item records](/formats/item-records.md). Shouts, words of
power, leveled spells, dual-cast data, and equip slots are on
[shouts and equip slots](/formats/shouts-equip-slots.md).

Sources:

- UESP [`Skyrim Mod:Mod File Format/MGEF`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF),
  and the SPEL and SCRL pages beside it. UESP gives the byte offsets and the fixed
  sizes.
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`, `wbRecord(MGEF, 'Magic Effect', [...])` and
  the SPEL and SCRL records. xEdit gives the field order, flags, enum names, and link
  types.

All integers and floats are little-endian. A zero FormID means "no link".

## MGEF fields

| field | type | meaning |
|---|---|---|
| `EDID` | zstring | editor ID |
| `FULL` | lstring | display name |
| `MDOB` | FormID | menu display object |
| `KSIZ` + `KWDA` | count + FormID array | keywords |
| `DATA` | 152 bytes | see below |
| `ESCE` | repeated FormID | counter effects |
| `SNDD` | packed 8-byte entries | uint32 sound kind + `SNDR` link |
| `DNAM` | lstring | magic-item description |
| `CTDA`/`CITC`/`CIS1`/`CIS2` | condition run | the effect's own conditions |
| `VMAD` | variable | script attachments, decoded like other records ([scripts](/formats/vmad.md)) |

`SNDD` holds 0 to 5 entries on the vanilla install (0, 8, 16, 24, 32, or 40 bytes). An empty
`SNDD` is a valid empty list. A size that is not a multiple of 8 is malformed.

## MGEF DATA

Every vanilla `DATA` is exactly 152 bytes. Actor-value fields are signed indices into the
actor-value table (see [actor value information](/formats/actor-value-information.md)).
For example, 24 is `Health` and 44 is `Resist Magic`. The value `-1` means "no actor value".

| offset | type | meaning |
|---:|---|---|
| `0x00` | uint32 | flags |
| `0x04` | float32 | base cost |
| `0x08` | FormID | associated item; its record type depends on the archetype |
| `0x0C` | int32 | magic skill actor value |
| `0x10` | int32 | resistance actor value |
| `0x14` | uint16 + 2 unused | counter-effect count |
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
| `0x40` | uint32 | archetype, 0 to 46 |
| `0x44` | int32 | primary (related) actor value |
| `0x48` | FormID | projectile |
| `0x4C` | FormID | explosion |
| `0x50` | uint32 | casting type |
| `0x54` | uint32 | delivery |
| `0x58` | int32 | second actor value |
| `0x5C` | FormID | casting art ([`ARTO`](/formats/art-objects.md)) |
| `0x60` | FormID | hit-effect art (`ARTO`) |
| `0x64` | FormID | impact data set |
| `0x68` | float32 | skill-usage multiplier |
| `0x6C` | FormID | dual-cast data (`DUAL`) |
| `0x70` | float32 | dual-cast scale |
| `0x74` | FormID | enchant art (`ARTO`) |
| `0x78` | FormID | hit visuals |
| `0x7C` | FormID | enchant visuals |
| `0x80` | FormID | equip ability |
| `0x84` | FormID | image-space modifier |
| `0x88` | FormID | perk to apply |
| `0x8C` | uint32 | casting sound level |
| `0x90` | float32 | script-effect AI score |
| `0x94` | float32 | script-effect AI delay |

When the enchant visuals (`0x7C`, an `RFCT`) are set, their shader and art replace both the
enchant shader (`0x24`) and the enchant art (`0x74`). A weapon enchantment shows them on the weapon
in the hand that casts it, when that hand's caster starts or readies. The item must be an
enchantment that is not a constant effect, and a charged item must hold at least one use. The
shader goes on the weapon only when its own flags have bit 24 set. The costliest effect decides.

The equip ability (`0x80`) follows the casting slots: left hand, right hand, voice, and instant.
When a slot gets a spell, scroll, staff, or other casting item, the ability of each of its effects
is cast on the actor. When the item leaves its last slot, those abilities are dispelled.

The flags with known meaning are: hostile, recover, detrimental, snap to navmesh, no hit
event, dispel with keywords, no duration, no magnitude, no area, effects persist, gory
visuals, hide in UI, no recast, power affects magnitude, power affects duration, painless,
no hit effect, and no death dispel. The bit numbers are in xEdit.

What the game does with some of them:

| Bit | Name | Effect |
| --- | --- | --- |
| 3 | Snap to navmesh | A target-location cast moves its aim point to the nearest navmesh point within 32 units, or 256 for an extra-large actor |
| 4 | No hit event | Applying the effect sends no hit event to the target's scripts |
| 8 | Dispel with keywords | When the effect starts, it dispels the target's other active effects that carry one of its own keywords |
| 12 | Effects persist | Objects the effect places are persistent references, and they are cleaned up when the effect ends |
| 14 | Gory visuals | With the `bDisableAllGore` INI switch on, the hit shader and hit art do not start |
| 24 | (unnamed) | The effect is left out of the spell's cost, its charge time, and the choice of its main effect |
| 26 | Painless | The target plays no pain or hit reaction |
| 27 | No hit effect | The hit shader and hit-effect art do not start on the target |
| 28 | No death dispel | Each frame, an effect on a dying or dead actor ends unless this bit is set. This holds for every archetype, abilities too. Reanimate is the one exception: it stays while it holds the body |

A target reacts with pain only to a hostile or detrimental effect that is not painless and not
from an ability (spell type 4).

Casting types are constant effect, fire and forget, concentration, and scroll (value 3,
which only scrolls use). Deliveries are self, touch, aimed, target actor, and target
location. The vanilla install uses no archetype, casting type, or delivery outside these
lists.

## SPEL and SCRL fields

A spell and a scroll carry the same payload: identity, a 36-byte `SPIT` header, and the
shared `EFID`/`EFIT`/`CTDA` effect list. A scroll adds the fields every carried item has.

| field | type | SPEL | SCRL |
|---|---|---|---|
| `EDID` | zstring | editor ID | editor ID |
| `OBND` | 12 bytes | object bounds | object bounds |
| `FULL` | lstring | display name | display name |
| `MODL`/`MODT` | zstring + bytes | absent | model path |
| `KSIZ` + `KWDA` | count + FormID array | keywords | keywords |
| `MDOB` | FormID | menu display object | menu display object |
| `ETYP` | FormID | equip slot | equip slot |
| `DESC` | lstring | description | description |
| `YNAM`/`ZNAM` | FormID | absent | pickup and drop sounds |
| `DATA` | 8 bytes | absent | uint32 value, float32 weight |
| `SPIT` | 36 bytes | see below | see below |
| `EFID`/`EFIT`/`CTDA` | repeated run | effect list | effect list |

| offset | type | meaning |
|---|---|---|
| `0x00` | uint32 | base cost; used only when the manual-cost flag is set |
| `0x04` | uint32 | flags |
| `0x08` | uint32 | spell type |
| `0x0C` | float32 | charge time |
| `0x10` | uint32 | casting type (same values as MGEF) |
| `0x14` | uint32 | delivery (same values as MGEF) |
| `0x18` | float32 | cast duration; the minimum time for a concentration spell |
| `0x1C` | float32 | range, for target-actor and target-location delivery |
| `0x20` | FormID | `PERK` that halves the cost |

Flag bits: 0 manual cost, 16 unknown, 17 PC start spell, 18 unknown, 19 area effect ignores
line of sight, 20 has two names, 21 disallow absorb and reflect, 22 unknown, 23 no dual-cast
modifications.

In the game, bit 19 makes the area target search ignore line of sight. The search reaches the
effect's area times 22 units, and a chain explosion skips it. Bit 20 keeps the target's
resistance from lowering the magnitude, and skips the absorb and reflect check, so on a `SPEL` it
means "ignore resistance". Bit 21 skips the absorb and reflect check; a self-delivered effect never
makes that check anyway. An ability is never lowered by resistance. On `Skyrim.esm`, bits 16, 18,
and 23 are set together on the ritual and body-effect abilities, such as `AbShieldMassCastBodyFX`.
xEdit names bit 20 "ignore resistance" on SPEL and "script effect always
applies" on SCRL, so OpenSky keeps both names.

Spell types: 0 spell, 1 disease, 2 power, 3 lesser power, 4 ability, 5 poison, 10 addiction,
11 voice.

## Spell cost

UESP gives the cost of one effect as:

```text
effect_base_cost * (magnitude * duration / 10) ^ 1.1
```

`effect_base_cost` is the MGEF `DATA` base cost. Three values change before the math:

- A magnitude below 1 counts as 1.
- A duration of 0 counts as 10.
- On a concentration spell, the duration always counts as 10.

UESP does not say how the game drops the fraction. We compared four ways against the cost
that vanilla stores in `SPIT`, over the 1,223 spells that do not set the manual-cost flag:

| variant | spells that match |
|---|---|
| truncate each effect, then sum | 1,091 |
| sum, then truncate | 1,024 |
| round each effect, then sum | 790 |
| sum, then round | 755 |

OpenSky uses the first. The other 132 spells do not follow from their effect list at all.
For example, the stored cost of `DLC1nVampireEnhancements` is far from what its effects give.
A spell with the manual-cost flag uses its `SPIT` cost. The ENCH page on UESP gives the same
per-effect formula, so enchantments ([enchantments](/formats/enchantments.md)) use it too.

## Vanilla counts

Measured on this machine's active load order:

- MGEF: 1,812 records, 1,731 unique. No malformed fields.
- SPEL and SCRL: 1,560 spells and 109 scrolls. Every `SPIT` is 36 bytes. 333 set the
  manual-cost flag.
