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
| 32 | `GetInSameCell` | reference | 1 when both stand in the same loaded cell |
| 35 | `GetDisabled` | none | 1 when the reference is disabled |
| 45 | `GetDetected` | actor | 1 when the run-on actor has detected the parameter |
| 46 | `GetDead` | none | 1 when the actor is dead |
| 47 | `GetItemCount` | item | how many the run-on holds |
| 48 | `GetGold` | none | how many `Gold001` the run-on holds |
| 56 | `GetQuestRunning` | `QUST` | 1 when the quest runs |
| 58 | `GetStage` | `QUST` | highest stage reached, 0 for none |
| 59 | `GetStageDone` | `QUST`, stage | 1 when that stage was visited |
| 60 | `GetFactionRankDifference` | `FACT`, actor | own rank minus the parameter actor's rank |
| 62 | `IsRaining` | none | 1 when the current weather is rainy |
| 67 | `GetInCell` | `CELL` | 1 when the reference stands in that cell |
| 69 | `GetIsRace` | `RACE` | 1 when the actor's race matches |
| 70 | `GetIsSex` | 0 male, 1 female | 1 when the actor has that sex |
| 71 | `GetInFaction` | `FACT` | 1 when a member |
| 72 | `GetIsID` | base object | 1 when the reference's base form matches |
| 73 | `GetFactionRank` | `FACT` | rank, -1 when not a member |
| 74 | `GetGlobalValue` | `GLOB` | the global's value |
| 75 | `IsSnowing` | none | 1 when the current weather is snowy |
| 77 | `GetRandomPercent` | none | integer 0 to 99 |
| 80 | `GetLevel` | none | level; for the player, the character level |
| 102 | `IsTorchOut` | none | 1 when the actor holds a torch out |
| 103 | `IsShieldOut` | none | 1 when the actor holds a shield out |
| 130 | `GetPCIsRace` | `RACE` | 1 when the player's race matches |
| 131 | `GetPCIsSex` | 0 male, 1 female | 1 when the player has that sex |
| 136 | `GetIsReference` | reference | 1 when the run-on is that reference |
| 149 | `GetIsCurrentWeather` | `WTHR` | 1 when that weather is current or coming in |
| 159 | `GetSitting` | none | 0 not sitting, 2 getting ready to sit, 3 sitting |
| 170 | `GetDayOfWeek` | none | 0 Sundas to 6 Loredas |
| 182 | `GetEquipped` | item | 1 when the actor has it equipped |
| 214 | `HasMagicEffect` | `MGEF` | 1 when that effect acts on the actor |
| 223 | `IsSpellTarget` | `SPEL`, `ALCH`, `INGR`, or `ENCH` | 1 when an effect from it acts on the actor |
| 248 | `IsScenePlaying` | `SCEN` | 1 while the scene plays |
| 249 | `IsInDialogueWithPlayer` | none | 1 when the player talks to this actor |
| 263 | `IsWeaponOut` | none | 0 nothing drawn, 2 weapon in a hand |
| 264 | `HasSpell` | `SPEL` | 1 when the actor knows the spell |
| 266 | `IsPleasant` | none | 1 when the current weather is pleasant |
| 277 | `GetBaseActorValue` | actor-value index | base value, without modifiers |
| 286 | `IsSneaking` | none | 1 while the actor sneaks |
| 289 | `IsInCombat` | none | 1 while fighting or searching |
| 310 | `GetInWorldspace` | `WRLD` | 1 in an exterior cell of that worldspace |
| 313 | `GetPairedAnimation` | none | 1 while the actor plays a paired animation; always 0 |
| 323 | `GetCombatState` | none | 0 not in combat, 1 in combat, 2 searching |
| 353 | `IsActor` | none | 1 when the run-on is an actor |
| 362 | `HasLinkedRef` | `KYWD` or null | 1 when an `XLKR` link has that keyword |
| 365 | `IsChild` | none | 1 when the actor's race has the child flag |
| 391 | `IsPC1stPerson` | none | 1 when the player uses the first-person camera; camera paths only |
| 375 | `GetCrimeGoldViolent` | `FACT` or null | violent part of the bounty |
| 376 | `GetCrimeGoldNonviolent` | `FACT` or null | non-violent part of the bounty |
| 403 | `GetRelationshipRank` | reference | 4 Lover to -4 Archnemesis |
| 426 | `GetIsVoiceType` | `VTYP` | 1 when the actor's `VTCK` matches |
| 430 | `GetHealthPercentage` | none | health over its maximum, 0 to 1 |
| 448 | `HasPerk` | `PERK` | 1 when the actor has the perk |
| 449 | `GetFactionRelation` | actor | 0 Neutral, 1 Enemy, 2 Ally, 3 Friend |
| 459 | `GetCrimeGold` | `FACT` or null | bounty owed to the faction |
| 543 | `GetQuestCompleted` | `QUST` | 1 when the quest is completed |
| 550 | `IsSceneActionComplete` | `SCEN`, action | 1 when that action is done in this run |
| 561 | `HasRefType` | `LCRT` | 1 when the reference has that location ref type |
| 566 | `GetIsAliasRef` | alias number | 1 when the reference fills that alias |
| 570 | `HasEquippedSpell` | casting source | 1 when that source holds a spell |
| 571 | `GetCurrentCastingType` | casting source | 0 constant, 1 fire and forget, 2 concentration |
| 572 | `GetCurrentDeliveryType` | casting source | 0 self, 1 contact, 2 aimed, 3 target actor, 4 target location |
| 590 | `IsInScene` | none | 1 while a playing scene holds the actor |
| 594 | `GetIsFlying` | none | 1 while the actor flies; always 0 |
| 613 | `IsFurnitureAnimType` | animation type | 1 when the actor's marker has that type |
| 614 | `IsFurnitureEntryType` | entry | 1 when the actor enters from that side |
| 629 | `GetVMQuestVariable` | `QUST`, variable (`CIS2`) | the quest script's variable |
| 630 | `GetVMScriptVariable` | reference, variable (`CIS2`) | the object script's variable |
| 631 | `IsEnteringInteractionQuick` | none | always 0 |
| 632 | `IsCasting` | none | 1 while a hand charges, is ready, or concentrates |
| 640 | `GetActorValuePercent` | actor-value index | current divided by maximum, 0 to 1 |
| 644 | `IsInFurnitureState` | animation type | 1 while seated on a marker of that type |
| 650 | `IsLinkedTo` | reference, `KYWD` or null | 1 when the run-on links to it |
| 659 | `EPTemperingItemIsEnchanted` | none | 1 when the item a tempering recipe improves is enchanted |
| 675 | `GetGraphVariableInt` | variable name (`CIS1`) | the actor's graph variable |
| 681 | `EPMagic_IsAdvanceSkill` | actor-value index | 1 when the credited use trains that skill |
| 691 | `EPModSkillUsage_AdvanceObjectHasKeyword` | `KYWD` | 1 when the use's object has the keyword |
| 692 | `EPModSkillUsage_IsAdvanceAction` | action | 1 when the use's action matches (0 normal to 4 lockpick broken) |
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

