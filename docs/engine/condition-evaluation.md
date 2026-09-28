---
type: Subsystem
title: Condition evaluation
description: How OpenSky answers a condition list - comparison, OR grouping, run-on targets,
  the choices behind individual functions, and the failure tally.
tags: [engine, conditions, quests, actors, magic, factions]
---

# Condition evaluation

This page explains how OpenSky answers "is this condition list true right now?". The byte
layout is on the [conditions](/formats/conditions.md) page.

The evaluator lives under `opensky/Engine/World/Conditions/`, not beside the decoder. A
condition needs runtime state that a format parser must never touch: global values, the game
clock, quest state, actor state, and the reference index
([runtime state](/engine/runtime-state.md)).

Sources: the Creation Kit wiki [Conditions](https://ck.uesp.net/wiki/Category:Conditions)
page and one page per function; xEdit's TES5 condition function table for names and parameter
types; UESP [Skyrim:Calendar](https://en.uesp.net/wiki/Skyrim:Calendar).

## Comparing one condition

A condition is `functionResult <operator> comparisonValue`. Both sides are floats.

Equality is exact. Neither UESP nor the Creation Kit gives a tolerance, and a tolerance nobody
documented would be a hidden difference from the game. Operators 6 and 7 give false with a
reason.

With the "use global" flag, the comparison value is a `GLOB`. If no plugin defines it, the
condition fails with "unresolved global". It does not compare against 0, because 0 is a value a
mod may really compare against.

## OR grouping

The Creation Kit wiki says the OR flag replaces the operator between condition N and N+1 with
OR. So:

- OR-joined conditions form one block, and blocks join with AND. OR binds tighter than AND. The
  wiki's example `A AND B OR C AND D` means `A AND (B OR C) AND D`.
- An OR flag on the last condition has nothing to join. OpenSky ends the block there.
- An empty list is true.

The evaluator never stops early. It evaluates every condition, so the tally covers the whole
list.

## Run-on targets

- Subject, target, and reference come from the context. The swap flag swaps subject and target.
- Quest alias uses parameter 3 as the alias number. The quest is the one that owns the
  condition, because a `CTDA` never names a quest. A list that belongs to no quest, such as a
  `MUST` record's, has no alias table.
- Combat target asks who the run-on actor is fighting. The player fights the nearest hostile
  living actor, and every engaged living actor fights the player. A dead actor fights nobody.
- Linked reference, package data, and event data are not supported. They fail with
  "unsupported run-on".
- A supported run-on whose object is missing fails with "unresolved reference". This is a
  different failure: the caller must give a better context, not OpenSky more engine.

A function asks for its object only if it needs one. So `GetCurrentTime` works with no subject.

Getting an object has two steps: which world identity, and which record stands behind it.
`GetIsID` needs the record. Actor functions need only the identity. The player has an identity
but no plugin record, so this split lets actor conditions about the player work.

`GetRandomPercent` draws from a seeded SplitMix64 generator. The same seed gives the same
draws.

## Choices behind functions

The registry is `ConditionFunctionRegistry.standard`. Most functions do what the Creation Kit
page says. These are the cases where OpenSky had to choose.

Time:

- `GetCurrentTime` reads the game clock. With no clock, it reads the `GameHour` global. So a
  tool with no running world still gets the plugin's time of day. With a clock, the clock always
  wins ([game clock](/engine/game-clock.md)).
- `GetDayOfWeek` counts from the vanilla start date, not the clock's first day. UESP says a new
  game starts on the 17th of Last Seed, a Sundas. The wiki says 0 is Sundas. A year has 365
  days, so the weekday moves one step each day.

Quests (see [runtime state](/engine/runtime-state.md)):

- `GetStageDone` with a stage above the uint16 range gives 0. No such stage can exist.
- `GetQuestCompleted` uses the fixed behavior. The wiki says the original returned 0 always until
  patch 1.9.32. Copying a patched bug would make every correct condition wrong.
- A quest parameter that names no quest fails. "This quest does not exist" and "this quest has
  not started" are different answers.

Actors:

- `IsWeaponOut` is documented as 0 (nothing drawn), 1 (fists only), or 2 (weapon). OpenSky
  gives 0 and 2, never 1, because it tracks where the weapon is, not whether the actor is
  unarmed. If nothing tracks an actor's draw state, the condition fails. It does not answer
  "sheathed".
- `GetCombatState` gives 0, 1 (fighting), or 2 (searching), from the combat phase, not from
  hostility. A dead actor is never in combat ([combat](/engine/combat.md)).
- `GetDead` reads the death flag, not health. The wiki: "This is more accurate than checking the
  actor's health because there are circumstances when the actor can die without losing all of
  their health."
- `GetBaseActorValue` ignores modifiers. A vanilla perk such as `Armsman20` needs
  `GetBaseActorValue One-Handed >= 20`, so a potion cannot buy a perk.
- Actor value functions take an index, not a FormID. An index OpenSky does not store fails with
  "unresolved parameter". That is kept apart from "no actor state in the context".

Magic ([magic](/engine/magic.md)):

- `HasMagicEffect` and `HasMagicEffectKeyword` answer a narrower question. The wiki says the
  original returns 1 when the effect's own conditions pass, "even if the spell-side conditions
  aren't met and the effect isn't actually active". OpenSky stores only applied effects, so it
  answers "is the actor affected". Every running effect gives the same answer either way.
- The casting source is Left, Right, Voice, or Instant (xEdit `wbCastingSourceEnum`). OpenSky has
  two hands and no voice slot, so Voice and Instant fail.
- A hand with no spell has no casting type or delivery, so those two functions fail for it.
- `HasEquippedSpell` takes only a casting source. The wiki says the spell parameter cannot be
  set, and xEdit types the one parameter as a casting source.

Factions and relationships ([factions](/formats/factions.md),
[relationships](/formats/relationships.md)):

- An actor no cell has loaded has no faction data. Its functions fail. They do not answer
  "belongs to nothing".
- `GetFactionRelation` returns 0 Neutral, 1 Enemy, 2 Ally, 3 Friend, as the wiki says. The
  `XNAM` field numbers them Ally 0, Friend 1, Neutral 2, Enemy 3. OpenSky maps each case by
  name, because the two tables come from different sources.
- `GetFactionRank` gives -1 for a non-member, as the console function does. The Papyrus function
  `Actor.GetFactionRank` gives -2, and keeps -1 for a real rank of -1. OpenSky does both, each
  where it belongs.
- `GetFactionRankDifference` counts a non-member as -1, like `GetFactionRank`. The wiki does
  not say.
- A pair with no `RELA` record and no script rank fails. It does not answer Acquaintance (0),
  because 0 is a rank vanilla uses on purpose.
- `IsHostileToActor` has no Creation Kit page. OpenSky answers it with the same hostility rules
  the combat loop uses.
- `GetCrimeGold` with a null faction asks about the hold the actor stands in. No crime data, an
  unknown faction, or a null faction outside a hold fails. See [crime](/engine/crime.md).

Left out on purpose:

- `GetIsInFactionList` is not in xEdit's table. `IsInList` (372) tests the base object, not
  faction membership.
- The `GetPC*` faction functions need expulsion and faction crime records that OpenSky does not
  keep. Answering "no" would be a wrong answer that looks right.
- `GetKeywordDataForLocation` returns a runtime float stored per location and keyword. OpenSky
  does not keep it, and answering 0 would hide the gap.
- `GetEquippedItemType` looks like a magic function, because its parameter is a casting source.
  It reports the item type in a hand, so it belongs with equipment.

## Index 77 is GetRandomPercent

xEdit puts `GetRandomPercent` at stored index 77. An older list suggests 76. Vanilla data
decides: index 76 never appears in `Skyrim.esm`. Every condition at 77 has zero parameters, and
compares against values from 0 to 100 or a global. That is the shape of a percentage roll.

## Failures and the tally

The evaluator never throws. A condition it cannot answer is false, with a reason. Examples:
unknown function, unresolved global, unresolved quest, unsupported run-on, unresolved
reference, unresolved parameter, and "unavailable" for a missing part of the context (clock,
actor state, detection, dialogue, data stores, magic, perks, crime, factions).

The result has three parts: the answer, the failures, and whether the answer is conclusive. A
caller that only wants true or false ignores the rest. A caller that cares checks
`isConclusive`.

Every failure is also counted in `ConditionTally`, which follows the same pattern as the
[ActionScript runtime](/engine/as2-runtime.md) tally. It answers: "which functions does
OpenSky still miss, and how often are they used?". That list decides which functions to add
next. Name tables stop at a fixed size, but the totals keep counting.

An unknown function is a counted false, not an error. So adding a function only adds. Nothing
that already works changes.

To see which functions the installed plugins need, run the real-data condition suites
(`make realtest`). They write the full tally to `logs/condition-sweep.log`.
