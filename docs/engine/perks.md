---
type: Subsystem
title: Perks at runtime
description: Owning perks, ranks as record chains, the entry-point evaluator, condition tab
  subjects, the formulas that ask, and perk abilities.
tags: [engine, progression, perks, combat, magic, conditions, runtime-state]
---

# Perks at runtime

The record side is on the [perks](/formats/perks.md) page: what a `PERK` is, how its effect
sections decode, and how entry points are indexed across the load order. This page covers who
owns a perk, and what an owned perk does to a number.

Ownership is a world state component. Evaluation is a pure calculation, and a runtime around it
gathers the owned effects and checks their conditions.

## Owning a perk

The perk component stores a sorted list of owned `PERK` identities, and nothing else. Every
change writes through the world state, so a new perk reaches the change log, the dirty counts,
and the save exactly like a learned spell ([runtime state](/engine/runtime-state.md)). The
component is removed when it becomes empty.

Two rules, as for the spellbook:

- Adding a perk this load order does not have is refused and counted. It could never be
  evaluated.
- A stored perk that stops resolving is kept. Removing a plugin must not destroy progress. The
  perk is only invisible to every query.

An NPC gets the perks of its own `PRKR` list. The list comes through the template chain when
the `ACBS` "Use Spell List" flag is set. UESP names that bit "Use spelllist (both spells and
perks)", so an actor that takes its spells from a template takes its perks from it too. The seed
happens the first time something asks about that actor, not at cell build. A cell of townsfolk
who never fight would otherwise each write a component that only repeats their base record.

The player starts with no perks, because there is no `NPC_` record behind the player here.

Owned perks are saved in the `PRKS` chunk, one entry per actor with at least one perk. Only the
identities are written. The rank is derived from the chain, and the abilities are granted again
on load ([save chunks](/formats/save-chunks.md)).

## Ranks are chains, not numbers

Each rank of a vanilla perk is its own `PERK` record, joined by `NNAM`. The game adds the record
for the rank it wants. Example: taking the second rank of Armsman adds `Armsman20`. Then
`Armsman00` turns itself off, because its perk owner condition is `HasPerk Armsman20 == 0`.
This was read from the local install.

So no rank number is stored. The rank is the position of the deepest owned record in the `NNAM`
chain: 0 when none is owned, 1 for the head alone. The deepest is used, not a count, because a
script can grant a later rank without the earlier ones.

The `PRKR` rank byte is not stored. UESP marks it "uint8 Rank (no longer in use)".

## The entry-point evaluator

The evaluator takes a value and a list of operands. Each operand is a function, its `EPFD`
payload, and its `PRKE` priority. It returns the new value, how many applied, and a reason for
each one that did not. It uses no store, no world, and no conditions.

The math is UESP's "Function Types" table:

| Id | Function | New value | Done |
| --- | --- | --- | --- |
| 01 | Set Value | `VALUE` | yes |
| 02 | Add Value | `Value + AMOUNT` | yes |
| 03 | Multiply Value | `Value * FACTOR` | yes |
| 04 | Add Range to Value | `Value + random(MIN, MAX)` | no |
| 05 | Add Actor Value Mult | `Value + AV * FACTOR` | yes |
| 06 | Absolute | `Abs(Value)` | yes |
| 07 | Negative ABS Value | `-Abs(Value)` | yes |
| 08 | Add Level List | a list | no |
| 09 | Add Activate Choice | a button | no |
| 0A | Select Spell | a spell | no |
| 0B | Select Text | a text | no |
| 0C | Set AV Mult | `AV * FACTOR` | yes |
| 0D | Multiply AV Mult | `Value * AV * FACTOR` | yes |
| 0E | Multiply 1 + AV Mult | `Value * (1 + AV * FACTOR)` | yes |
| 0F | Set Text | a text | no |

`Add Range to Value` is the only number function left out. Neither UESP nor xEdit gives the
random distribution or the seed. Inventing one would make a formula that should be repeatable
depend on a made-up number.

Anything a function cannot do leaves the value unchanged and is counted. This covers an
unsupported function, a missing or wrong payload, an actor value the caller cannot read, and a
result that is not finite. The rule for the whole system: an entry point nothing implements
never changes a number.

### Order

The `PRKE` priority byte is the only order a record gives. UESP says: "Priority - Assumed to be
how to order/iterate through perk sections". OpenSky applies operands from the highest priority
down. Ties keep the index order: priority, plugin, object ID, effect position. So one load order
always applies the same effects in the same order.

Order matters only when a `Set Value` meets another function. This order is a choice, not a
known fact.

## Which entry points are covered

Any entry point whose effects use one of the nine number functions can be evaluated. An unknown
entry point ID evaluates to no change. What differs is whether a formula asks. These ask today:

