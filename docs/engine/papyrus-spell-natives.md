---
type: Subsystem
title: Papyrus spell natives
description: The eleven Actor and Spell natives over the spellbook, casting, and active effects -
  how they were chosen, why none is latent, the casting source numbers, and the stated gaps.
tags: [engine, papyrus, magic]
---

# Papyrus spell natives

These natives sit on [spellcasting](/engine/spellcasting.md) and [active effects](/engine/magic.md),
through [the world bridge](/engine/papyrus-activation.md#the-world-bridge).

Which eleven was measured, not chosen. The native census over the install's compiled scripts ranks
every native by call sites, and the magic head of that list is what is registered. The counts are the
References column.

| Native | References | What it does | Source |
| --- | ---: | --- | --- |
| `bool RemoveSpell(Spell)` | 311 | Forgets the spell and clears any hand holding it | [RemoveSpell - Actor](https://ck.uesp.net/wiki/RemoveSpell_-_Actor) |
| `bool AddSpell(Spell, bool abVerbose = true)` | 278 | Teaches it. False if already known | [AddSpell - Actor](https://ck.uesp.net/wiki/AddSpell_-_Actor) |
| `Cast(ObjectReference akSource, ObjectReference akTarget = None)` | 277 | Casts the spell at once from `akSource` | [Cast - Spell](https://ck.uesp.net/wiki/Cast_-_Spell) |
| `bool HasSpell(Form)` | 72 | Whether the actor knows it | [HasSpell - Actor](https://ck.uesp.net/wiki/HasSpell_-_Actor) |
| `Spell GetEquippedSpell(int aiSource)` | 40 | The spell ready at that source, or `None` | [GetEquippedSpell - Actor](https://ck.uesp.net/wiki/GetEquippedSpell_-_Actor) |
| `EquipSpell(Spell, int aiSource)` | 37 | Readies it, teaching it first if needed | [EquipSpell - Actor](https://ck.uesp.net/wiki/EquipSpell_-_Actor) |
| `bool HasMagicEffect(MagicEffect)` | 31 | Whether an effect of that `MGEF` is acting | [HasMagicEffect - Actor](https://ck.uesp.net/wiki/HasMagicEffect_-_Actor) |
| `bool DispelSpell(Spell)` | 30 | Removes every effect that spell applied | [DispelSpell - Actor](https://ck.uesp.net/wiki/DispelSpell_-_Actor) |
| `UnequipSpell(Spell, int aiSource)` | 21 | Clears that hand, only if it holds the spell | [UnequipSpell - Actor](https://ck.uesp.net/wiki/UnequipSpell_-_Actor) |
| `DispelAllSpells()` | 16 | Removes every effect that can be dispelled | [DispelAllSpells - Actor](https://ck.uesp.net/wiki/DispelAllSpells_-_Actor) |
| `bool HasMagicEffectWithKeyword(Keyword)` | 8 | Whether an acting effect has that keyword | [HasMagicEffectWithKeyword - Actor](https://ck.uesp.net/wiki/HasMagicEffectWithKeyword_-_Actor) |

## None is latent

Each wiki page declares a plain `native` with no latent marker, and the cast page says "This
function casts the spell instantaneously." So each returns on the same call, and a script that casts
and then reads `HasMagicEffect` sees the effect.

## Where each goes

- Learning, forgetting, and readying go through the spellbook, so a scripted `AddSpell` is saved
  like reading a spell tome. Readying a hand works against worn equipment by the same path the
  panel's Ready button uses.
- Dispelling goes through the active effect runtime, so each removed effect gives back its modifier
  slot.
- `Spell.Cast` goes through the caster, so it applies the effect list with the same code a player's
  cast uses.

Casting sources are xEdit's `wbCastingSourceEnum`: 0 Left, 1 Right, 2 Voice, 3 Instant. The wiki's
`EquipSpell` page uses the same numbers. OpenSky readies spells in two hands and has no voice slot,
so sources 2 and 3 are a tallied failure, not a silent no-op.

## Stated gaps

| Behavior | What OpenSky does | Why |
| --- | --- | --- |
| `RemoveSpell` on a spell a race or base actor grants | Removes it | The wiki says vanilla keeps such a spell and "will still return true in such cases". Here an authored `SPLO` grant is an ordinary known spell. Copying a documented false answer would make correct scripts wrong |
| `AddSpell(_, abVerbose)` | Ignores the flag | It only hides a message, and there is no spell-added message yet |
| `Spell.Cast` and magicka | Never charges the caster | The wiki describes a cast that does not animate the actor and works whether or not the source knows the spell. Nothing in it says the caster pays |
| `Spell.Cast` with `akTarget` | Applies to that actor, with no area sweep | A script that names a target is not aiming. Nothing knows where an impact was, and an invented spot could catch bystanders |
| `Actor.DoCombatSpellApply` | Not installed | It asks the combat controller to fit a spell into what it is doing. The caster AI picks its own spells, so an instant cast would bypass its decisions |
| `Spell.RemoteCast`, `Spell.Preload`, `Spell.Unload` | Not installed | The asset lifecycle they name does not exist |
| The `ActiveMagicEffect` script | Not installed | No script archetype `MGEF` runs yet, so there is no receiver |
| `HasMagicEffect`, `HasMagicEffectWithKeyword` | Answer "is it acting", not "is it carried" | The same narrowing the condition functions use, cited on [condition evaluation](/engine/conditions.md) |
