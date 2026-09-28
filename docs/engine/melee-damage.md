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
