---
type: Subsystem
title: Perks at runtime
description: Owning perks on an actor, the entry-point evaluator every combat and magic
  formula queries, which entry points are covered, the condition-tab subjects the engine can
  and cannot bind, and the seams perks are wired into.
tags: [engine, progression, perks, combat, magic, conditions, runtime-state]
timestamp: 2026-08-19T00:00:00Z
---

# Perks at runtime

The record side is [perks](/formats/perks.md): what a PERK is, how its effect sections
decode, and how `PerkStore` indexes entry points across the load order. This page is the
runtime half — who owns a perk, and what an owned perk does to a number.

Two questions, kept apart on purpose:

- **Ownership** is a world-state component and a mutation layer over it (`PerkState`,
  `PerkRuntime`), the same shape a spellbook has.
- **Evaluation** is a pure fold over function payloads (`PerkEntryPointEvaluator`) wrapped in
  a runtime that gathers owned effects and runs their conditions
  (`PerkRuntimeEvaluation.swift`).

## Contents

- Owning a perk
- Ranks are chains, not numbers
- The entry-point evaluator
- Which entry points are covered
- Condition tabs and the subjects they run against
- Wired seams
- Abilities
- Scripting and conditions
- What is deliberately absent

## Owning a perk

`PerkState` stores a flat, ascending list of owned PERK identities and nothing else. Every
mutation goes through `PerkRuntime`, which writes through `WorldStateStore`, so a grant lands
in the journal, the dirty counts and the save exactly as learning a spell does
([runtime state](/engine/runtime-state.md)). The component is dropped once it empties, so an
actor that owns no perk is not dirty for the slot.

Two rules of direction, the same pair the spellbook applies:

- Adding a perk this load order does not carry is **refused** and counted
  (`PerkRuntimeTally.unresolvedPerks`). A key nothing resolves could never be evaluated.
- A *stored* key that stops resolving is **kept**. Removing a plugin must not destroy
  progress; the key is simply invisible to every query that goes through `PerkStore`.

NPCs are seeded from their own `PRKR` run, resolved through the template chain on the ACBS
`Use Spell List` flag — UESP names that bit "Use spelllist (both spells and perks)", so an
actor delegating its spell list delegates its perk list with it
(`ActorPerkBaselineResolver`). The seed is lazy and idempotent, exactly like the spell grant:
it happens the first time anything asks about that actor rather than for every resident actor
at cell build, because a cell of townsfolk who never fight would otherwise write a component
each to say what their base records already say.

The player is seeded **empty** — no component at all. There is no NPC_ record behind the
player in this engine, and the perks a player has are the ones they took.

Owned perks travel in the save's `PRKS` chunk, one entry per actor that owns at least one.
Only identities are written: a rank is derived from the chain and the abilities perks grant
are re-established on load by the same reconcile that grants them, so nothing here duplicates
what `AEFF` already carries.

## Ranks are chains, not numbers

Each rank of a vanilla perk is a separate PERK record joined by `NNAM`, and the game adds the
record for the rank it wants. Taking the second rank of Armsman adds `Armsman20`; `Armsman00`
then switches *itself* off, because its perk-owner condition tab is
`HasPerk Armsman20 == 0` — read off this machine's install, and pinned by
`PerkRuntimeRealDataTests`.

So there is no stored rank number. `PerkRuntime.rank(inChainFrom:on:)` walks the `NNAM` chain
and answers the position of the deepest owned record: 0 when none is owned, 1 for the head
alone, and the deepest position otherwise. Deepest rather than a count, because a script may
grant a later rank without the earlier ones and reporting "rank 1" for an actor holding the
fifth record would be wrong.

The `PRKR` rank byte is not stored either. UESP records it as dead: "uint8 Rank (no longer in
use)".

## The entry-point evaluator

`PerkEntryPointEvaluator` is pure: given a value and a list of operands — a function, its
`EPFD` payload and its `PRKE` priority — it returns the modified value plus a count of what
applied and a reason for everything that did not. No store, no world, no conditions, so every
rule below is a plain assertion in a test.

The arithmetic is UESP's "Function Types" table, quoted per function:

