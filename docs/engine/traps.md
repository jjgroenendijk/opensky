---
type: Subsystem
title: Traps, enable parents, and hazards
description: How shipped trap scripts run, how XESP enable parents decide what is enabled, the
  trap native census, and the hazard runtime for PHZD placed hazards.
tags: [engine, scripting, magic, streaming]
---

# Traps, enable parents, and hazards

Vanilla traps are Papyrus scripts. A pressure plate or tripwire is a trigger volume with a
script. When the player walks in, the volume's `OnTriggerEnter` runs, and the script fires the
trap it is linked to through `XLKR`. The trap script plays animations, enables effect
references, and damages whoever it hits. OpenSky runs those scripts as shipped. It adds no
trap rules of its own.

## Enable parents

A placed reference can name an enable parent in `XESP`
([placed references](/formats/placed-references.md)). The CK wiki ("Enable Parent") says a
child follows its parent, and that `Enable` and `Disable` on a child have no effect. OpenSky
resolves the effective state like this:

1. No `XESP`, or the parent cannot be found: the reference's own state. That is its runtime
   enable state if a script set one, else the opposite of its initially-disabled flag.
2. The parent was found: the parent's effective state, inverted when flag 0x01 ("set enable
   state to opposite of parent") is set. A chain resolves to its root, up to 16 links.

A disabled reference drops out of rendering, collision, and trigger volumes. The cell build
counts it as "disabled", apart from a reference a script disabled.

Parents are looked up among the cell's own references and, for an exterior cell, every
persistent reference of the worldspace. A parent elsewhere, such as in another interior, is
counted as unresolved and the child keeps its own state. Papyrus `IsEnabled` uses the same
rule over resident references.

When a reference's enable state changes, every resident cell with a reference or hazard that
names it as `XESP` parent is rebuilt. This is the cascade that makes a fire trap's flames
appear when its plate enables their parent.

## Native census

`TrapScriptCensusRealDataTests` lists every native that the shipped trap and trigger scripts
call: every script named `trap*`, plus `pressureplate`, `pressurereleaseplate`, `tripwire`,
`darttrap`, `bladetrap`, `bladetraphit`, `macetrap`, `swingingwalltrap`, `hazard`,
`hazardbase`, `magicplacehazard`, and `defaultbipressureplate`. The test fails on any native
the registry does not hold.

Implemented for traps:

| Native | Behavior |
| --- | --- |
| `ObjectReference.GetTriggerObjectCount` | Actors standing in the volume, from the trigger enter and leave events |
| `ObjectReference.ProcessTrapHit` | Takes the damage off the receiver's Health and knocks it back. Stagger is dropped |
| `ObjectReference.PlaceAtMe` | Spawns a hazard or detonates an explosion, see below |
| `ObjectReference.ApplyHavokImpulse` | Pushes the receiver's simulated body |
| `ObjectReference.PushActorAway` | Knocks the actor argument back, away from the receiver |
| `ObjectReference.GetBaseObject` | The base form |
| `ObjectReference.GetNthLinkedRef` | Follows the untagged `XLKR` link n times |
| `ObjectReference.GetAngleZ` | Rotation about Z, in degrees |
| `ObjectReference.IsLockBroken` | Always false: OpenSky never breaks a lock |
| `Utility.GetCurrentRealTime` | Seconds since the first call |
| `FormList.GetSize`, `FormList.GetAt` | The list's plugin entries. A nested list is one entry, and a runtime `AddForm` is not seen |

Without a running game (the CLI and the package tests) the four world natives above are
traced stubs too.

`WaitForAnimationEvent` waits one second of real time, then answers true. No animation event
arrives, because OpenSky plays no object behavior graph. A thresher repeats
`PlayAnimation` and `WaitForAnimationEvent` while its cell is loaded. An instant answer
would run that loop thousands of times in each frame.

Traced stubs answer the type's empty value and count as stubbed in the Papyrus tally, so the
script runs on:

- Havok and motion: `SetMotionType`, `Reset`.
- Destruction: `ClearDestruction`, `DamageObject`, `SetDestroyed`,
  `GetCurrentDestructionStage` (0, intact).
- Effects and feedback: `Game.ShakeCamera`, `Game.ShakeController`, `Sound.Play`,
  `EffectShader.Play`, `Say`, `Message.Show`, `Weapon.Fire`, `InterruptCast`.
- Animation: `SetAnimationVariableFloat`,
  `GetAnimationVariableFloat` (0), `Form.RegisterForAnimationEvent` (true),
  `Form.UnregisterForAnimationEvent`.
- Records and world: `AddItem`, `BlockActivation`, `CreateDetectionEvent`,
  `SetActorCause`, `CalculateEncounterLevel` (1), `GetActorOwner`, `GetFactionOwner`,
  `GetParentCell` (None), `Form.HasKeyword` (false), `FormList.HasForm` (false),
  `Actor.GetEquippedItemType` (0), `Cell.IsAttached` (true).

