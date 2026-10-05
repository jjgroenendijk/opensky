---
type: Subsystem
title: Combat graph names and hand types
description: The behavior graph events and variables melee and archery raise and read, and the
  iRightHandType and iLeftHandType encoding read from the vanilla graphs.
tags: [engine, combat, behavior-graph, hkx, weapons]
---

# Combat graph names and hand types

[Melee combat](/engine/melee-combat.md) talks to the player's
[behavior graph](/engine/behavior-runtime.md) by name. Every name here comes from the behavior
census over the install (`.logs/hkx-behavior-census.log`), never from memory. `0_master.hkx`
declares 230 variables and 1,217 events, and a name that only sounds right resolves to nothing.
Each name is spelled exactly as the third-person
`meshes\actors\character\behaviors\0_master.hkx` spells it, including vanilla's mixed
capitalization: `attackStart` and `HitFrame` are in the same file.

## Events and variables

Havok events have no direction. The same name can be raised into a graph and fired back out. The
split below says which way OpenSky uses each name. It is not a property of the data.

| Raised into the graph | Meaning |
| --- | --- |
| `weaponDraw`, `weaponSheathe` | Draw and sheath requests |
| `WeapEquip`, `Magic_Equip`, `Unequip` | The equip events the graph moves on |
| `attackStart`, `attackRelease`, `attackStop` | Swing start, release of a held power attack, swing end |
| `blockStart`, `blockStop` | Guard up and down |
| `staggerStart`, `staggerStop` | The stagger a hit causes, on the target's graph |

| Fired back by the graph | Meaning |
| --- | --- |
| `BeginWeaponDraw`, `BeginWeaponSheathe` | The clip marks where the weapon changes nodes |
| `WeapEquip_Out`, `Unequip_Out` | The graph's own end-of-equip transitions |
| `weaponSwing` | The audible start of the swing, before contact |
| `preHitFrame` | The frame before contact |
| `HitFrame` | The contact frame, which runs the sweep |
| `blockHitStart` | A block absorbed a hit |

Variables written: `IsAttacking`, `IsBlocking`, `IsStaggering`, `staggerMagnitude`,
`weaponSpeedMult`, `iRightHandType`, `iLeftHandType`.

`weaponDraw` is odd. The graph declares it, but no transition in any file under
`meshes\actors\character\behaviors\` names it. In vanilla it is the intent: the engine, not the
graph, decides what that intent equips and raises the matching equip event. OpenSky raises both,
in that order. `Magic_Equip` replaces `WeapEquip` when the right hand holds a readied spell.
`Unequip` covers both on the way back.

Variables are written before events are raised. The graph picks the equip clip from
`iRightHandType` when it acts on `WeapEquip`. So a frame that equips a sword and draws it must
write the number first.

## Hand types

`iRightHandType` and `iLeftHandType` are `int32` values that select the animation set. The equip
selectors in `weapequip.hkx` index their child list by them, and most combat transitions in
`1hm_behavior.hkx` test them. If they are not written, both hands read 0 (empty), and the graph
plays hand-to-hand for a drawn sword.

The census gave the names and type, but not the numbers. They were read from the install:

| Value | Holding | Read from |
| --- | --- | --- |
| 0 | Nothing (hand-to-hand) | `Weap_Equip_MSG` child 0, `MT_H2H_State` |
| 1 | One-handed sword | `1HM_Equip.hkx`, `MT_1HM_State` |
| 2 | Dagger | `Dag_Equip.hkx`, `MT_Dagger_State` |
| 3 | War axe | `Axe_Equip.hkx`, `MT_Axe_State` |
| 4 | Mace | `Mac_Equip.hkx`, `MT_Mace_State` |
| 5 | Greatsword | `2HC_Equip.hkx`, `MT_2HM_State` |
| 6 | Battleaxe or warhammer | `2HW_Equip.hkx`, `MT_2HW_State` |
| 7 | Bow | `Bow_Equip.hkx`, `MT_BowState` |
| 8 | Staff | `Stf_Equip.hkx`, `MT_Staff_State` |
| 9 | Readied spell | `MagicForceEquipBlend`, `MT_Magic_State` |
| 10 | Shield | `MRh_and_Shield_ForceEquipBlend`, `MT_Shield_State` |
| 11 | Torch | `MRh_Equip_TorchBlend`, `MT_Torch_State` |
| 12 | Crossbow | `DLC01\CrossBow_Equip.hkx`, `MT_CrossBowState` |

Three separate readings agree:

- `weapequip.hkx` binds `hkbManualSelectorGenerator::m_selectedGeneratorIndex` to the variable, so
  the selector's child list is the encoding, in order.
- `0_master.hkx` uses the same thirteen values as the state IDs of its `MT_LeftHandOverride`
  machine.
- The transition conditions agree where they overlap. `1hm_behavior.hkx` takes `bowAttackStart`
  only on `iRightHandType == 7`, bashes with a bow or crossbow on
  `(iRightHandType == 7) || (iRightHandType == 12)`, and dual-wields only when both hands are in
  `1...4`. `magicbehavior.hkx` shouts on `(iRightHandType == 8) || (iRightHandType == 9)`.

This is not the `WEAP` `DNAM` animation type, although it looks like it. The two agree from 0 to 8,
then differ: `DNAM` uses 9 for crossbow, while the graph uses 9 for a spell and 12 for a crossbow.
The graph also has three values (spell, shield, torch) that no `WEAP` record can hold. One
conversion function is the only place the two meet.

## The left hand

The left hand comes from the equipped set:

- A two-handed weapon fills both hands and reports its type on each.
- A second equipped `WEAP` is the off-hand weapon.
- A shield is any equipped `ARMO` on biped slot 39.

A torch is a `LIGH`, which the equipment catalog does not index, so a lit hand still reports empty.
Torches and true dual-wielding need the equipment runtime to track which hand an item went into.
