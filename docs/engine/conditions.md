---
type: Subsystem
title: Condition evaluation
description: How OpenSky answers a CTDA condition list — comparison, OR grouping, run-on
  resolution, the evaluation context, and the failure tally.
tags: [engine, conditions, runtime]
---

# Condition evaluation

This page explains how OpenSky answers "is this condition list true right now?". The
`CTDA` layout is on [conditions](/formats/conditions.md). The functions and their special
cases are on [condition functions](/engine/condition-functions.md).

The evaluator lives under `Sources/OpenSkyEngine/World/`, not beside the decoder. It needs runtime
state that a format parser must never touch: globals, the game clock, and the runtime
reference index ([runtime state](/engine/runtime-state.md)).

## Comparing one condition

A condition tests `functionReturn <operator> comparisonValue`. Both sides are `Float`.

Equality is exact. Neither UESP nor the Creation Kit wiki gives a tolerance for "equal to" or
"not equal to". A tolerance that nobody documented would be a hidden difference from the
game, so OpenSky compares directly. The undefined operators 6 and 7 give false with a reason.

With the use-global flag (`0x04`), the comparison value is a `GLOB` FormID. If no plugin
defines that global, the condition fails as `unresolvedGlobal`. It does not compare against
zero, because zero is a real value that a mod can test for.

## OR grouping

The Creation Kit wiki Conditions page says the OR flag replaces the operator *between*
condition N and condition N+1. Two results follow:

- OR-joined conditions form one block, and blocks join with AND. So OR binds tighter than
  AND. The wiki's example `A AND B OR C AND D` means `(A AND (B OR C) AND D)`.
- An OR flag on the last condition has no next operator to replace. The rule does not cover
  this case. OpenSky ends the block with the list.

An empty list is true: a record without conditions always applies.

The evaluator never stops early. It evaluates every condition, so the tally covers the whole
list.

## Run-on resolution

The run-on type picks the object that the function runs on.

- Subject and target come from the context. Reference looks up the FormID at offset 24 in
  the runtime reference index. The swap flag (`0x10`) applies here.
- Quest alias (5): the alias index is parameter 3 at offset 28. A `CTDA` never names the
  quest. The quest is the record the condition came from, so the context carries it. A list
  that belongs to no quest (for example a `MUST` record) has no alias table, and every
  alias lookup fails.
- Combat target (3): the combat target of the actor the condition runs on. The player
  fights the nearest hostile living actor, and every hostile living actor fights the player.
  A dead actor fights nobody.
- Linked reference, package data, event data, and unknown values fail as
  `unsupportedRunOn`. That means a missing subsystem.
- A supported run-on that names nothing the context can give — no subject, an unknown key,
  or an empty alias — fails as `unresolvedReference`. That means the caller gave a weak
  context.

Resolution is lazy. A function asks for a reference only when it needs one. So
`GetCurrentTime` works with no subject at all.

Resolution has two steps. The first step finds the world identity (`ReferenceKey`). The
second step finds the record behind it. `GetIsID` compares base forms, so it needs both.
Actor functions need only the first. The player has a `ReferenceKey` but no plugin record,
so actor conditions about the player still work.

## The evaluation context

`ConditionContext` is a value type. It holds read-only snapshots: globals, quests, quest
aliases, actor state, enable state, the clock, the runtime reference index, subject and
target, a random source, and the snapshots for data, magic, factions, crime, perks,
detection, and dialogue. A caller off the main actor builds its own context from a snapshot.

`ConditionRandom` is a SplitMix64 value type. The engine seeds it once per session. The same
seed gives the same draws.

## Failures and the tally

The evaluator never throws. A condition it cannot answer is false and carries a
`ConditionFailure` that says why: `unknownFunction`, `unresolvedGlobal`, `unresolvedQuest`,
`unsupportedRunOn`, `unresolvedReference`, `unknownOperator`, `unresolvedParameter`, or one
of the `unavailable...` cases for a missing snapshot (clock, actor state, detection,
dialogue, data, magic, perks, crime, factions).

Some choices keep two different answers apart:

- A `QUST` parameter that names no quest is `unresolvedQuest`, not a stopped quest at stage
  zero. "This quest does not exist" and "this quest has not started" are different.
- `unresolvedParameter` means a `CIS1`/`CIS2` alias name that matches no filled alias, or an
  actor value that OpenSky does not store.
- `ConditionOutcome` has `isTrue` and `isConclusive`. `isConclusive` is true only when the
  answer came from real evaluation.

Every failure also goes into `ConditionTally`. The tally answers "which condition functions
does OpenSky still need, and how often are they used?". It follows `AS2Tally` in the
[ActionScript 2 runtime](/engine/as2-runtime.md). Each name table stops at 64 names, but the
totals keep counting.

An unknown function is a counted false, not an error. So adding a function never changes
code that already works.

## Measured demand

The whole active load order has 118,494 conditions using 258 function indices. Counting how
often each index appears decides which functions to add next. Two families show the method:

| family | functions | conditions |
| --- | --- | --- |
| keyword, form list, location | 14 | 7,354 |
| magic | 8 | 618 |

`GetIsID` alone is 22.9% of all conditions in `Skyrim.esm`, and `GetStage` and
`GetStageDone` are another 14.6%. Magic functions are many but rarely used, because vanilla
gates magic mostly through perks and equipment. `GetEquippedItemType` (stored 597, 785
conditions) looks like a magic function because its parameter is a casting source. It
reports the item type in a hand, so it belongs with equipment.

A full sweep writes every tally bucket to `logs/condition-sweep.log`. That file is
gitignored because it comes from the user's own plugins.
