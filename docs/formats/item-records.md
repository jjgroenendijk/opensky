---
type: File Format
title: Item records (MISC, KEYM, SLGM, APPA, BOOK, ALCH, INGR, WEAP, AMMO, CONT, ARMO)
description: Layouts of carried items, their shared fields, effect lists, and container
  contents.
tags: [format, plugin, records, inventory, items]
---

# Item records

These records are things an actor can carry, plus container contents. The projectile an
arrow launches is on [projectiles](projectiles.md). Shared decode rules are on
[record decoders](records.md). The runtime is on
[inventory and equipment](../engine/inventory-equipment.md).

Sources: UESP "Skyrim Mod:Mod File Format" pages `/MISC`, `/KEYM`, `/SLGM`, `/APPA`,
`/BOOK`, `/ALCH`, `/INGR`, `/WEAP`, `/AMMO`, `/CONT`, and `/ARMO`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), and xEdit `dev-4.1.6`
`wbDefinitionsTES5.pas` and `wbDefinitionsCommon.pas`. Line numbers below are in those
files.

## Shared fields

Every carried item repeats the same fields:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `MODL` | zstring | model |
| `OBND` | 6 x int16 | bounds: minimum corner, then maximum corner (xEdit `wbOBND`, common line 8634) |
| `KSIZ` + `KWDA` | uint32 + FormID array | keywords |
| `ICON`, `MICO` | zstring | inventory icons |
| `YNAM`, `ZNAM` | FormID | pickup and drop sounds |

`DATA` is different for each type: 8 bytes on MISC, KEYM, SLGM, APPA, INGR, and ARMO
(int32 value, float32 weight), 4 on ALCH, 10 on WEAP, 16 on BOOK, and 16 or 20 on AMMO.

## MISC

Gems, ingots, tools, gold, and clutter. Only the shared fields and the 8-byte `DATA`
(line 8303).

