---
type: Subsystem
title: Melee damage and blocking
description: The block formula from UESP with the install's own game setting values, how the
  fractions are read, and the attacker and blocker bonus terms.
tags: [engine, combat, melee, damage, gmst, perks]
---

# Melee damage and blocking

A landed [melee](/engine/melee-combat.md) or [archery](/engine/archery.md) hit starts from the
`WEAP` `DATA` base damage. This page covers what blocking and bonuses do to it.

## The block formula

The shape of the block formula is from UESP "Skyrim:Block":

```text
weapon: blocked = fBlockWeaponBase
                  + fBlockWeaponScaling * attackerWeaponBaseDamage
                    * (1 + blockSkill * fBlockSkillMult / 100) / 100
shield: blocked = fShieldBaseFactor
                  + fShieldScalingFactor * shieldBaseArmorRating
                    * (1 + blockSkill * fBlockSkillMult / 100) / 100
```

The shield branch applies when the blocker holds a shield, the player as well as an NPC. Then it
is multiplied by the perk, enchantment, and potion terms, and by `fBlockPowerAttackMult` for a
power attack, and capped at `fBlockMax`.

The numbers come from the install, and they are not the ones UESP prints. From `Skyrim.esm`, with
`openskycli gmst combat`:

| Setting | Install | UESP |
| --- | --- | --- |
| `fCombatDistance` | 141.000 | 141 |
| `fBlockWeaponBase` | 0.300 | 30 |
| `fBlockWeaponScaling` | 0.200 | 0.2 |
| `fShieldBaseFactor` | 0.450 | 45 |
| `fShieldScalingFactor` | 0.200 | 0.2 |
| `fBlockSkillMult` | 2.000 | 1.5 |
| `fBlockMax` | 0.700 | 85% |
| `fBlockPowerAttackMult` | 0.660 | 0.66 |
| `fBlockAmountWeaponMult` | 1.000 | not listed |

`fBlockAmountWeaponMult` has no documented use. OpenSky reads it from its name: it multiplies the
weapon branch only. At 1 it changes nothing.

The install wins: these are the numbers the game reads. UESP still gives which term multiplies
which. That shape fits the install's values in only one reading: the two base terms and the cap
are fractions, and the two scaling terms are percentage points per unit of damage or armor, so
each has a `/ 100`. Every result is a fraction from 0 to 1.

The weapon branch uses the attacker's weapon damage, not the blocker's. This looks like a bug but
is not. UESP says so, and works through the creature case (an unarmed attacker gives only the flat
base) to show it. The other reading would make a warhammer the best thing to block with.

Block skill is fixed at 15, the starting value UESP gives.

### Two bonus terms

- The blocker's term multiplies the blocked fraction, where the formula puts it. It comes from the
  Block Modifier and Block Power Modifier actor values, and the `Mod Percent Blocked` perk
  ([perks](/engine/perks.md)).
- The attacker's term follows UESP "Skyrim:Weapons":
  `... * (1 + perk effects) * (1 + item effects) * (1 + potion effect)`. It reads the one-handed,
  two-handed, or archery values for the weapon's family. The perks are in the strike terms below.

They are separate because they act on opposite sides. One term would let the target's ring change
the attacker's damage. The attacker's term applies after the blocked fraction, because the block
formula scales on the base `WEAP` damage, not the enchanted damage. So a fortified attacker deals
more through a block, without the block growing to match.

Why the magnitudes are percentage points is on the [magic](/engine/magic.md) page. A hit from an
enchanted weapon also casts the enchantment on the target and uses charge.

## Skill, sneak attacks and armour

After the block and the bonus terms, three more factors scale the hit. They multiply, so their
order does not matter.

```text
applied = ((base + weaponBonus) * attackBonus * skill * sneak * (1 - armour) * perks
           + critical) * (1 - blocked)
```

The perk terms are the attacker's and the target's perk entry points
([perk entry points](/engine/perk-entry-points.md)).

Skill. UESP "Skyrim:Weapons" gives the player's damage as `base * (1 + skill / 200)`. This is
`1 + (fDamagePCSkillMax - 1) * skill / 100` with the install's 1.5. The skill is One-Handed,
Two-Handed, or Archery for the weapon's family. An unarmed hit and an NPC's hit are not scaled.