## Placing with PlaceAtMe

`ObjectReference.PlaceAtMe(form, count)` places `count` copies of `form` at the receiver.
OpenSky places two kinds of base form. A `HAZD` hazard spawns at the receiver and lives out
its lifetime; the call answers the last spawned hazard. An `EXPL` explosion detonates at the
receiver; the call answers None, because an explosion leaves no reference a script can hold.
The placed object takes the receiver's position, not its rotation.

## Impulses and pushback

`ApplyHavokImpulse(x, y, z, magnitude)` pushes the receiver's dynamic body with the unit
direction times the magnitude. Papyrus gives the impulse in Havok units, so OpenSky scales it
by 69.99 game units per metre. A reference with no dynamic body does not move.

`ProcessTrapHit(trap, damage, pushback, xVel, yVel, zVel, ...)` knocks the hit actor back at
`pushback` units per second, along the trap's velocity. With no velocity it pushes away
from the trap. `PushActorAway(actor, force)` pushes away from the receiver at 100 units per
second per point of force. The knockback is horizontal, is capped at 1500 units per second,
and fades on the ground in about one second.

[WARNING] Neither scale is confirmed against the game. The game also ragdolls an actor that
`PushActorAway` hits; OpenSky only moves the player and does not push NPCs.

## Hazards

A `PHZD` places a `HAZD` hazard ([hazard records](/formats/hazards.md)). On the install 369 of
the 394 `PHZD` records carry an `XESP` parent: they are trap effects that wait for their trap.
A cell build keeps the enabled `PHZD` records of the cell. The hazard runtime holds them while
the cell is live and replaces them when the cell is rebuilt.

| `HAZD DATA` field | Use |
| --- | --- |
| Radius | An actor is inside when its capsule is within this distance |
| Target interval | An actor is hit on entering, then once per interval while inside. At least 0.1 s |
| Lifetime | Only a spawned hazard expires. A placed one lasts while its cell is live and enabled |
| Limit | The most spawned copies at once; the oldest goes first |
| Flag 0x01 | Affects the player only |
| Spell | Applied through the spell-hit path, sourced to the hazard |

The interval-per-target and lifetime readings are OpenSky's: no open source states them. A hit
goes through the same path as a landed spell, so resistances, death, and the actor's health
work as for any spell. Hazards step on world time and stop while a menu pauses the world.

## Spawned hazards

An explosion whose placed object is a `HAZD` spawns that hazard at the blast point, and the
Effects panel can spawn one in front of the camera. A spawned hazard expires after its
lifetime and respects the record's limit. It draws its `MODL` model where it sits. The panel
lists each live hazard with its position, remaining lifetime, and tick count: the number of
steps on which it hit someone.

## Activate parents

A trap does not listen to its plate through a linked reference. The trap's `XAPR` field names
the plate as an activate parent ([placed references](/formats/placed-references.md)). When the
plate's script calls `Activate(self)`, every resident reference that names the plate is
activated too, with the plate as the activator, and so on down the chain. Each reference is
activated once per chain, so a loop of parents ends.

Two parts of `XAPR` and `XAPD` are not used. The delay is ignored, so a child activates at once.
The "parent activate only" flag is not enforced, so the player can still activate such a child
directly. The field meanings come from xEdit's record definitions. The behavior is the
Creation Kit's "Activate Parents" tab as it is commonly described. It is not yet checked against
the CK wiki, which was unreachable when this was written. The trap test cell agrees with it:
its pressure plate names no linked reference, and one reference names the plate through `XAPR`.

## Disarming

A tripwire or pressure plate is activated with the use key like any activator. The press
reaches the reference's scripts as `OnActivate`, and the shipped script decides whether it
disarms. OpenSky adds no disarm rule. A spent trap is a script state too: a tripwire stays in
`active` after it fires, and a plate goes to `DoNothing` while an actor stands on it.

## Checking it in the app

World > World > Traps lists every loaded reference with a trap-family script, with each
script's Papyrus state and how many actors stand in its volume. The script state is how a trap
says armed or disarmed. The selected trap gets a red marker. Fire sends the volume an enter
and a leave, as a walk across it would. Disarm presses the use key on it. The readout shows
the selected reference's enable-parent chain with each link's effective state, and every live
hazard with its lifetime and last hit. The record views in the Asset Browser decode `HAZD`
and `PHZD`.

## Not done

Swinging blades and battering rams move through their behavior graph, which scripts start
with `PlayAnimation`. OpenSky does not play object behavior graphs yet, so these traps do not
swing. `SetMotionType` stays stubbed: OpenSky cannot turn a static object into a dynamic
body at runtime. `Weapon.Fire` stays stubbed: projectiles fire only from actors.
`PlaceAtMe` of any base other than a hazard or an explosion answers None: OpenSky has no
runtime-spawned references for other forms yet.