A `LIGH` with the "can be carried" flag, such as a torch, is an item too. Its name, value,
and weight are in the [lighting records](lighting.md#ligh) page.

## KEYM, SLGM, and APPA

Keys, soul gems, and alchemy apparatus. Each has the shared fields and the 8-byte `DATA`.
xEdit types the value int32 on KEYM and uint32 on SLGM and APPA. The decoders read every
other field by name and count the rest (`VMAD`, `MODT`, the `DEST` destruction fields) in an
unread-field tally. A malformed field is counted too, and the rest of the record still loads.

KEYM (line 7868) adds nothing. Record-header flag `0x04` marks it non-playable.

SLGM (line 5460):

| field | type | meaning |
| --- | --- | --- |
| `SOUL` | uint8 | contained soul: 0 none, 1 petty, 2 lesser, 3 common, 4 greater, 5 grand |
| `SLCP` | uint8 | maximum capacity, same values |
| `NAM0` | FormID | linked SLGM |

The enum is `wbSoulGemEnum` (`wbDefinitionsCommon.pas` line 8185). Record-header flag
`0x20000` is "Can Hold NPC Soul", set on the black soul gems. OpenSky decodes the soul data
only; filling and using a gem are not modeled. The inventory names a gem's soul with the
`sSoulLevelNamePetty` to `sSoulLevelNameGrand` settings, in the `sSoulLevel` line "Filled with %s
Soul", and an empty gem with `sEmpty`.

APPA (line 8251):

| field | type | meaning |
| --- | --- | --- |
| `QUAL` | int32 | quality: 0 novice, 1 apprentice, 2 journeyman, 3 expert, 4 master |
| `DESC` | lstring | description |

xEdit lists no keyword fields on APPA. An unknown soul or quality value keeps its number.
The player brews only at an alchemy lab, not with carried apparatus (UESP "Skyrim:Alchemy",
<https://en.uesp.net/wiki/Skyrim:Alchemy>), so no brewing rule reads the quality. Papyrus
reads it with `Apparatus.GetQuality` (<https://ck.uesp.net/wiki/Apparatus_Script>), which
returns the `QUAL` number. `Apparatus.SetQuality` changes the base form's quality, so a
later `GetQuality` returns the new number. OpenSky keeps the change until the next game
load and does not write it to a save.

Observed in the five masters (`Skyrim.esm`, `Update.esm`, `Dawnguard.esm`,
`HearthFires.esm`, `Dragonborn.esm`): 377 KEYM, 17 SLGM, and 45 APPA, all decoded. The
unread fields are `MODT` (391) and `VMAD` (5); no field was malformed. Examples:
`SoulGemBlack` holds no soul and has grand capacity, `SoulGemPettyFilled` holds a petty
soul, and `Alembic04Expert` has expert quality. In `Skyrim.esm`, 359 `CNTO` entries name
one of the three types, and every one resolves to an item.

## BOOK

| field | type | meaning |
| --- | --- | --- |
| `DESC` | lstring | book text, from the `.dlstrings` table ([strings](strings.md)) |
| `CNAM` | lstring | inventory description |
| `DATA` | 16 bytes | see below |
| `INAM` | FormID | inventory art, a `STAT`; kept, and nothing reads it while the game runs |

`DATA` (line 4220): uint8 flags (`0x01` teaches skill, `0x02` cannot be taken, `0x04`
teaches spell), uint8 kind (0 book, 255 note; always 0 since SSE), 2 unused bytes, uint32
"teaches" word, uint32 value, float32 weight. The "teaches" word is an actor-value skill
index with flag `0x01`, a SPEL FormID with flag `0x04`, and unused otherwise. If a mod sets
both flags, OpenSky reads a spell.

How the game uses the flags:

- `0x01`: reading the book raises the skill (actor values 6 to 23) by 1, through perk entry
  point 5, while the skill is below 200. Then the game clears `0x01` and `0x04` and marks the
  book changed, so the book teaches once and the save keeps it. At load, a skill outside 6 to
  24 clears `0x01` and sets the skill to -1.
- `0x04`: reading the book teaches the spell. The item card text and the "learned" or "already
  known" message depend on whether the player knows the spell.
- `0x08`: set by the first read. That read also sends a "book read" event, which says whether
  the book taught a skill, and marks the book changed, so the save keeps it.
- Nothing reads `0x10` or a higher bit.
- `0x02`: activating the book reads it but does not take it, and an NPC that loots skips it.

## ALCH

Food, drink, potions, and poisons (line 4042). Here `DATA` is only a float32 weight. The
value is in `ENIT`, 20 bytes: int32 value, uint32 flags (`0x00001` no auto-calc, `0x00002`
food, `0x10000` medicine, `0x20000` poison), FormID addiction, float32 addiction chance,
FormID consume sound (`SNDR`).

## INGR

Alchemy ingredients (line 7909). The 8-byte `DATA`, and an 8-byte `ENIT`: int32 auto-calc
value (not the same as the value in `DATA`) and uint32 flags (`0x001` no auto-calc, `0x002`
food, `0x100` references persist).

## Effect lists

ALCH, INGR, SPEL, SCRL, and ENCH store effects as a run of fields, not a struct. `EFID`
names the MGEF, the next `EFIT` holds its numbers, and any `CTDA` after that is a condition
on that effect ([conditions](conditions.md)). Then the run repeats. xEdit: `wbEFID`
line 3832, `wbEFIT` 3834, `wbEffect` 4030.

| field | type | meaning |
| --- | --- | --- |
| `EFID` | FormID | the MGEF ([magic records](magic-records.md)) |
| `EFIT` | 12 bytes | float32 magnitude, uint32 area, uint32 duration |
| `CTDA` | 32 bytes | condition on this effect |

An `EFIT` without an `EFID` before it is dropped. An `EFID` without an `EFIT` still counts,
with magnitude 0.

## WEAP

| field | type | meaning |
| --- | --- | --- |
| `DATA` | 10 bytes | uint32 value, float32 weight, uint16 damage |
| `DNAM` | 100 bytes | animation type, speed, reach, flags, rumble, skill, stagger |
| `CRDT` | 16 or 24 bytes | critical hit data |
| `EITM` | FormID | enchantment (`ENCH`) |
| `EAMT` | uint16 | enchantment charge |
| `ETYP` | FormID | equip slot (`EQUP`, see [shouts and equip slots](shouts-equip-slots.md)) |
| `CNAM` | FormID | template, another WEAP |
| `INAM` | FormID | impact data set (`IPDS`) for a normal swing |
| `BIDS` | FormID | impact data set (`IPDS`) for a shield bash |
| `BAMT` | FormID | alternate block material, a `MATT`; kept, and nothing reads it while the game runs |
| `WNAM` | FormID | first-person model, a `STAT` |
| `NNAM` | zstring | embedded weapon node |

Record at line 10499, `DATA` 10530, `DNAM` 10535, `CRDT` 10604.

`DNAM` offsets: `0x00` uint8 animation type (0 other, 1 one-hand sword, up to 9 crossbow),
`0x04` float32 speed, `0x08` float32 reach, `0x0C` uint16 flags (`0x08` cannot drop, `0x20`
embedded, `0x80` not playable), `0x34`, `0x38`, and `0x3C` float32 rumble left motor strength,
right motor strength, and seconds (the Creation Kit's Rumble tab), `0x4C` int32 skill as an
actor value (-1 for none), `0x60` float32 stagger. The rest is padding or old Fallout fields.

At load, a speed or reach at or below 0 becomes 1. The INI setting `bForceNPCsUseAmmo` sets
flags-2 bit `0x2` on every weapon. Flag `0x20` (embedded) with a non-empty `NNAM` makes `NNAM`
the node a projectile launches from. Otherwise the game uses `ProjectileNode`, then
`##ProjectileNode`. Flags-2 bit `0x40` gives the weapon a score of 0 when an NPC picks a
combat weapon, so the AI never picks it for normal combat.

Flags-2 is the uint32 at `0x28`, and the game keeps its low 16 bits. Bit `0x01` (player only)
keeps the weapon out of every NPC weapon choice. Bit `0x2000` marks a bound weapon:

- the condition `HasBoundWeaponEquipped` is 1 when the left hand (parameter 0) or the right
  hand (parameter 1) holds one;
- an NPC's weapon score adds `fCombatBoundWeaponDPSBonus` (100000), so an NPC always picks a
  bound weapon it carries; bit `0x40` still gives a score of 0 first;
- unequipping one removes one of it from the actor's inventory;
- a bulk unequip of an actor's items skips it, and when an item moves between the player and
  another actor, that actor is equipped again with its armour and its other weapons, not its
  bound weapons.

xEdit names a `DNAM` byte "Embedded Weapon AV" (offset `0x1B`, not confirmed). The game reads
it as actor value 46 plus the byte, at most 52: the body-part condition values. An actor that
holds an embedded weapon reads that actor value (100 without one) and works out value × 0.1,
less 1 when that is above 1. What this number drives is not known.

`WNAM` names a `STAT`. The player's weapon shows that static's model, in first and in third
person. An NPC's weapon shows the weapon's own `MODL`.

`CNAM` names a template weapon. At load, after the template's own load, the template
overwrites this weapon's model with its `MODT` and `MODS`, icon, weight, `DATA` damage,
destruction data, equip slot, message icon, pickup and putdown sounds, `BIDS` and `BAMT`,
keywords, description, scope model (`MOD3`), `INAM`, `WNAM`, all of `DNAM`, `CRDT`, and the
weapon sounds. The name, enchantment, value, and `NNAM` stay this weapon's own.

A weapon with "Can't Drop" set "cannot be disarmed and does not fall off when actor dies"
(<https://ck.uesp.net/wiki/Weapons>). So a disarm effect leaves it in the hand, and a death
never drops it. An embedded weapon (flag `0x20`) also stays with its owner at death. A
non-playable weapon is hidden from the player
([inventory menu](../engine/inventory-menu.md#row-list)).

Reach
is a multiplier, not a distance: UESP gives melee reach as `fCombatDistance * NPCScale *
WeaponReach` ([melee combat](../engine/melee-combat.md)).

`CRDT` changed in SSE. The size picks the layout, not the form version, so older mod records
still read:

| bytes | layout |
| --- | --- |
| 16 | uint16 damage, 2 unused, float32 multiplier, uint8 on-death, 3 unused, FormID SPEL |
| 24 | the same, but 7 unused after on-death, SPEL at `0x10`, then 4 unused |

Weapon sounds, and when the game plays them:

| Field | Sound |
| --- | --- |
| `NAM9` | Draw: plays at the actor when the animation sends the right hand's begin-draw event |
| `NAM8` | Sheathe: plays at the actor on the begin-sheathe event |
| `TNAM` | Swing: plays at the actor on every weapon-swing animation event, either hand |
| `SNAM` | Fire: a 3D sound when the weapon launches its projectile |
| `XNAM` | Fire for the player in first person, instead of `SNAM` |
| `NAM7` | A loop while the actor attacks without a pause |
| `UNAM` | A loop while the weapon is equipped and the actor is alive |

Every vanilla `NAM9` is a draw sound and every `NAM8` a sheathe sound. `TNAM` is the swing sound
on 2,435 vanilla weapons, not an "attack fail" sound. After `SNAM` or `XNAM`, the weapon's sound
level makes a detection event at the shooter. The 7 bound weapons use `UNAM` for
`MAGConjureBoundWeaponLP`.

OpenSky starts the `NAM7` loop on each swing event and stops it on the `attackStop` event, so a
chain of swings keeps it playing. The `UNAM` loop plays while the holder is alive, for the
player and for NPCs near the listener.

The item card shows a weapon's `DESC` as its effect text when it is not empty. Only an empty
`DESC` shows the enchantment's text instead. 33 `Skyrim.esm` weapons have one, such as
`SilverSword` and the Nightingale bow. The same holds for armour: 28 `ARMO` records.

UESP calls `INAM` "Normal weapon swing impact set" and `BIDS` "Block bash impact data set".
A null link on a weapon or armour means the hit makes no impact. That is normal in vanilla.
Another bashing item uses the default object's impact set
([armour](armor.md#armo)).

## AMMO

`DATA` grew in SSE, so the size picks the layout (line 4087, `IsSSE` pair at 4101):

| offset | type | meaning |
| --- | --- | --- |
| 0x00 | FormID | projectile (`PROJ`, see [projectiles](projectiles.md)) |
| 0x04 | uint32 | flags: `0x01` ignores weapon resistance, `0x02` not playable, `0x04` not a bolt |
| 0x08 | float32 | damage |
| 0x0C | uint32 | value |
| 0x10 | float32 | weight; SSE only, the 16-byte form ends before it |

Vanilla SSE gives every arrow weight 0.1, but the game treats arrows as weightless.

What the game does with the flags:

- `0x01`: no reader was found in the game program, so the flag seems to change nothing.
- `0x02`: an arrow that hits an actor never joins its inventory.
- `0x04`: picks how deep the arrow sticks. A bolt sticks `fCombatBoltStickDepth` (5) units deep,
  other ammunition `fCombatMissileStickDepth` (10 in the program, 20 in `Skyrim.esm`).

## CONT contents

A container has the placeable fields ([world records](world-records.md)) plus its
contents:

| field | type | meaning |
| --- | --- | --- |
| `COCT` | uint32 | entry count; not trusted |
| `CNTO` | 8 bytes | FormID item, int32 count; repeated |
| `COED` | 12 bytes | owner data for the `CNTO` before it |
| `DATA` | uint8 + float32 | flags: `0x01` allow sounds, `0x02` respawns, `0x04` show owner |

xEdit: `wbCOED` line 2305, `wbCNTO` 2315, `wbCOCT` 2329, `wbRecord(CONT, ...)` 4505. A
`CNTO` item can be a carried item or an `LVLI`. The middle word of `COED` is a GLOB FormID
when the owner is an NPC_, and a faction rank when it is a FACT. The `DATA` float is
documented as a misplaced weight that is always 0.

Only the `DATA` flags byte is read. The `SNAM` open sound plays at the container when an actor
activates it and the lock lets it in. The `QNAM` close sound plays when the container menu
closes. Neither waits for an animation event. A container whose model has a
`NiControllerManager` with a sequence plays them only when flag `0x01` is set; any other
container always plays them. With flag `0x04` (show owner), the activate prompt puts the
owner's name and "'s" in front of the container's name.

## ARMO inventory fields

The appearance fields are on [armor records](armor.md). Inventory fields: the
8-byte `DATA`, keywords, `DNAM` (armor rating x 100, a uint32 of which only the low 16 bits
are used), and `EITM` (enchantment). ARMO has no `EAMT`: xEdit builds both records' link
from `wbEnchantment` and adds the charge only on WEAP. So enchanted armor has no charge.

## Item sounds

An item plays its `YNAM` pickup sound when it is picked up and its `ZNAM` putdown sound
when it is dropped. A potion or food plays its `ALCH` `ENAM` use sound when it is consumed.
The Creation Kit wiki names these fields "Pickup Sound", "Putdown Sound", and "Use Sound"
(<https://ck.uesp.net/wiki/Potion>, <https://ck.uesp.net/wiki/Armor>).

An item with no pickup or putdown sound of its own plays the Default Object of its kind
(<https://ck.uesp.net/wiki/DefaultObjectManager_Script>):

| Kind | Pickup | Putdown |
| --- | --- | --- |
| Weapon | `PUSW` | `PDSW` |
| Armour | `PUSA` | `PDSA` |
| Book | `PUSB` | `PDSB` |
| Ingredient | `PUSI` | `PDSI` |
| Any other item | `PUSG` | `PDSG` |

The sound plays where the item is: at the picked-up reference, or where the dropped item
lands. A use sound plays at the actor.

## Vanilla items

In `Skyrim.esm`:

| measure | value |
| --- | --- |
| items | 7,326 (ARMO 2,762, WEAP 2,484, BOOK 821, MISC 371, ALCH 363, KEYM 334, INGR 94, APPA 45, AMMO 35, SLGM 17) |
| containers | 436 CONT with 9,597 `CNTO` entries |
| `CNTO` naming an item | 7,112, of which 359 name a KEYM, SLGM, or APPA |
| other `CNTO` | LVLI, LIGH, and SCRL |
| `CNTO` naming a type xEdit does not allow | 0 |
| `COCT` that disagree with `CNTO` | 0 |
| value / weight | 0 to 5,000 gold, 0.0 to 50.0 |

Every `CNTO` names an allowed type. That would not hold if item and count were in the other
order.

Examples: `IronSword` (WEAP `00012EB7`) has value 25, weight 9, damage 7, animation type
one-hand sword, speed 1, reach 1, critical damage 3. `SkillSmithing1` (BOOK `0001AFCE`)
teaches skill 10. `Wheat` (INGR `0004B0BA`) has 4 effects and auto-calc value 47.
`IronArrow` (AMMO `0001397D`) has damage 8 and projectile `0003BE11`. `BarrelFood01` (CONT
`00000845`) has 1 entry and flags `0x2`.
