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
| `Actor` | `SetGhost`, `SetPlayerTeammate`, `SetDoingFavor`, `SetAlert`, `SetAllowFlying`, `SetIntimidated`, `SetBribed`, `SetUnconscious` | `IsGhost`, `IsPlayerTeammate`, `IsDoingFavor`, `IsAlerted`, `IsAllowedToFly`, `IsIntimidated`, `IsBribed`, `IsUnconscious` |
| `Actor` | `SetRestrained`, `SetNoBleedoutRecovery`, `SetNotShowOnStealthMeter`, `SetDontMove`, `SetAttackActorOnSight`, `SetHeadTracking`, `SetPlayerResistingArrest`, `AllowBleedoutDialogue`, `AllowPCDialogue` | none |
| `Actor` | `EnableAI(bool abEnable = true)` | `IsAIEnabled` |
| `Actor` | `SetAlpha`, `SetVoiceRecoveryTime`, `SetCriticalStage` | `GetVoiceRecoveryTime` |
| `Actor` | `SetForcedLandingMarker`, `SetCrimeFaction`, `SetLookAt`, `ClearLookAt` | `GetCrimeFaction` |
| `ActorBase` | `SetEssential`, `SetInvulnerable`, `SetProtected` | none |
| `ObjectReference` | `IgnoreFriendlyHits`, `SetNoFavorAllowed`, `BlockActivation` | `IsActivationBlocked` |
| `Location` | `SetCleared`, `SetKeywordData(Keyword, float)` | `IsCleared`, `GetKeywordData(Keyword)` |
| `Cell` | `SetPublic` | none |
| `Quest` | `SetActive` | `IsActive` |
| `Game` | `SetInChargen`, `SetBeastForm` | none |

`GetCrimeFaction` answers a faction a script set before the `CRIF` of the actor's base.

Condition functions read some of these flags too, such as `GetIsGhost` and
`GetKeywordDataForLocation` ([condition functions](/engine/condition-functions.md#script-state)).

The engine writes some entries itself, for conditions that ask about the past: the killer of
an actor, the player's friendly hits, the last actor that hit the player, and the destruction
progress ([recorded events](/engine/condition-functions-world.md#recorded-events),
[Papyrus destruction](/engine/papyrus-destruction.md)).

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
player, and `Game.IsWordUnlocked` reads the second. `Actor.AddShout`, `RemoveShout`,
`EquipShout`, `UnequipShout`, and `GetEquippedShout` keep the shouts an actor knows and wears.
`RemoveShout` answers whether the actor knew the shout, and takes it off when it was equipped.
OpenSky casts no shout yet, so nothing else reads these.

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

## Added forms

`FormList.AddForm` appends a form once. `RemoveAddedForm` removes a form a script added, and
`Revert` removes every added form. The `FormList` reads see the plugin entries first, then the
added forms. `LeveledItem`, `LeveledActor`, and `LeveledSpell` keep `AddForm` and `Revert` the same
way.

## Where OpenSky differs

- The state is recorded, and in most cases nothing else reads it yet. The input layer does not
  read the player controls, the AI does not read `EnableAI`, death does not read `SetEssential`,
  the HUD does not read `SetNotShowOnStealthMeter`, and leveled lists do not read added forms.
- A read does not fall back to the record. `IsGhost` on an actor whose `NPC_` record has the ghost
  flag reads false until a script sets it.
- `UnlockWord` does not also teach the word. No source this project checked says whether it
  does.
- A shout an actor's record gives is not known to `RemoveShout` or `GetEquippedShout`; only
  the shouts a script added are.
- A leveled-list entry keeps its form, not its level or count.
- No open source says where `AddForm` puts a form in `GetAt` order. OpenSky puts it after the
  plugin entries.
- `SetCrimeFaction(None)` removes the script's faction, so `GetCrimeFaction` answers the `CRIF`
  again. The game may instead keep the actor without a crime faction.
