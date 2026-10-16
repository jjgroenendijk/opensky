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

Then it is multiplied by the perk, enchantment, and potion terms, and by `fBlockPowerAttackMult`
for a power attack, and capped at `fBlockMax`.

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
each has a `/ 100`. Every result is a fraction from 0 to 1. The readout multiplies by 100 at the
end.

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
  two-handed, or archery values for the weapon's family, and `Mod Attack Damage`.

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
applied = base * attackBonus * (1 - blocked) * skill * sneak * (1 - armour)
```

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
The perks that change these factors, such as Backstab, test the weapon in a condition tab that
the perk evaluator does not bind yet, so they are not applied.

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
