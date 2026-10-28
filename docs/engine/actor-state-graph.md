---
type: Subsystem
title: Actor state graph variables
description: The actor-state variables the engine writes into the player's behavior graphs each
  step, the outputs it reads back, how iState is encoded, and the variables left unwritten.
tags: [engine, animation, behavior, player]
---

# Actor state graph variables

The behavior graphs share more than movement with the engine. The engine tells them what the actor
does: an attack, a guard, a cast, where the camera looks. The graphs report back what the animation
allows: whether the actor may turn, equip, or is in a recoil. The movement variables are on the
[locomotion graph](/engine/locomotion-graph.md) page.

Every name and direction comes from the install's character graphs, read with the census of
[HKX behavior graph objects](/formats/hkx-behavior.md). The Creation Kit list of animation variables
(<https://ck.uesp.net/wiki/List_of_Animation_Variables>) names many of them but gives no types.

## Inputs the engine writes

The locomotion bridge writes these each step, to both the third-person and the first-person graph.

| Variable | Type | Written as | Bound in the graph to |
| --- | --- | --- | --- |
| `bHeadTracking` | bool | The Head tracking setting | `BSLookAtModifier.lookAtTarget` |
| `TargetLocation` | quad | A point 1024 units along the camera view, world space | `BSLookAtModifier.targetLocation` |
| `camerafromx`, `camerafromy`, `camerafromz` | real | The camera position | Look and aim modifiers |
| `Pitch` | real | Camera pitch in radians, positive up | `hkbTwistModifier` in the bow aim |
| `bSprintOK` | bool | False when the stamina gate refuses a sprint | Sprint transition conditions |
| `iWantBlock` | int32 | 1 while the block key is held | Block and bow zoom conditions |
| `bWantCastLeft`, `bWantCastRight` | bool | True while that hand casts | `BSEventOnFalseToTrueModifier` |
| `bWantCastVoice` | bool | True while the player inhales a shout ([shouts](/engine/shouts.md)) | `BSEventOnFalseToTrueModifier` raising `BeginCastVoice` |
| `IsInCastState` | real | 1 while either hand casts, else 0 | Cast blends |
| `iRightHandEquipped`, `iLeftHandEquipped` | int32 | The hand's `iRightHandType` value while drawn, else 0 | Jump, sprint, stagger, and shout selectors |
| `IsBeastRace` | bool | The race has the `IsBeastRace` keyword | The unarmed attack selector |
| `iGetUpType` | int32 | 2 while swimming, else 1 | The get-up pose matcher |
| `weapAdj` | real | The player's weight / 100 | The expression that weights the [body-weight layer](/engine/behavior-clips.md#body-weight-layer) |
| `iState` | int32 | The value of one `iState_*` constant | State conditions |

The hand selectors list their children in the `iRightHandType` order: 0 unarmed, 1 to 4 one-handed,
5 two-handed sword, 6 two-handed axe, 7 bow, 8 staff, 12 crossbow. A sheathed weapon picks the
unarmed child, so OpenSky writes 0 then. The `IsBeastRace` keyword is the default object `KWBR`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOBJ>). The pose matcher under
`iGetUpType` has three children: 0 reanimate, 1 get up, 2 swimming. OpenSky never writes 0,
because it has no reanimation.

[WARNING] The sign of `Pitch` on the spine twist is not yet checked against the game. The look
distance of `TargetLocation` is OpenSky's own.

## How `iState` is encoded

`0_master.hkx` declares one int32 variable per actor state, such as `iState_NPC1HM` and
`iState_NPCSprinting`. Each holds the number that `iState` takes for that state. The engine reads the
numbers from the graph instead of hard-coding them, so a graph with other numbers still works. When
the graph declares no constant for the state, `iState` is not written.

The state is picked in a fixed order. The first match wins:

1. An attack: a power attack, a two-handed attack, or a plain attack.
2. A guard (`iState_NPCBlocking`).
3. A fully drawn bow (`iState_NPCBowDrawn`).
4. A cast in either hand (`iState_NPCMagicCasting`).
5. Riding: `iState_HorseSprint` while the mount sprints, else `iState_NPCHorse`. `bIsRiding` is
   true while the player sits on a mount ([riding](/engine/riding.md)).
6. Drunk (`iState_NPCDrunk`), while the graph tags it (see below).
7. A sprint or sneak gait.
8. A drawn weapon, by the right-hand type: one-handed, two-handed, bow or crossbow, or staff or
   spell. The type uses the `iRightHandType` encoding ([combat graph names](/engine/combat-graph-names.md)).
9. Otherwise `iState_NPCDefault`.

[INFO] This order is OpenSky's own. No source states the game's order. Bleedout,
quick shot, and shield charge have no OpenSky system yet, so no step picks them.

## Drunk actors

