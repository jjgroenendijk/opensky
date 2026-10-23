---
type: Subsystem
title: Papyrus world reads
description: The natives that read where things are, what a base record holds, and who an
  actor talks to, with the data each one reads and where OpenSky differs from the game.
tags: [engine, papyrus]
---

# Papyrus world reads

These natives read state the engine already keeps. None of them changes the world. Each
signature comes from the Creation Kit wiki page named for the function, for example
"GetEditorLocation - ObjectReference". A native without the data it needs fails with a
reason, so the script gets the default value and the tally names the cause.

## Places

| Native | Reads |
| --- | --- |
| `ObjectReference.GetEditorLocation` | The location of the cell the reference was placed in, from the place snapshot that conditions read. None when that cell has no location |
| `Location.HasCommonParent(akOther, akFilter)` | True when the two `PNAM` parent chains share a location above both. With a filter keyword, the shared parent, or one of its own parents, must carry it |
| `Cell.IsInterior` | True when the cell has no worldspace. It fails when no loaded reference sits in the cell |

`HasCommonParent` does not count a location as its own parent. A town and its hold share no
parent; two towns in one hold do. The wiki does not say how the game treats the location
itself, so this is OpenSky's reading.

## Base records

| Native | Reads |
| --- | --- |
| `ObjectReference.GetWidth`, `GetLength`, `GetHeight` | The base record's `OBND` box along X, Y, and Z, times the reference's scale |
| `ObjectReference.GetMass` | The Havok mass in kilograms of a loose dynamic body, or the sum of a ragdoll's bone bodies. 0 when Havok does not move the reference, as the wiki states ([GetMass - ObjectReference](https://ck.uesp.net/wiki/GetMass_-_ObjectReference)) |
| `ObjectReference.GetVoiceType` | The actor base's `VTCK` after template inheritance |
| `ActorBase.GetGiftFilter` | The actor base's own `GNAM` form list |

The wiki says `GetLength` is "the distance between the bounding box min and max y values".
It does not say whether the scale applies. OpenSky applies it, because a scaled reference
covers a scaled box. The bounds come from the record index that keywords use, so a base type
outside that index, such as `STAT`, fails. A talking activator's voice type is not read,
so `GetVoiceType` answers None for one.

## Spells

`Spell.IsHostile` is true when any effect of the spell carries the `MGEF` hostile flag. A cast
uses the same rule to decide whether it is an attack.

`Spell.Preload`, `Spell.Unload`, and `Game.PrecacheCharGen` ask the game to load art early, so
a later cast or the race menu does not stall. OpenSky loads that art when it first draws it,
so these hints have nothing to start and return at once.

## Actors

- `Actor.GetDialogueTarget` returns the player for the actor the player talks to, and None
  otherwise. OpenSky models only the player's conversation. On the player the game returns
  None, and so does OpenSky.
- `Actor.GetBribeAmount` returns the price that `GetBribeSuccess` tests, with the player's
  "Mod Bribe Amount" perk factor. [Speech checks](/engine/speech-checks.md) gives the
  formula.
- `Faction.SetReaction(akOther, aiNewValue)` sets how this faction reacts to the other one,
  and only in that direction. The wiki notes that 3 makes friends, so the value is read as an
  `XNAM` combat reaction: 0 neutral, 1 enemy, 2 ally, 3 friend. Any other value fails. The
  reaction is stored like the one `SetEnemy` stores.

- `Game.GetPlayersLastRiddenHorse` returns the horse the vehicle runtime last saw the player
  mount, the same horse the `IsPlayersLastRiddenMount` condition reads. None before the
  first ride.

## Radius searches

`Game.FindClosestActor`, `FindRandomActor`, `FindClosestReferenceOfType`,
`FindRandomReferenceOfType`, `FindClosestReferenceOfAnyTypeInList`, and
`FindRandomReferenceOfAnyTypeInList` look at the resident references within the radius of
the point. A disabled or deleted reference does not count. The player counts as an actor, as
the wiki notes for `FindClosestActor`.

- The closest search breaks a tie in distance by reference order, so a run repeats.
- The random search draws from the script random stream, which a seed makes repeatable.
- A list search matches any base in the form list's direct entries.

## Weather blend

`Weather.GetOutgoingWeather` returns the weather a blend moves away from, and
`GetCurrentWeatherTransition` how far the blend has come, from 0 to 1. With no blend
running, they return None and 1, as the wiki describes. [Weather](/engine/weather.md)
describes the blend.

## Stack traces

`Debug.TraceStack(asTextToPrint, aiSeverity)` writes the text and the call stack to the
log. The interpreter adds the stack, because only it knows the callers. Each line names a
script and the instruction it was on. The game names the function and the source line
instead; OpenSky does not read the debug line table. Severity 1 logs a warning and 2 an
error.

## Interior fog

`Cell.SetFogColor(aiNearRed, aiNearGreen, aiNearBlue, aiFarRed, aiFarGreen, aiFarBlue)`,
`SetFogPlanes(afNear, afFar)`, and `SetFogPower(afPower)` change the fog of the loaded
interior. The argument names come from the install's `Cell.pex`. Colour channels are 0 to
255. A near plane past the far one swaps the two, as the wiki page for `SetFogPlanes` says.
A cell that is not the loaded interior does not change.

The change lives in the renderer, beside the lighting it was made from. When the scene
gets other lighting, such as after a move to another cell, the cell's recorded fog draws
again. The game's rule for how long a change lasts is not documented, so OpenSky keeps it
only while the cell stays loaded. A cell without recorded fog shows the new fog only after
`SetFogPlanes` gives it a far plane.

## User logs and the HUD toggle

`Debug.OpenUserLog(asLogName)` opens a named user log and answers false when it is already
open. `TraceUser(asLogName, asText)` writes `name: text` to the native log and answers
false when that log is not open. `CloseUserLog` closes it. The game writes each user log
to its own file under `Logs/Script/User/`
([OpenUserLog - Debug](https://ck.uesp.net/wiki/OpenUserLog_-_Debug)). OpenSky keeps one
log, so the name is a prefix instead.

`Debug.ToggleMenus()` shows or hides the HUD layer, as the `tm` console command does.

`Game.UsingGamepad()` answers false, because OpenSky reads only the keyboard and mouse.
