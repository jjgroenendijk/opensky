---
type: Subsystem
title: Condition functions
description: The condition functions OpenSky answers, their sources, and where OpenSky's
  answer differs from the documented one.
tags: [engine, conditions, runtime]
---

# Condition functions

These are the condition functions OpenSky can answer. How a list is evaluated is on
[condition evaluation](/engine/conditions.md). The `CTDA` layout is on
[conditions](/formats/conditions.md).

"Stored" is the index in the plugin. The Creation Kit number is 4096 higher. Each function
reads one snapshot in the context. A function whose snapshot is missing fails with a reason;
it never guesses. Sources are the Creation Kit wiki function pages under
<https://ck.uesp.net/wiki/>, and xEdit's TES5 function table for parameter types.
`IsWeaponOut` and `GetCombatState` were read from the `creationkit.com` mirror through the
Wayback Machine (see `docs/tools/environment.md`).

## Registered functions

| stored | name | parameters | returns |
| --- | --- | --- | --- |
| 1 | `GetDistance` | reference | world units to the parameter |
| 14 | `GetActorValue` | actor-value index | current value |
| 18 | `GetCurrentTime` | none | game hour, 0 to 24; 4:30 am is 4.5 |
| 27 | `GetLineOfSight` | reference | 1 when the sight line is clear |
| 35 | `GetDisabled` | none | 1 when the reference is disabled |
| 45 | `GetDetected` | actor | 1 when the run-on actor has detected the parameter |
| 46 | `GetDead` | none | 1 when the actor is dead |
| 56 | `GetQuestRunning` | `QUST` | 1 when the quest runs |
| 58 | `GetStage` | `QUST` | highest stage reached, 0 for none |
| 59 | `GetStageDone` | `QUST`, stage | 1 when that stage was visited |
| 60 | `GetFactionRankDifference` | `FACT`, actor | own rank minus the parameter actor's rank |
| 71 | `GetInFaction` | `FACT` | 1 when a member |
| 72 | `GetIsID` | base object | 1 when the reference's base form matches |
| 73 | `GetFactionRank` | `FACT` | rank, -1 when not a member |
| 74 | `GetGlobalValue` | `GLOB` | the global's value |
| 77 | `GetRandomPercent` | none | integer 0 to 99 |
| 80 | `GetLevel` | none | level; for the player, the character level |
| 170 | `GetDayOfWeek` | none | 0 Sundas to 6 Loredas |
| 214 | `HasMagicEffect` | `MGEF` | 1 when that effect acts on the actor |
| 223 | `IsSpellTarget` | `SPEL`, `ALCH`, `INGR`, or `ENCH` | 1 when an effect from it acts on the actor |
| 249 | `IsInDialogueWithPlayer` | none | 1 when the player talks to this actor |
| 263 | `IsWeaponOut` | none | 0 nothing drawn, 2 weapon in a hand |
| 264 | `HasSpell` | `SPEL` | 1 when the actor knows the spell |
| 277 | `GetBaseActorValue` | actor-value index | base value, without modifiers |
| 323 | `GetCombatState` | none | 0 not in combat, 1 in combat, 2 searching |
| 375 | `GetCrimeGoldViolent` | `FACT` or null | violent part of the bounty |
| 376 | `GetCrimeGoldNonviolent` | `FACT` or null | non-violent part of the bounty |
| 403 | `GetRelationshipRank` | reference | 4 Lover to -4 Archnemesis |
| 426 | `GetIsVoiceType` | `VTYP` | 1 when the actor's `VTCK` matches |
| 448 | `HasPerk` | `PERK` | 1 when the actor has the perk |
| 449 | `GetFactionRelation` | actor | 0 Neutral, 1 Enemy, 2 Ally, 3 Friend |
| 459 | `GetCrimeGold` | `FACT` or null | bounty owed to the faction |
| 543 | `GetQuestCompleted` | `QUST` | 1 when the quest is completed |
| 566 | `GetIsAliasRef` | alias number | 1 when the reference fills that alias |
| 570 | `HasEquippedSpell` | casting source | 1 when that source holds a spell |
| 571 | `GetCurrentCastingType` | casting source | 0 constant, 1 fire and forget, 2 concentration |
| 572 | `GetCurrentDeliveryType` | casting source | 0 self, 1 contact, 2 aimed, 3 target actor, 4 target location |
| 632 | `IsCasting` | none | 1 while a hand charges, is ready, or concentrates |
| 640 | `GetActorValuePercent` | actor-value index | current divided by maximum, 0 to 1 |
| 699 | `HasMagicEffectKeyword` | `KYWD` | 1 when an effect with that keyword acts on the actor |
| 719 | `IsHostileToActor` | actor | 1 when hostile to the parameter actor |

Keyword, form-list, and location functions, with their use count in the active load order:

| stored | name | uses | stored | name | uses |
| --- | --- | --- | --- | --- | --- |
| 560 | `HasKeyword` | 3,501 | 610 | `LocAliasHasKeyword` | 41 |
| 359 | `GetInCurrentLoc` | 1,590 | 372 | `IsInList` | 39 |
| 562 | `LocationHasKeyword` | 755 | 444 | `GetInCurrentLocFormList` | 17 |
| 567 | `GetIsEditorLocAlias` | 445 | 604 | `IsInSameCurrentLocAsRefAlias` | 7 |
| 360 | `GetInCurrentLocAlias` | 411 | 180 | `HasSameEditorLocAsRef` | 1 |
| 605 | `LocAliasIsLocation` | 232 | 603 | `IsInSameCurrentLocAsRef` | 0 |
| 565 | `GetIsEditorLocation` | 165 | 181 | `HasSameEditorLocAsRefAlias` | 150 |