| Entry point | Id | Asked by |
| --- | --- | --- |
| Mod Attack Damage | 35 | melee and bow damage |
| Mod Percent Blocked | 39 | the blocked fraction, for both sides of a fight |
| Mod Spell Cost | 38 | the magicka cost of every cast |

Nothing asks about lockpicking, prices, detection, tempering, or enchanting yet, because those
formulas do not exist.

## Condition tabs and their subjects

An entry-point effect has one to three `PRKC` condition tabs. The `PRKC` byte is an index into
the entry point's own list of condition subjects, not a run-on type. For `Mod Attack Damage` the
list is (Perk Owner, Weapon, Target), so tab 1 asks about the weapon. OpenSky copies that column
of UESP's "Perk Effect Types" table for all 92 entry points.

A caller binds the subjects it knows. A melee formula knows the perk owner and the target. It
cannot bind a weapon, item, enchantment, or spell, because those are forms, not placed
references that conditions such as `HasKeyword` can run on.

A tab whose subject is not bound is skipped and counted, not failed. This is on purpose, and it
is knowingly wrong in one direction. Example: `Armsman00`'s weapon tab checks for a one-handed
weapon. With the tab skipped, the perk also raises two-handed damage. Failing the tab instead
would turn off every vanilla damage perk, which is a worse and silent error. The counter shows
how often it happens.

A bound tab is evaluated strictly by the normal
[condition evaluator](/engine/condition-evaluation.md). An unimplemented function is false with
a reason, and the effect does not apply.

## Where perks change numbers

Each formula multiplies the perk term in the same place as the fortify term. This follows the
shape on UESP "Skyrim:Weapons":
`... * (1 + perk effects) * (1 + item effects) * (1 + potion effect)`.

- Melee and archery: the fortify bonus times the `Mod Attack Damage` result
  ([melee combat](/engine/melee-combat.md), [archery](/engine/archery.md)).
- Blocking: the block fortify bonus times the `Mod Percent Blocked` result. A blow from an NPC and
  a blow from the player use the same code.
- Spell cost: the `SPIT` half-cost perk, if the caster owns it, then `Mod Spell Cost` on what is
  left ([magic](/engine/magic.md)).

### One discount, written twice

On the local install, `Flames` costs 24 and names `DestructionNovice00` as its half-cost perk.
That perk's only effect is `Mod Spell Cost` x 0.5. So the header field and the entry point are
the same discount. Applying both would charge 6, where the game charges 12.

So the header halving applies only when the named perk does not itself hook `Mod Spell Cost`. No
source says which one the game reads. This rule gives the observed cost either way, and still
works for a mod that sets only the header field.

The unbound spell subject has a side effect here. `DestructionNovice00`'s condition limits the
discount to novice Destruction spells. That tab is skipped, so an owner currently pays less for
every spell. It is counted like every other unbound subject.

## Abilities

An ability perk effect grants a `SPEL` while the perk is owned. A reconcile step makes the
effects from perks match the owned perks. Each granted spell's effects are applied as constant
[active effects](/engine/magic.md). Losing the perk removes exactly those.

It is a reconcile, not a hook on "add". Perks come from scripts, seeds, and loads, and a hook on
each path is one missed call away from an effect that never goes away.

Effects from perks are marked with a perk source. So the reconcile can tell a perk's ability
apart from the same spell the actor knows on its own. Removing by spell alone would remove an
effect the actor still has the perk for.

A function that selects a spell is not an ability. That spell is cast when the entry point fires,
for example on a hit, and is not carried. Nothing casts it yet.

## Scripts and conditions

- `Actor.AddPerk`, `Actor.RemovePerk`, and `Actor.HasPerk` are native functions
  ([Papyrus VM](/engine/papyrus-vm.md)). A grant also updates abilities in the same call, so a
  perk from a script is saved like any other. A session with no perk data fails with a reason,
  instead of answering "no perks".
- The `HasPerk` condition is stored index 448, Creation Kit 4544, with parameter 1 `ptPerk`. It is
  needed: it is how a rank chain turns itself off. It reads live ownership on every evaluation.
- A `HasPerk` that names a perk no loaded plugin defines is counted as unavailable. It does not
  mean "this actor does not have it". The record must exist, not only resolve, like the keyword
  rule.

## Not part of this system

- Spending perk points and tree requirements belong to
  [character leveling](/engine/character-leveling.md). `AddPerk` grants without cost, as the
  Creation Kit says. That is why the two layers are separate: quests, scripts, and races hand
  out perks that no tree gates.
- Skill experience: [skill advancement](/engine/skill-advancement.md).
- The perk tree layout comes from `AVIF`
  ([actor value information](/formats/actor-value-information.md)), not from `PERK`.
