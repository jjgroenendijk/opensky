---
type: Subsystem
title: Beast forms
description: How the player becomes a werewolf or a vampire lord, what the change scripts do and what the engine adds, and where OpenSky differs from the game.
tags: [engine, player, scripting, crime]
---

# Beast forms

The player can take two beast forms: the werewolf, through the Beast Form power, and, with
Dawnguard, the vampire lord. A beast form swaps the player's race, body, and behaviour graph,
and takes away most of the player's actions.

Sources: UESP "Skyrim:Lycanthropy", "Skyrim:Vampire Lord", and "Skyrim:Crime"; the Creation
Kit pages "SetBeastForm - Game", "SendWereWolfTransformation - Game", and "Crime".

## The scripts do the change

The game runs a beast form in Papyrus. The power's effect script starts a quest, and the quest
script does the change. Its natives were read from the string table of the install's
`playerwerewolfchangescript.pex` and `dlc1playervampirechangescript.pex`:

| Step | Natives |
| --- | --- |
| Lock the player in | `DisablePlayerControls`, `ForceThirdPerson`, `SetBeastForm(true)`, `EnableFastTravel(false)` |
| Change the body | `UnequipAll`, `SetRace` to `WerewolfBeastRace` or `DLC1VampireBeastRace`, `EquipItem` |
| Give the form's powers | `AddSpell`, `AddShout`, `EquipShout`, `AddPerk` |
| Report the crime | `SendWereWolfTransformation` |
| Feed, and count perk progress | the feed perk's fragment calls the script's `Feed`; `IncrementStat`, `SetValue` |
| Change back | `PlayIdle` with the change-back idle, then `SetRace` with the original race, `SetBeastForm(false)` |

So the engine does not run a timer or count feedings. It gives the natives their effects, and
the rules below.

## What the engine adds

The form is read from two facts. `SetBeastForm(true)` sets a flag on the player. The race
says which form it is: `WerewolfBeastRace` is the werewolf and `DLC1VampireBeastRace` the
vampire lord. These are the races the two change scripts set. A flag with another race is a
form a mod adds.

The race has its own behaviour project. `WerewolfBeastRace` names
`Actors\WerewolfBeast\WerewolfBeastProject.hkx`, and `DLC1VampireBeastRace` names
`Actors\VampireLord\VampireLord.hkx`. The character races name projects under
`Actors\Character`. When the player's race names another folder, the player runs that project's
graph and rig in place of `0_master.hkx`, and the body waits for it. A beast form has no
first-person graph, so the scripts and the debug switch force the third-person camera. When the
race changes back, the character graphs return. They stay loaded during the form.

The body comes from the race, as an NPC's does: the race's skin (`WNAM`) and skeleton
(`ANAM`). Neither beast race has the FaceGen Head flag, so no head parts are added.

In a beast form, these keys do nothing: inventory, magic, map, skills, the camera switch, and
the favourites hotkeys. The journal, the wait key, and the shout key still work. The shout key
uses the howl or the vampire power the script equipped.

Two activation rules are the engine's:

- A race without the `RACE` `DATA` flag "Can Pick Up Items" (bit 28) cannot take an item.
  Both beast races lack it; `NordRace` has it.
- A beast form cannot start a conversation.

Containers, doors, locks, and the "Feed" choice on a corpse come from the data. The change
effects add perks with Filter Activation entries, such as `PlayerWerewolfFeed` and
`DLC1VampireActivationBlocker`, and the [perk activation](/engine/perks.md) rules apply them.

## The crime

`Game.SendWereWolfTransformation` reports the change as a crime when an actor detects the
player. The price is the crime faction's `CRVA` werewolf price, 1000 in every vanilla hold.
[Crime](/engine/crime.md) has the details.

## IsBeastRace is not a beast form

The character graph variable `IsBeastRace` follows the `IsBeastRace` keyword. On the install,
only `ArgonianRace`, `KhajiitRace`, and their vampire races carry it. It selects the claw
attacks of those races. The werewolf and vampire lord races do not carry it, so it is false in a
beast form. `GetIsRace` and `GetPCIsRace` read the player's current race, so they answer the
beast race during a form.

## Checking it in the game

`openskycli game debug form werewolf`, `vampirelord`, or `none` sets the race and the
`SetBeastForm` flag without the change scripts. `state player` shows `form` and the
`behaviorProject` the body runs.

## Where OpenSky differs

- In the game, the skills key opens the form's perk tree. In OpenSky it does nothing in a beast
  form (issue #1612).
- The game charges the change only for the first witnessed change. OpenSky charges each one
  (issue #1613).