An actor is drunk while its graph is in the `MT_Drunk` state of `mt_behavior.hkx`. Two idle
records in `Skyrim.esm` move it there and back. Both name `Actors\Character\Behaviors\0_Master.hkx`,
with no conditions and no parent:

| Idle | Form ID | Event |
| --- | --- | --- |
| `IdleDrunkStart` | `0CEFD0` | `DrunkStart` |
| `IdleDrunkStop` | `0CEFD1` | `DrunkStop` |

`0_master.hkx` passes the event to `mt_behavior.hkx`. There the state machine
`DefaultOrDrunkBehavior` goes from `NonDrunkState` to `MT_Drunk` on `DrunkStart`, and back on
`DrunkStop`. Inside `MT_Drunk`, `DrunkStanding` plays `IdleDrunk.hkx` and its two turn clips, and
`moveStart` leads to `DrunkLocomotion`, which plays `IdleDrunk_Walk.hkx`. The machine's sync
variable is `iDrunkVariable`.

`MT_Drunk` runs the `BSiStateTaggingGenerator` `MT_Drunk_iStateGen`. While it runs, the graph
tags the value 15, which is the value of `iState_NPCDrunk` in `0_master.hkx`. The graph files
hold many such generators, for example `Sprint_iStateGen` and `BleedOut_iStateGen`. OpenSky
reads the tag with the highest `m_iPriority`; on a tie the first one reached wins. No source
states the game's tie rule.

OpenSky treats an actor as drunk while its graph's tag equals `iState_NPCDrunk`:

- The player's `iState` takes `iState_NPCDrunk` (step 6 above).
- An NPC's `iState` is set to `iState_NPCDefault` or `iState_NPCDrunk` when the tag changes. OpenSky
  writes no other `iState` for an NPC yet.

After `DrunkStop` the actor stays drunk until the blend out of `MT_Drunk` ends, because the
tagging generator runs as long as the old state is blended in.

`openskycli hkx meshes\actors\character\behaviors\0_master.hkx --raise DrunkStart --raise moveStart`
shows the states and the tag. `openskycli game debug drunk <ref> on|off` raises the event on a
running actor, and `state player` and `state actors` give `drunk` and `iState`.

In the vanilla data nothing plays the two idles. No `PACK`, `SCEN`, `QUST`, or `NPC_` record names
them, and no script in `Skyrim - Misc.bsa` sends `DrunkStart`. Tavern drunks such as the ones of
`FavorJobsDrunksFaction` walk normally in the game as well. A mod reaches the state with
`PlayIdle(IdleDrunkStart)` (<https://ck.uesp.net/wiki/PlayIdle_-_Actor>) or
`Debug.SendAnimationEvent(akActor, "DrunkStart")`
(<https://ck.uesp.net/wiki/SendAnimationEvent_-_Debug>). The animation variable list names
`iState_NPCDrunk` "Sets actor in a drunk state" (<https://ck.uesp.net/wiki/List_of_Animation_Variables>).

[WARNING] Whether the game keeps the drunk state in a save, or after the actor's graph reloads,
is not known. OpenSky loses it when the graph stops.

## How `iCombatStance` is encoded

Only the horse graphs read `iCombatStance`. It picks the start state of `StandingIdleBehavior`:
0 starts `NonCombat`, 1 starts `Combat`. The transitions between them fire on `combatStanceStart`
and `combatStanceStop`. The engine writes 1 while the rider's (or the horse's own) weapon is drawn,
and raises the event on the edge. Every actor graph gets the same write, so an NPC horse follows
its rider too.

## Outputs the graph publishes

The graph writes these through `BSIsActiveModifier`, a state machine's `isActive` or
`currentStateId`, a sync variable ([behavior state machines](/engine/behavior-state-machines.md)),
or an expression assignment. Examples: `bAnimationDriven`, `bAllowRotation`, `bEquipOK`,
`IsRecoiling`, `bIsSynced`, `iSyncIdleLocomotion`. No engine system acts on them yet.

## Variables left unwritten

Many names on the Creation Kit list are tuning values. The graph file gives them a non-zero
start value, such as `fMinSpeed`, `TurnMin`, `RotMax`, `SpeedAcc`, `PitchAcc`, `PitchThresh`,
`iCharacterSelector`, and `iSyncTurnDirection`. No script reads them, so OpenSky keeps the
graph's own value ([gap report](/tools/gaps.md)).

These still need a value from the engine, and no OpenSky system can give it yet:

- `attackIntroLength`, `attackPowerStartTime`, and `weapChangeStartFraction`: the game times
  attack and weapon-change blends with them. No source gives the value.
- `PitchOffset`, `TweenPosition`, and `TweenRotation`: dragon flight.
- `IsInCastStateDamped`: a damped copy of `IsInCastState`. No source gives the damping rate.

Perk flags such as `bPerkQuickShot` come from the perk entry point Set Boolean Graph Variable; the
combat runtime writes them while the perk applies.
