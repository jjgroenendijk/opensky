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
6. A sprint or sneak gait.
7. A drawn weapon, by the right-hand type: one-handed, two-handed, bow or crossbow, or staff or
   spell. The type uses the `iRightHandType` encoding ([combat graph names](/engine/combat-graph-names.md)).
8. Otherwise `iState_NPCDefault`.

[INFO] This order is OpenSky's own. No source states the game's order. Bleedout,
drunk, quick shot, and shield charge have no OpenSky system yet, so no step picks them.

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