`HasKeyword` and `IsInList` test the base object. The keyword data indexes the base types that
carry `KWDA`: actors (`NPC_`, `RACE`), activators, furniture, flora, and items. The Papyrus
`Form.HasKeyword` reads the same data. Form lists expand nested lists. Location
checks walk the parent chain and stop on a loop.

## Script variables

`GetVMQuestVariable` and `GetVMScriptVariable` read a Papyrus variable. The `CTDA` word
for parameter 2 is not a name. In `Skyrim.esm` every one of these conditions (4,584 and
91) carries a `CIS2` with the variable, for example `::MarkarthMarket_var`, the hidden
variable behind an auto property. The Creation Kit wiki says only `Int`, `Float`, and
`Bool` properties work, so OpenSky offers only those, with `Bool` as 0 or 1. A variable
that no live script instance declares fails as unavailable. `GetVMScriptVariable` reads
the object parameter 1 names, not the run-on reference.

## Scenes

`IsSceneActionComplete` takes the action's `INAM` index, which the wiki calls the
"SceneActionID". A scene that does not play answers 0, because a new run starts with no
action done. `IsInScene` is true while a playing scene holds the actor, the same rule that
keeps a held actor out of a second scene ([dialogue](/engine/dialogue.md)).

## Places

`GetInCell`, `GetInWorldspace`, and `GetInSameCell` read the loaded cell that holds the
reference. A reference outside the loaded cells fails as unavailable. The wiki notes that
`GetInCell` needs an exact cell, not a name prefix as in older games. `GetInWorldspace` is 0
in an interior.