| Id | Function | New value | Implemented |
| --- | --- | --- | --- |
| 01 | Set Value | `VALUE` | yes |
| 02 | Add Value | `Value + AMOUNT` | yes |
| 03 | Multiply Value | `Value * FACTOR` | yes |
| 04 | Add Range to Value | `Value + random(MIN, MAX)` | no — see below |
| 05 | Add Actor Value Mult | `Value + AV * FACTOR` | yes |
| 06 | Absolute | `Abs(Value)` | yes |
| 07 | Negative ABS Value | `-Abs(Value)` | yes |
| 08 | Add Level List | list-valued | no |
| 09 | Add Activate Choice | button-valued | no |
| 0A | Select Spell | spell-valued | no |
| 0B | Select Text | text-valued | no |
| 0C | Set AV Mult | `AV * FACTOR` | yes |
| 0D | Multiply AV Mult | `Value * AV * FACTOR` | yes |
| 0E | Multiply 1 + AV Mult | `Value * (1 + AV * FACTOR)` | yes |
| 0F | Set Text | text-valued | no |

`Add Range to Value` is the one *numeric* function left out. Neither UESP nor xEdit documents
the distribution or the seed, and inventing one would make a formula that is supposed to be
reproducible depend on a number this engine made up. It is counted like the others.

Everything a function cannot do is a counted no-op, never a zero: an unsupported function, a
missing or mismatched payload, an actor value the caller cannot read, and a result that comes
out non-finite all leave the value exactly as it arrived. That is the identity rule the whole
subsystem follows — **an entry point nothing implements never changes a number**.

### Ordering

The `PRKE` priority byte is the only ordering a record carries, and UESP is candid about it:
"Priority - Assumed to be how to order/iterate through perk sections". OpenSky folds operands
in **descending priority**, ties in the caller's order — which `PerkStore`'s entry-point index
has already fixed to `(priority, plugin, object id, effect position)`, so the same load order
always folds the same effects in the same sequence.

Ordering only changes an answer when a `Set Value` competes with something else: addition and
multiplication over the rest commute. The choice is recorded here rather than presented as
certain.

## Which entry points are covered

Coverage is a property of the *function*, not of the entry point id. The evaluator answers
for any of the 92 entry points whose owned effects use one of the nine numeric functions
above, and every entry point id the name table does not know still evaluates — to identity.

What differs per entry point is whether a formula asks. Wired today:

| Entry point | Id | Asked by |
| --- | --- | --- |
| Mod Attack Damage | 35 | melee swing and bow shot damage |
| Mod Percent Blocked | 39 | the blocked fraction, both directions of a fight |
| Mod Spell Cost | 38 | every cast's magicka cost |

Those three are the first, fourth and — for blocking — the entry point vanilla's Shield Wall
chain hooks; `Mod Attack Damage` alone is 81 of the 622 entry-point effects in the install
([perks](/formats/perks.md) has the full histogram). Every other entry point is *evaluable*
and simply has no caller yet: nothing asks about lockpicking, prices, detection, tempering or
enchanting because those formulas do not exist in this engine.

`Mod Bow Zoom` (20) is the closest near miss: Eagle Eye's zoom is an entry point, and the
archery graph variables it would drive (`bowZoom`, `bAimActive`) are still absent
(`ArcheryGraphNames`).

## Condition tabs and the subjects they run against

An entry-point effect carries one to three `PRKC` condition tabs. The `PRKC` byte is an index
into the entry point's own documented condition-type list, not a run-on type: for
`Mod Attack Damage` the list is (Perk Owner, Weapon, Target), so tab 1 is asked about the
weapon. `PerkConditionSubject` transcribes that column of UESP's "Perk Effect Types" table for
all 92 entry points.

A caller binds the subjects it knows. A melee formula knows the perk owner and the target; it
cannot bind `weapon`, `item`, `enchantment` or `spell`, because those name inventory and
record forms rather than placed references the condition machinery can run `HasKeyword`
against.

**A tab whose subject the caller did not bind is skipped and counted**
(`PerkRuntimeTally.unboundConditionSubjects`), not failed. This is a deliberate
over-application and the one place the subsystem is knowingly wrong: `Armsman00`'s weapon tab
checks that the weapon is one-handed, so with the tab skipped the perk currently raises
two-handed damage as well. Failing the tab instead would make every vanilla damage perk inert,
which is a worse wrong answer and a silent one. The counter is how much of it happened, and to
what.

A tab that *is* bound is evaluated strictly through the ordinary `ConditionEvaluator`
([conditions](/formats/conditions.md)): an unimplemented function is the usual reason-tagged
false, and the effect does not apply.

## Wired seams

Each seam multiplies the perk term into the same place the fortify term already occupied,
which is the shape UESP "Skyrim:Weapons" gives:
`... * (1 + perk effects) * (1 + item effects) * (1 + potion effect)`.

