---
type: Subsystem
title: Papyrus session natives and engine events
description: The Papyrus natives that reach the running session - saves, quitting, fades, screen
  blood, god mode, crime switches, model nodes, sounds, scripted walks, the sun, eye textures,
  Havok constraints - and the engine events for wards, books, grabs, equips, and bow shots, with
  where OpenSky differs.
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
| `Game.FadeOutGame` | Waits, then fades the frame to black or white, or back, on the game clock ([fades](#fades)) |
| `Game.TriggerScreenBlood`, `Game.ClearTempEffects` | Adds screen blood splatters, or clears them |
| `Game.ShowTitleSequenceMenu`, `Game.HideTitleSequenceMenu` | Shows or removes `interface\titles.swf` over the world ([new game](/engine/main-menu.md#new-game)) |
| `Game.StartTitleSequence` | Plays the named clip of the titles movie, such as `Sequence1` |
| `Game.ShowFirstPersonGeometry` | Shows or hides the first-person arms |
| `Debug.TakeScreenshot` | Writes a PNG of the view, at its size, to `~/Pictures/OpenSky/` |
| `Debug.ToggleCollisions` | Switches the player between flying and walking |
| `Debug.SetGodMode` | The player takes no damage while it is on. A save keeps it |
| `Debug.SetFootIK` | Turns foot IK on or off for the player and every actor, until the session ends |
| `Debug.CenterOnCellAndWait` | Moves the player to the cell |
| `Game.ClearPrison`, `Game.SetPlayerReportCrime` | Ends a jail stay; stops crime reports against the player. A save keeps the switch |
| `Game.GetPlayerGrabbedRef` | The body the player holds with telekinesis |
| `Cell.Reset` | Flags a cell for reset ([cell reset](/engine/cell-reset.md#a-script-reset)): an interior, or a loaded exterior cell |
| `ShaderParticleGeometry.Apply`, `Remove` | Lays the record's rain or snow over the weather, fading over `afFadeTime`; a load or a new game removes it |

`Debug.DBSendPlayerPosition` sends to a debug tool that does not exist, so it does nothing.

God mode and the crime-report switch sit on the player's world state, so the save keeps them in
the [`PRUL` chunk](/formats/opensky-save-world-chunks.md#prul-player-rules).

`ToggleCollisions` matches the console's `tcl` with no target: UESP's
[console page](https://en.uesp.net/wiki/Skyrim:Console) says it turns off the player's collision
and gravity, so the player flies through walls. That is OpenSky's fly mode.

### Fades

A fade out waits `afSecsBeforeFade`, then covers the frame over `afFadeDuration`. A fade in
covers the frame at once, waits, then uncovers it, as the wiki example "spend 2 seconds on a
black screen before fading in" says. `abBlackFade` false fades to white. The fader lays over
every image-space modifier ([image space](/rendering/image-space.md)) and runs on the game
clock, so it stops while the world is paused. A loading screen draws over it, and a load or a
new game clears it. `openskycli game debug fade` starts one, and `state frame` shows it.

## Actor and reference rules

- `StartDeferredKill` and `EndDeferredKill` hold and release a death
  ([bleedout](/engine/ragdoll.md#bleedout)). `IsInKillMove` is false: there are no kill moves.
- `StartVampireFeed` sends the feed to the vampire scripts. `StartCannibal` marks the target as
  eaten. Neither plays its animation.
- `DoCombatSpellApply` casts the spell. `PlayIdleWithTarget` plays the idle on the actor alone.
- `MoveToPackageLocation` moves the actor to the place its running package uses.
- `ClearExtraArrows` removes the arrows stuck in the actor. `ClearArrested` clears the arrest.
- `AttachAshPile` places the given pile at the actor and links each to the other. With no pile
  given it places `DefaultAshPile1` (`Skyrim.esm:00001B`), a form below 0x800, the range the
  engine itself names. Activating the pile activates the actor too, so the player searches the
  dead actor's inventory through the pile.
- `UnLockOwnedDoorsInCell` unlocks the doors of the actor's cell that its base owns.
- `KnockAreaEffect` pushes the actors in the radius away from the caster.
- `ForceAddRagdollToWorld` starts a ragdoll at once.
- `PlayImpactEffect` casts a line from the reference, or from the named node, along the given
  direction and length. The direction turns with the node when `abApplyNodeRotation` is set:
  with the node's world rotation, or with its rotation inside its parent node when
  `abUseNodeLocalRotation` is set. The impact plays where the line first meets a static or the
  ground, with that surface's material. A line that meets nothing plays no impact.
- `PathToReference` walks the actor to the target over the navmesh and waits until it stops.
  The speed is `afWalkRunPercent` of the way from the walk speed to the run speed, so 0.5 is
  half way between them (<https://ck.uesp.net/wiki/PathToReference_-_Actor>). It answers true
  when the actor arrived, and false when no path starts, the walk gives up or is stopped, or
  `afWalkRunPercent` is outside 0 to 1.
- `Game.PlayBink` plays a movie from `Data\Video` and waits until it ends or is skipped
  ([movies](/engine/movies.md)).
- `Faction.GetStolenItemValueCrime` and `GetStolenItemValueNoCrime` sum what the player stole
  from the faction, seen and unseen.

## Model nodes

`HasNode` and `MoveToNode` read the named nodes of the reference. An actor's skeleton and an
animated object's bones are read in their current pose. Any other node comes from the base model
in its rest pose. The model loads off the main actor. A call that finds it still loading waits,
and the frame answers the call once the model is in. `MoveToNode` takes the node's position and
rotation, and keeps the reference's scale.

## Sounds

`Sound.Play` starts the sound at the source reference and returns an instance ID; 0 means it
did not play. A Papyrus `Sound` is a `SOUN` record, which names its `SNDR` descriptor. Example:
`MQ101` plays `OBJCarriageMove2DLPM` on the player for the cart ride, a loop it stops with
`StopInstance` when the cart arrives. `PlayAndWait` waits until the sound ends, and answers
false when it could not play or was stopped. `StopInstance` and `SetInstanceVolume` act on the
ID, also when the sound file is still loading. The volume is clamped to 0 to 1, as the
[wiki](https://ck.uesp.net/wiki/SetInstanceVolume_-_Sound) says.

## The sun

`Game.GetSunPositionX`, `Y`, and `Z` give the point 100,000 units from the player's eye toward
the sun. They return 0 in an interior and at night, when the wiki says the sun is not up.
`Game.IsPlayerSungazing` is true, and `OnPlayerBowShot` reports sun gazing, when the player's
view is within 5 degrees of the sun. No open source gives the game's angle, so this cone is
OpenSky's own. `Game.SetSunGazeImageSpaceModifier` plays its modifier when the view enters the
cone.

## Eye textures

`Actor.SetEyeTexture` draws the actor's eyes head part with the given texture set. An
assembled head retextures that part. A baked FaceGen head names its eyes shape after the eyes
head part's editor ID, so OpenSky retextures the shape of that name. For example, Serana's
`dawnguard.esm\00002b6c.nif` has the shape `FemaleEyesHumanVampire01Nord`. The CK wiki says the
texture lasts until the actor's 3D reloads, and the vampire scripts set it again in `OnLoad`. So
OpenSky clears it when the actor's cell unloads, and keeps it in no save. An actor without 3D
ignores the call. The player's head ignores it too; no vanilla script calls it on the player.

## Havok constraints

`Game.AddHavokBallAndSocketConstraint` and `Game.RemoveHavokConstraints` take two references
and a node name on each. Each end is one of three kinds:

| End | Example | What OpenSky does |
| --- | --- | --- |
| A dead or ragdolling actor's bone | the corpse's `NPC Neck [Neck]` in `HangedManScript` | A dead actor that lies still starts its ragdoll first |
| A loose body | the key in `HangingKeyAttachOnLoad` | The whole body is held; the node name is not checked |
| Any other reference's node | the rope's `JointHelper01`, the peg's `AttachDummy` | A fixed point, read from the model |

Two ragdoll ends make a link. A ragdoll or loose end with a fixed end makes a pin. Any other
pair, and a living actor that is not ragdolling, answers false, as the CK wiki says the game
does. The add waits while the fixed end's model loads, because the wiki lists both natives as
latent. [Ragdoll solver](/engine/ragdoll-solver.md#script-links) has the solve.

The sub-graph natives are in [effect graphs](/engine/effect-graphs.md).

## Engine events

- `OnWardHit(akCaster, akSpell, aiStatus)` goes to the ward holder's scripts when a spell meets
  the ward.
- `OnRead()` goes to a placed book's scripts, or to the book's own base scripts when it is read
  from an inventory.
- `OnGrab()` and `OnRelease()` go to a body the player takes or lets go with telekinesis.
- `OnEquipped(akActor)` and `OnUnequipped(akActor)` go to the item's own base scripts. An item in
  an inventory has no reference, so OpenSky keeps one persistent instance per base form. As the
  wiki says, an equip by a script (`EquipItem`, `UnequipItem`, `UnequipAll`, `UnequipItemSlot`)
  sends neither. An item a scripted equip pushes out of its slot sends nothing either.
- `OnPlayerBowShot(akWeapon, akAmmo, afPower, abSunGazing)` goes to the player's scripts when an
  arrow leaves the bow.
- `OnEnterBleedout()` and the trap contact events are on the
  [bleedout](/engine/ragdoll.md#bleedout) and [trap contact](/engine/traps.md#trap-contact) pages.

## Where OpenSky differs

- The screenshot goes to `~/Pictures/OpenSky/`, because OpenSky never writes into the install.
- No source says whether the game sends `OnUnequipped` for an item a scripted equip pushes out
  of its slot. OpenSky sends nothing.
- `PathToReference` blends the speed. An actor that runs its behaviour graph blends its walk
  and run clips by that speed too. An actor without a running graph plays one clip, walk below
  half of `afWalkRunPercent` and run from half up, so its feet can slide.
- `OnPlayerBowShot` and `Game.IsPlayerSungazing` count the player as looking at the sun within
  5 degrees of it. No open source or game setting gives the game's angle.
- `KnockAreaEffect` pushes at 1000 units a second for a magnitude of 1. No open source or game
  setting gives the game's scale.
- `Debug.SetFootIK` lasts until the session ends and is not kept in a save. No source says
  whether the game keeps it.
- A loose body and a ragdoll do not link to each other, and neither do two loose bodies. No
  vanilla script makes such a pair.