## References

- `GetIsReference` and `IsLinkedTo` accept a parameter that is not loaded: OpenSky resolves
  the FormID to its key, and `PlayerRef` means the player.
- `HasLinkedRef` and `IsLinkedTo` read `XLKR` as the plugin wrote it. A link a script sets at
  run time is not seen yet. A null keyword asks for the untagged link.
- `IsLinkedTo` has no wiki page. xEdit gives a reference and a keyword. OpenSky reads it as
  "the run-on links to the reference under the keyword". Vanilla uses it in quest alias
  conditions with an alias as the reference.
- `HasRefType` reads the reference's own `XLRT`, and every location that lists it under
  `LCSR` or `ACSR`, without the ones `RCSR` removes.

## Weather

The weather functions read the weather the sky is moving toward. The wiki says
`GetIsCurrentWeather` "will return true as soon as the weather starts transitioning into the
specified weather". `IsPleasant`, `IsRaining`, and `IsSnowing` read the `WTHR DATA`
classification ([weather](/formats/weather.md)). Indoors no weather runs, so they fail as
unavailable; the game keeps the outside weather.

## Inventory

`GetGold` counts `Gold001` (`Skyrim.esm` 0x0F). It and `GetEquipped` read the player only;
another actor fails as unavailable.

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
- `IsTorchOut` and `IsShieldOut` read what the left hand holds out. OpenSky draws no
  torch, and a shield comes out only with a drawn weapon. So an actor whose weapon is
  sheathed, or an NPC that is not fighting, holds nothing out and both return 0. An NPC
  in a fight has no tracked draw state, so both fail as unavailable. Vanilla idle markers
  test these two, for example the sweeping and warm-hands idles.
- `GetIsSex` reads the `ACBS` female flag after template inheritance through "use traits".
  For the player, it and `GetPCIsSex` read the race menu choice. `GetPCIsRace` ignores the
  run-on.
- `IsInCombat` is 1 while fighting and while searching, the two non-zero `GetCombatState`
  values. The wiki only says "currently in combat".
- `IsSneaking` reads the player's gait. No NPC gait is tracked, so an NPC fails as
  unavailable.
- `IsChild` reads the race's `DATA` flag 0x04 (xEdit `dev-4.1.6`, `wbRACE_DATAFlags01`).
- `GetIsRace` compares the race the actor's values were derived from. An actor whose race
  is not known fails as unavailable.
- `GetPairedAnimation` and `GetIsFlying` return 0. OpenSky plays no paired animation, such
  as a kill move, and no actor flies yet. The systems that add them set the actor state.
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
(664, 23), `IsDualCasting` (627, 4),
`HasBoundWeaponEquipped` (706, 1), `EffectWasDualCast` (724, 1).

## Furniture

The furniture functions read how the actor uses a furniture marker. Only the idle runtime fills
this data, when a package seats an actor ([Idle runtime](/engine/idle-runtime.md#furniture)).
Elsewhere they fail with the furniture reason.

- The `GetSitting` values come from the Creation Kit wiki page "GetSitting". OpenSky uses 0, 2,
  and 3: 2 while the entry idle is picked, 3 after.
- The parameter enums come from xEdit `wbDefinitionsTES5.pas`: animation type 1 Sit, 2 Lay,
  4 Lean; entry `0x10000` Front, `0x20000` Behind, `0x40000` Right, `0x80000` Left,
  `0x100000` Up. A NIF marker stores the same entry bits 16 places lower.
- `IsEnteringInteractionQuick` is always 0, because OpenSky has no quick entry.
- `GetGraphVariableInt` names its variable in `CIS1`. An NPC runs no live graph in OpenSky, so
  each of its variables reads 0; the furniture tree tests `bInJumpState` == 0 this way. The
  player's graph is not read yet, so the function fails for the player.
- While an actor sits, the furniture reference is the condition Target (run-on 1). The
  chopping block's idle tree runs `HasKeyword FurnitureExecutioner` on the Target, and only
  the block has that keyword.

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