Sneak attacks. UESP "Skyrim:Sneak": a hit on a target that has not detected the attacker
multiplies by the weapon family's setting.

| Weapon | Setting | Install |
| --- | --- | --- |
| Sword, axe, mace, dagger | `fCombatSneak1H*Mult` | 3 |
| Greatsword | `fCombatSneak2HSwordMult` | 2 |
| Battleaxe, warhammer | `fCombatSneak2HAxeMult` | 2 |
| Unarmed | `fCombatSneakHandMult` | 2 |
| Bow | none | 2 |

`fDamageSneakAttackMult` (1) multiplies every family. `fCombatSneakAttackBonusMult` (100) has no
documented use. A Nexus combat mod lowers it on hard difficulty levels, so OpenSky reads it as a
percent scale on the same product. Only the player sneak attacks, because the player has no
detection state toward an NPC. A target that is already fighting the player is never surprised.
The `Mod Sneak Attack Mult` perks, such as Backstab, change the factor.

A landed sneak attack gives Sneak experience: `fSneakAttackSkillUsageMelee` (30) for a melee hit.
UESP "Skyrim:Sneak" says "Melee sneak attacks give 12x as much as ranged sneak attacks", and no
setting holds the ranged amount, so an arrow gives 30 / 12 = 2.5. The HUD shows
`sSuccessfulSneakAttackMain`, the multiplier with one decimal, and `sSuccessfulSneakAttackEnd`:
"Sneak attack for 3.0X damage!".

Armour. UESP "Skyrim:Armor":

```text
pieceRating = DNAM rating + tempering
rating      = sum(pieceRating * factor) + Damage Resist
factor      = fArmorRatingBase + (top - fArmorRatingBase) * armourSkill / 100
top         = fArmorRatingPCMax (1.4) for the player, fArmorRatingMax (2.5) for an NPC
armour      = rating * fArmorScalingFactor / 100 + fArmorBaseFactor * pieces
```

The armour skill is Light Armor or Heavy Armor, by the piece's `BOD2` type. A clothing piece
uses `fClothingArmorScale` as its factor and does not count as a piece. `armour` is capped at
`fMaxArmorRating` percent (80). Arrows go through the same skill, sneak, and armour factors.

## Power attacks and bashes

A press of the attack button waits. Released before 0.3 seconds, it is a plain swing
(`attackStart`). Held for 0.3 seconds, it is a power attack. The 0.3 seconds is the default of the
INI setting `fInitialPowerAttackDelay`; OpenSky does not read the INI file. The power attack's
event follows the movement keys: `attackPowerStartForward`, `attackPowerStartBackward`,
`attackPowerStartLeft`, `attackPowerStartRight`, or `attackPowerStartInPlace`. All five are
declared by `0_master.hkx` on the install.

A power attack costs stamina when it starts (UESP "Skyrim:Combat"):

```text
cost   = (fStaminaAttackWeaponBase + weaponWeight * fStaminaAttackWeaponMult)
         * fPowerAttackStaminaPenalty
damage = normal damage * (1 + fPowerAttackDefaultBonus)
```

With the install's 20, 1, and 2, a 10-weight sword costs 60 stamina. Below one point of stamina,
a held press plays the plain swing instead. After a power attack, the next one waits
`fPowerAttackCoolDownTime` seconds (0 on the install). A blocked power attack also uses
`fBlockPowerAttackMult`.

With the guard up, a press is a bash (`bashStart`) and costs `fStaminaBashBase` (35). Held, it is
a power bash (`bashPowerStart`, `fStaminaPowerBashBase`, 55), but only with the Power Bash perk.
A bash reaches `fCombatBashReach` whatever the weapon. Its damage is from UESP "Skyrim:Block":

```text
bash      = source * 0.5 * (min + blockSkill / 100 * (max - min))
power bash = 3 * bash
```

`source` is the shield's base armour rating, or the weapon's base damage without a shield. The
pairs are `fShieldBashPCMin`/`fShieldBashPCMax` and `fWeaponBashPCMin`/`fWeaponBashPCMax` for the
player, and the same names without `PC` for an NPC. `Skyrim.esm` carries only `fShieldBashMin`,
`fShieldBashMax`, `fShieldBashPCMax`, and `fWeaponBashMax`. The others keep the values UESP lists.
A bash is not scaled by fortify effects, which UESP states.
