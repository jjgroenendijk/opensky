---
type: Subsystem
title: Papyrus script state
description: The flags, values, form links, and added forms that Papyrus natives set when no other
  runtime holds them, how they are read back and saved, and where OpenSky differs from the game.
tags: [engine, papyrus, save]
---

# Papyrus script state

Many natives set something that no OpenSky runtime models yet. `Actor.SetGhost` is an example:
no system reads the ghost flag, but a script may read it back with `IsGhost`. OpenSky keeps such
values in one world-state component, `ScriptedReferenceState`, on the form the script changed. A
`Game` function keeps its value on the player. The `SCRS` save chunk stores the component
([world chunks](/formats/opensky-save-world-chunks.md#scrs-script-state)).

The component has four parts:

| Part | Example native | Read back by |
| --- | --- | --- |
| Flags | `SetGhost(bool abIsGhost = true)` | `IsGhost()` |
| Values | `SetVoiceRecoveryTime(float)` | `GetVoiceRecoveryTime()` |
| Form links | `SetCrimeFaction(Faction)` | `GetCrimeFaction()` |
| Added forms | `FormList.AddForm(Form)` | `GetSize()`, `GetAt(int)`, `HasForm(Form)`, `Find(Form)` |

A flag that is not set reads false, and a value that is not set reads 0. A setter that clears the
last value removes the component, so an untouched form stays clean in the save. Names are
case-insensitive.

Signatures and defaults are from the Creation Kit wiki script pages, for example
<https://ck.uesp.net/wiki/Actor_Script> and <https://ck.uesp.net/wiki/Game_Script>.

## Flags and values

| Script | Setters | Reads |
| --- | --- | --- |
| `Actor` | `SetPlayerTeammate`, `SetDoingFavor`, `SetAlert`, `SetAllowFlying`, `SetIntimidated`, `SetBribed`, `SetUnconscious` | `IsGhost`, `IsPlayerTeammate`, `IsDoingFavor`, `IsAlerted`, `IsAllowedToFly`, `IsIntimidated`, `IsBribed`, `IsUnconscious` |
| `Actor` | `SetRestrained`, `SetNoBleedoutRecovery`, `SetDontMove`, `SetAttackActorOnSight`, `SetHeadTracking`, `SetPlayerResistingArrest`, `AllowBleedoutDialogue`, `AllowPCDialogue` | none |
| `Actor` | `EnableAI(bool abEnable = true)` | `IsAIEnabled`, the AI packages, and combat |
| `Actor` | `SetAlpha`, `SetVoiceRecoveryTime`, `SetCriticalStage` | `GetVoiceRecoveryTime` |
| `Actor` | `SetForcedLandingMarker`, `SetCrimeFaction`, `SetLookAt`, `ClearLookAt` | `GetCrimeFaction` |
| `Actor`, `ActorBase` | `SetGhost`, `SetNotShowOnStealthMeter`, `SetEssential`, `SetInvulnerable`, `SetProtected` | see [record flags](#record-flags) |
| `ObjectReference` | `IgnoreFriendlyHits`, `SetNoFavorAllowed`, `BlockActivation` | `IsActivationBlocked` |
| `Location` | `SetCleared`, `SetKeywordData(Keyword, float)` | `IsCleared`, `GetKeywordData(Keyword)` |
| `Cell` | `SetPublic` | none |
| `Quest` | `SetActive` | `IsActive` |
| `Game` | `SetInChargen`, `SetBeastForm`, `SetAllowFlyingMountLandingRequests` | none |

`GetCrimeFaction` answers a faction a script set before the `CRIF` of the actor's base.

Condition functions read some of these flags too, such as `GetIsGhost` and
`GetKeywordDataForLocation` ([condition functions](/engine/condition-functions.md#script-state)).

The engine writes some entries itself, for conditions that ask about the past: the killer of
an actor, the player's friendly hits, the last actor that hit the player, and the destruction
progress ([recorded events](/engine/condition-functions-world.md#recorded-events),
[Papyrus destruction](/engine/papyrus-destruction.md)).

## Record flags

Five setters change a flag the `ACBS` of the `NPC_` record also holds: ghost, not shown on
the stealth meter, essential, protected, and invulnerable. `SetGhost` and
`SetNotShowOnStealthMeter` change the one actor. The `ActorBase` setters change every actor
of the base. A read starts from the record's flags, applies what a script set or cleared, and
then adds the essential and protected flags of every quest alias that holds the actor
(<https://ck.uesp.net/wiki/SetEssential_-_ActorBase>). `IsGhost`, `IsEssential`, the condition
functions `GetIsGhost`, `IsEssential`, and `IsProtected`, and the bleedout rule all read the
same result.

## Faction reactions

`Faction.SetEnemy(Faction akOther, bool abSelfIsNeutralToOther = false, bool
abOtherIsNeutralToSelf = false)` sets both directions to enemy; a true flag makes that side
neutral instead. `SetAlly` has the same shape, and a true flag makes that side a friend.
`SetReaction(Faction, int)` sets one direction, numbered as `GetReaction` answers: 0 neutral,
1 enemy, 2 ally, 3 friend. `SetPlayerEnemy(bool abIsEnemy = true)` pairs the faction with
`PlayerFaction` (Skyrim.esm `000DB1`) in both directions, and false sets them neutral.

The reaction is a value and a form link on the faction's state, so the save keeps it. After
each change, and after a load, the faction runtime receives every scripted reaction. A
scripted reaction wins over the `XNAM` relation of the record, in the hostility derivation
and in `GetReaction` ([hostility](/engine/hostility.md)).

## Words and shouts

`Game.TeachWord(WordOfPower)` and `Game.UnlockWord(WordOfPower)` set a flag per word on the
player, and `Game.IsWordUnlocked` reads the second. `UnlockWord` also teaches the word
(<https://ck.uesp.net/wiki/UnlockWord_-_Game>). `Actor.AddShout`, `RemoveShout`,
`EquipShout`, `UnequipShout`, and `GetEquippedShout` keep the shouts an actor knows and wears.
They count the shouts the actor's record gives as well as the ones a script added.
`RemoveShout` answers whether the actor knew the shout, and takes it off when it was equipped.
The [shout runtime](/engine/shouts.md) reads them to know which words the player may shout.

## Ownership

`SetActorOwner(ActorBase)` and `SetFactionOwner(Faction)` work on a reference and on a cell. A form
has one owner at a time, so setting one clears the other. A `None` argument clears the owner.

The crime check reads the owner a script set on a reference before the reference's own `XOWN`
([crime](/engine/crime.md#ownership)). So `SetActorOwner` with the player's base makes taking an
item no theft. A faction owner set by a script needs rank 0.

`GetActorOwner` and `GetFactionOwner` answer the script's owner first. With no script owner, a
reference answers the owner the crime check uses, and a cell answers `None`, counted as a stub.

## Player controls

`DisablePlayerControls` and `EnablePlayerControls` take eight Bool arguments, one per control
group: movement, fighting, camera switch, looking, sneaking, menu, activate, and journal. For
`DisablePlayerControls` the defaults are true for movement, fighting, menu, and activate, and false
for the rest. For `EnablePlayerControls` every default is true. Only an argument that is true
changes its group. `IsMovementControlsEnabled` and the seven other reads answer the stored state.

While the player bleeds out, movement, fighting, sneaking, and activate are locked. A dead player
has every group locked (see [Player death](/engine/ragdoll.md#player-death)).

## Added forms

`FormList.AddForm` appends a form once. `RemoveAddedForm` removes a form a script added, and
`Revert` removes every added form. The `FormList` reads see the plugin entries first, then the
added forms. `LeveledItem`, `LeveledActor`, and `LeveledSpell` keep `AddForm` and `Revert` the same
way, and each added entry keeps its level and, for `LeveledItem`, its count. The leveled roll
reads the added entries ([leveled lists](/engine/leveled-lists.md#script-changes)).

## Where OpenSky differs

- The state is recorded, and in most cases nothing else reads it yet. The HUD has no stealth
  meter, so `SetNotShowOnStealthMeter` changes only the flag reads. The input layer reads the
  player controls.
- The condition function `GetEquippedShout` sees a record shout of an actor that was resident
  when the script state last changed. An actor that loaded after that change answers only the
  shout a script equipped.
- No open source says where `AddForm` puts a form in `GetAt` order. OpenSky puts it after the
  plugin entries.
- `SetCrimeFaction(None)` removes the script's faction, so `GetCrimeFaction` answers the `CRIF`
  again. The game may instead keep the actor without a crime faction.