- **Melee** (`GameViewController.meleeAttackMultiplier`) — `CombatFortifyBonus.melee` times
  the `Mod Attack Damage` multiplier, into `MeleeDamage`'s `attackMultiplier`
  ([melee combat](/engine/melee-combat.md)).
- **Archery** (`archeryAttackMultiplier`) — the same entry point beside
  `CombatFortifyBonus.archery` ([archery](/engine/archery.md)).
- **Blocking** (`meleeBlockMultiplier`) — `CombatFortifyBonus.block` times the
  `Mod Percent Blocked` multiplier, into `MeleeDamage`'s `bonusMultiplier`. Both directions of
  a fight route through it, so a blow from an NPC and a blow from the player are reduced by
  one implementation. This also closes the M19 gap where the block fortify term was computed
  and never supplied.
- **Spell cost** (`CasterRuntime.cost(of:caster:)`) — the SPIT half-cost perk *when the caster
  owns it*, then `Mod Spell Cost` over what is left. The SPIT link was decoded in M19 and
  consumed by nobody; the ownership check is what this item adds
  ([magic](/engine/magic.md)).

### One discount, authored twice

Measured on this machine's install on 2026-08-19: `Flames` costs 24 and names
`DestructionNovice00` as its SPIT half-cost perk, and that perk's only effect is
`Mod Spell Cost` x 0.5. The header field and the entry point are the same discount written
down twice, so applying both would charge 6 where the game charges 12.

The header halving therefore applies only when the perk it names does **not** hook
`Mod Spell Cost` itself. Which of the two mechanisms the original engine reads is not
documented anywhere this project can cite; the number it charges is observable, and this rule
reproduces it under either reading while still honouring a mod that authors the header field
alone.

Note the second-order consequence of the unbound `spell` subject: `DestructionNovice00`'s
condition tab runs against the spell and gates the discount to novice Destruction spells. That
tab is skipped here, so an owner of the perk currently pays less for every spell, not only for
that school. Counted like every other unbound subject.

## Abilities

An ability-type perk effect grants a SPEL for as long as the perk is owned.
`PerkAbilityApplication.reconcile` makes the stored perk-sourced effects match the owned set:
the whole effect list of each granted spell is applied as `constant` effects through the M19
active-effect runtime, and losing the perk dispels exactly those.

It is a reconcile rather than an add hook for the reason worn enchantments are
([magic](/engine/magic.md)): perks arrive from a script, a seed and a load, and hanging the
grant off each door would be one missed call away from an effect that never comes off. Calling
it twice changes nothing.

`ActiveEffectSourceKind.perk` exists so the reconcile can tell a perk's ability from the same
spell an actor also knows in its own right. Dispelling by source record alone would take off
an effect the actor still owns the perk for.

An entry-point function that *selects* a spell is not an ability: that spell is cast when the
entry point fires — a combat hit, a bash — not carried. Nothing casts it yet.

## Scripting and conditions

- `Actor.AddPerk`, `Actor.RemovePerk` and `Actor.HasPerk` are registered
  ([Papyrus VM](/engine/papyrus-vm.md)). A grant goes through `PerkRuntime` and reconciles
  abilities in the same call, so a scripted perk is saved exactly like a seeded one. A session
  with no perk data is a reason-tagged failure rather than an actor who has taken nothing.
- The `HasPerk` condition function is stored index 448, Creation Kit 4544, parameter 1
  `ptPerk`. It is not an optional extra: it is what makes a rank chain switch itself off. The
  seam it reads is `PerkConditionResolution` on `ConditionContext`, rebuilt from the store per
  evaluation so a perk's own condition always sees live ownership.
- A `HasPerk` parameter naming a perk no loaded plugin defines is `unavailablePerks`, not
  "this actor does not have it". Plugin-relative resolution would answer with an identity for
  any FormID whose plugin is loaded, so the record has to exist, not merely resolve — the same
  rule the keyword seam applies.

## What is deliberately absent

- Perk-point spending and tree prerequisites, which are
  [character leveling](/engine/character-leveling.md)'s: `PerkTreeSpendValidator` is the only
  place a tree, a rank order and a skill requirement gate a grant. `AddPerk` still grants
  without charging anything, which is what the Creation Kit says it does, and that is exactly
  why the two layers are separate — a quest, a script and a race all hand out perks no tree
  gates.
- Skill XP and level-ups ([skill advancement](/engine/skill-advancement.md) and
  [character leveling](/engine/character-leveling.md)).
- Any perk UI (item 20.7). The perk tree's layout comes from AVIF
  ([actor value information](/formats/actor-value-information.md)), not from PERK.
- A caller for every entry point but the three wired above. They evaluate; nothing asks.