`HasKeyword` and `IsInList` test the base object. Form lists expand nested lists. Location
checks walk the parent chain and stop on a loop.

## Time, quests, and enable state

`GetDisabled` reads the runtime enable state first. Without one, it reads the
"initially disabled" flag in the REFR or ACHR header. A missing placement fails.

`GetCurrentTime` reads the game clock. Without a clock, it reads the `GameHour` global, so
an inspector or a test without a running world still gets the plugin's time. With a clock,
the clock wins ([game clock](/engine/game-clock.md)).

`GetDayOfWeek` counts from the start date of a new game. UESP `Skyrim:Calendar`
(<https://en.uesp.net/wiki/Skyrim:Calendar>) says a new game starts on the 17th of Last Seed,
a Sundas. The Creation Kit page maps 0 to Sundas. A year has 365 days and no leap day. UESP
notes one case OpenSky does not copy: loading a save before a new game keeps that save's
weekday.

`GetStage` is the highest stage reached. `GetStageDone` is "this stage was visited"
([runtime state](/engine/runtime-state.md)). A stage index above the uint16 range answers 0,
because no such stage can exist. `GetQuestCompleted` follows the fixed behavior. The
Creation Kit wiki says it always returned 0 before patch 1.9.32.

## Actors

- `IsWeaponOut` documents 0, 1 (only fists out), and 2. OpenSky tracks where the
  weapon is, not whether it is fists, so it returns 0 or 2. Raised fists give 2.
- `GetCombatState` reads the combat phase: 0 when the actor has not noticed the player or
  gave up searching, 1 when fighting, 2 when searching. A dead actor is never in combat
  ([combat](/engine/combat.md)).
- `GetDead` reads the death flag, not health. The Creation Kit says: "This is more accurate
  than checking the actor's health because there are circumstances when the actor can die
  without losing all of their health."
- Actor-value functions take an index, not a FormID (xEdit `ptActorValue`). An index that
  OpenSky does not store fails as `unresolvedParameter`.
- `GetBaseActorValue` ignores modifiers, so a potion cannot meet a perk requirement. Perk
  requirements use it: `Armsman20` needs `GetBaseActorValue One-Handed >= 20`.

## Magic

- `HasMagicEffect` and `HasMagicEffectKeyword` answer a narrower question than the game. The
  Creation Kit says the game returns 1 "even if the spell-side conditions aren't met and the
  effect isn't actually active". OpenSky stores only applied effects, so it answers "is it
  acting".
- xEdit's casting sources are `Left`, `Right`, `Voice`, and `Instant`. OpenSky has two hands
  and no voice slot, so sources 2 and 3 fail as unavailable.
- A hand with no spell has no casting type or delivery, so those functions fail.
- `HasEquippedSpell` takes only a casting source. The Creation Kit says "There is no
  selectable parameter for the Spell ID". In vanilla, 34 of its 52 conditions leave the word
  zero, which is the left hand.

Not registered yet: `GetEquippedItemType` (597, 785 uses; equipment), `SpellHasKeyword`
(596, 114), `IsWeaponMagicOut` (101, 113), `EPMagic_SpellHasKeyword` (693, 80),
`SpellHasCastingPerk` (713, 75), `EPMagic_SpellHasSkill` (696, 39), `GetReplacedItemType`
(664, 23), `EPMagic_IsAdvanceSkill` (681, 19), `IsDualCasting` (627, 4),
`HasBoundWeaponEquipped` (706, 1), `EffectWasDualCast` (724, 1).

## Factions and crime

- `GetFactionRelation` returns the Creation Kit order: 0 Neutral, 1 Enemy, 2 Ally, 3 Friend.
  The `XNAM` reaction word uses Ally 0, Friend 1, Neutral 2, Enemy 3. OpenSky maps each case.
- For a non-member, the console `GetFactionRank` returns -1. The Papyrus
  `Actor.GetFactionRank` returns -2, because -1 is a real rank. OpenSky does both.
- `GetFactionRankDifference` counts a non-member as -1. The wiki gives neither this value
  nor the order; the order follows its sentence ("the current actor and target actor").
- A pair with no `RELA` record and no script rank has no answer. Acquaintance (rank 0) is a
  real rank, so OpenSky does not assume it ([relationships](/formats/relationships.md)).
- `IsHostileToActor` has no Creation Kit page. xEdit gives the name and parameter.
  `Actor.pex` declares `bool IsHostileToActor(Actor akActor) native`. OpenSky answers with
  the same hostility rules the combat loop uses.
- `GetCrimeGold` with a null faction asks about the hold where the actor stands. No crime
  data, an unknown faction, or no hold fails. The violent and non-violent parts add up to it
  ([crime](/engine/crime.md)).

Not registered on purpose: `GetIsInFactionList` is not in xEdit's table. The five `GetPC*`
faction functions (132, 193, 195, 197, 199) need records of expulsion and faction crimes
that OpenSky does not keep. `GetKeywordDataForLocation` (606, 783 uses) returns a float
stored per location and keyword, which OpenSky does not keep.
