---
type: Subsystem
title: Papyrus session natives and engine events
description: The Papyrus natives that reach the running session - saves, quitting, fades, screen
  blood, god mode, crime switches, model nodes, the sun - the natives that stay traced stubs, and
  the engine events for wards, books, grabs, equips, and bow shots, with where OpenSky differs.
tags: [engine, papyrus, session, events]
---

# Papyrus session natives and engine events

Some natives act on the whole session, not on one record: they save, quit, fade the screen, or
switch a game rule. The bridge reaches them through the `gameNatives` family
([coordinators](/engine/coordinators.md)). The app fills it when a session starts. A native whose
hook is empty fails the call, so a test or a load without a session sees a refusal, not a silent
success.

Signatures and behaviour come from the Creation Kit wiki pages named after each function, such as
[RequestSave](https://ck.uesp.net/wiki/RequestSave_-_Game) and
[FadeOutGame](https://ck.uesp.net/wiki/FadeOutGame_-_Game).

## Session natives

| Native | What OpenSky does |
| --- | --- |
| `Game.RequestSave`, `Game.RequestAutoSave` | Writes a save in a new slot, or in the autosave slot |
| `Game.QuitToMainMenu`, `Debug.QuitGame` | Ends the session, or quits the app |
| `Game.FadeOutGame` | Covers the world in black, or uncovers it, at once |
| `Game.TriggerScreenBlood`, `Game.ClearTempEffects` | Adds screen blood splatters, or clears them |
| `Game.ShowTitleSequenceMenu`, `Game.HideTitleSequenceMenu` | Shows or hides the title backdrop |
| `Game.ShowFirstPersonGeometry` | Shows or hides the first-person arms |
| `Debug.TakeScreenshot` | Writes a 1920 by 1080 PNG to `~/Pictures/OpenSky/` |
| `Debug.ToggleCollisions` | Switches the player between flying and walking |
| `Debug.SetGodMode` | The player takes no damage while it is on |
| `Debug.CenterOnCellAndWait` | Moves the player to the cell |
| `Game.ClearPrison`, `Game.SetPlayerReportCrime` | Ends a jail stay; stops crime reports against the player |
| `Game.GetPlayerGrabbedRef` | The body the player holds with telekinesis |
| `Cell.Reset` | Flags an interior cell for reset ([cell reset](/engine/cell-reset.md#a-script-reset)) |

`Debug.DBSendPlayerPosition` sends to a debug tool that does not exist, so it does nothing.

## Actor and reference rules

- `StartDeferredKill` and `EndDeferredKill` hold and release a death
  ([bleedout](/engine/ragdoll.md#bleedout)). `IsInKillMove` is false: there are no kill moves.
- `StartVampireFeed` sends the feed to the vampire scripts. `StartCannibal` marks the target as
  eaten. Neither plays its animation.
- `DoCombatSpellApply` casts the spell. `PlayIdleWithTarget` plays the idle on the actor alone.
- `MoveToPackageLocation` moves the actor to the place its running package uses.
- `ClearExtraArrows` removes the arrows stuck in the actor. `ClearArrested` clears the arrest.
- `AttachAshPile` places the given pile at the actor and links it. With no pile given it does
  nothing, because the default pile is not known.
- `UnLockOwnedDoorsInCell` unlocks the doors of the actor's cell that its base owns.
- `KnockAreaEffect` pushes the actors in the radius away from the caster.
- `ForceAddRagdollToWorld` starts a ragdoll at once. `PlayImpactEffect` plays the impact data
  set where the reference stands.
- `Faction.GetStolenItemValueCrime` and `GetStolenItemValueNoCrime` sum what the player stole
  from the faction, seen and unseen.

## Model nodes

`HasNode` and `MoveToNode` read the named nodes of the reference's base model. The model loads off
the main actor. A call that finds it still loading waits, and the frame answers the call once the
model is in. The node position is its rest pose, so a node that an animation moves is read where
it starts. Only a placed object's base model is read; an actor's skeleton is not.

## The sun

`Game.GetSunPositionX`, `Y`, and `Z` give the point 100,000 units from the player's eye toward
the sun. They return 0 in an interior and at night, when the wiki says the sun is not up.
`OnPlayerBowShot` reports sun gazing when the player's view is within 5 degrees of the sun. No
open source gives the game's angle, so this cone is OpenSky's own.

## Traced stubs

These natives return a fixed value and write a trace line, because the subsystem they need is not
built: `SetSubGraphFloatVariable`, `PlaySubGraphAnimation`, `SetEyeTexture`, `PathToReference`
(false), `AddHavokBallAndSocketConstraint` (false), `RemoveHavokConstraints` (false),
`Game.PlayBink`, `Game.StartTitleSequence`, `Game.SendWereWolfTransformation`, `Debug.SetFootIK`,
`ShaderParticleGeometry.Apply` and `Remove`, and `Sound.SetInstanceVolume`.

## Engine events

- `OnWardHit(akCaster, akSpell, aiStatus)` goes to the ward holder's scripts when a spell meets
  the ward.
- `OnRead()` goes to a placed book's scripts, or to the book's own base scripts when it is read
  from an inventory.
- `OnGrab()` and `OnRelease()` go to a body the player takes or lets go with telekinesis.
- `OnEquipped(akActor)` and `OnUnequipped(akActor)` go to the item's own base scripts. An item in
  an inventory has no reference, so OpenSky keeps one persistent instance per base form.
- `OnPlayerBowShot(akWeapon, akAmmo, afPower, abSunGazing)` goes to the player's scripts when an
  arrow leaves the bow.
- `OnEnterBleedout()` and the trap contact events are on the
  [bleedout](/engine/ragdoll.md#bleedout) and [trap contact](/engine/traps.md#trap-contact) pages.

## Where OpenSky differs

- A fade is instant and always black. The game waits `afSecsBeforeFade`, fades over
  `afFadeDuration`, and can fade to white.
- `OnEquipped` fires for every equip, also one a script makes. The wiki says the game sends it
  only for an item equipped from an inventory.
- `ToggleCollisions` uses fly mode, so the player also ignores gravity.
- God mode and `SetPlayerReportCrime` are not saved.
- The screenshot size and folder are fixed.
