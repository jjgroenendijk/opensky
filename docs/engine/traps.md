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

The same rule applies to placed actors (`ACHR`), and a parent can be an actor. The opening of
the game needs both: the second cart horse and both carts start disabled and name the first
horse as their parent.

Parents are looked up among the cell's own references and actors and, for an exterior cell,
every persistent reference and actor of the worldspace. A parent elsewhere, such as in another
interior, is counted as unresolved and the child keeps its own state. Papyrus `IsEnabled` uses the same
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
| `ObjectReference.ProcessTrapHit` | Takes the damage off the receiver's Health, knocks it back, and staggers it |
| `ObjectReference.PlaceAtMe` | Spawns a hazard, detonates an explosion, or places an object, see below |
| `ObjectReference.ApplyHavokImpulse` | Pushes the receiver's simulated body |
| `ObjectReference.PushActorAway` | Knocks the actor argument back, away from the receiver |
| `ObjectReference.SetMotionType` | Makes the receiver's collision simulate or hold, see below |
| `ObjectReference.Reset` | Puts an object back at its plugin place, see below |
| `Weapon.Fire` | Fires an arrow or dart from a reference, see below |
| `ObjectReference.GetBaseObject` | The base form |
| `ObjectReference.GetNthLinkedRef` | Follows the untagged `XLKR` link n times |
| `ObjectReference.GetAngleX`, `GetAngleZ` | Rotation about X or Z, in degrees |
| `ObjectReference.IsLockBroken` | Always false: OpenSky never breaks a lock |
| `Utility.GetCurrentRealTime` | Seconds since the first call |
| `FormList.GetSize`, `FormList.GetAt` | The list's plugin entries. A nested list is one entry, and a runtime `AddForm` is not seen |

Without a running game (the CLI and the package tests) the world natives above are
traced stubs too.

A trap whose mesh names a behaviour graph runs it, and the animation natives drive that
graph ([object animation](/engine/object-animation.md)). For a trap without a graph,
`WaitForAnimationEvent` waits one second of real time, then answers true. A thresher repeats
`PlayAnimation` and `WaitForAnimationEvent` while its cell is loaded. An instant answer
would run that loop thousands of times in each frame.

Traced stubs answer the type's empty value and count as stubbed in the Papyrus tally, so the
script runs on:

- Destruction: `ClearDestruction`, `DamageObject`, `SetDestroyed`,
  `GetCurrentDestructionStage` (0, intact).
- Effects and feedback: `Game.ShakeCamera`, `Game.ShakeController`, `Sound.Play`,
  `EffectShader.Play`, `Say`, `Message.Show`, `InterruptCast`.
- Animation: `SetAnimationVariableFloat`,
  `GetAnimationVariableFloat` (0), `Form.RegisterForAnimationEvent` (true),
  `Form.UnregisterForAnimationEvent`.
- Records and world: `AddItem`, `BlockActivation`, `CreateDetectionEvent`,
  `SetActorCause`, `CalculateEncounterLevel` (1), `GetActorOwner`, `GetFactionOwner`,
  `GetParentCell` (None), `SetNoFavorAllowed`,
  `FormList.HasForm` (false), `Actor.GetEquippedItemType` (0),
  `Cell.IsAttached` (true).

## Placing with PlaceAtMe

`ObjectReference.PlaceAtMe(form, count)` places `count` copies of `form` at the receiver.
A `HAZD` hazard spawns at the receiver and lives out its lifetime; the call answers the last
spawned hazard. An `EXPL` explosion detonates at the receiver; the call answers None, because an
explosion leaves no reference a script can hold. A hazard or an explosion takes the receiver's
position, not its rotation.

Any other base becomes `count` spawned references at the receiver's position and rotation, and
the call answers the last one. A spawn is saved and built like a dropped item, so an actor base
places an actor. `PlaceActorAtMe(base, levelMod, zone)` places one actor the same way. It does not
read the level modifier or the encounter zone.

## Impulses and pushback

`ApplyHavokImpulse(x, y, z, magnitude)` pushes the receiver's dynamic body with the unit
direction times the magnitude. The CK wiki
([ApplyHavokImpulse](https://ck.uesp.net/wiki/ApplyHavokImpulse_-_ObjectReference)) says the
vector is normalized first and a zero-length vector fails; OpenSky does both. Papyrus gives
the impulse in Havok units, so OpenSky scales it by 69.99 game units per metre. A reference
with no dynamic body does not move.

`ProcessTrapHit(trap, damage, pushback, xVel, yVel, zVel, xPos, yPos, zPos, material,
stagger)` knocks the hit actor back at `pushback` units per second, along the trap's velocity.
With no velocity it pushes away from the trap. A stagger above 0 staggers the actor with that
magnitude, at most 1, through the same path a stagger spell takes.

`PushActorAway(actor, force)` pushes away from the receiver at 100 units per second per point
of force. A negative force pulls the actor in, as the CK wiki
([PushActorAway](https://ck.uesp.net/wiki/PushActorAway_-_ObjectReference)) notes.

The knockback is horizontal, is capped at 1500 units per second, and fades on the ground in
about one second. The player slides on the walk capsule. An NPC that is walking takes the push
on its walk capsule. A standing NPC slides on a capsule of its own until the push drops below
5 units per second on the ground, or for at most 3 seconds, and then stands where it stopped.

[WARNING] Neither scale is confirmed against the game. The game also ragdolls an actor that
`PushActorAway` hits, "as if an explosion had gone off"; OpenSky only slides it.

## Motion type

`SetMotionType(type, allowActivate)` sets whether a reference's collision simulates. The
values come from the CK wiki
([SetMotionType](https://ck.uesp.net/wiki/SetMotionType_-_ObjectReference)): 1, 2, 3, and 6
simulate, 4 and 5 hold. 7 is for characters and fails. The choice is stored on the reference,
saved in the `RMOT` chunk ([save format](/formats/opensky-save.md)), and read by the next build
of its cell:

- Dynamic: every body in the model with a positive mass simulates, whatever motion system the
  NIF gives it.
- Keyframed: no body simulates. A body that was moving keeps the pose it has now.

The shipped traps use this. `PhysicsTrap` (rock falls) and `MaceTrap` hold their objects when
the cell attaches. When the trap fires they set the objects dynamic and push them down with
`ApplyHavokImpulse(0, 0, -1, 15)`. The rebuild takes a few frames, so the impulse can reach
the object before its body exists; the body falls under gravity anyway.

`allowActivate` is not read: a body made dynamic falls at once.

## Reset

`Reset(target)` on an object drops the moves a script or physics made, drops the motion type,
and removes the simulated body, so the next build places the object where its plugin put it.
With a target it stands at the target instead. Every shipped trap calls it in `onReset`.

The CK wiki ([Reset](https://ck.uesp.net/wiki/Reset_-_ObjectReference)) says the game also
resets inventory and resurrects an actor. OpenSky does neither: other state stays, and `Reset`
on an actor stays a traced stub.

## Firing a weapon

`Weapon.Fire(source, ammo)` fires the weapon from a reference
([Fire](https://ck.uesp.net/wiki/Fire_-_Weapon)). Dart traps call it once per linked
reference, and ballistas and crossbow traps from themselves. OpenSky fires the ammo's
projectile from the source's position, level, along its heading (its rotation about Z). The
X and Y rotations are not used. Source: observed data. In `Pinewatch02` the dart ports on the
west wall are turned +90 degrees about X with a heading of 81 degrees, and those on the east
wall -90 degrees with a heading of 263 degrees. Only the heading points both walls across the
corridor; the full facing points one wall at the ceiling and the other at the floor. The shot
spends no ammunition, and an arrow that misses still sticks. Its damage is the
weapon's base damage plus the ammo's, with no skill or perk term. The weapon's enchantment
applies too, and never runs out of charge: `TrapDartWeapon01` poisons with
`TrapDartPoisonWeapEnch01`. A dart does not explode. Its projectile `TrapDartWooden01` names
`FireBallExp01`, but its explosion flag (`0x02`) is off, and a projectile explodes only with that
flag. Of the 93 vanilla projectiles that name an explosion, 18 have the flag off, such as
`BoundArrowPROJ` and `VoiceFireBreathProjectile01`. The hit is credited to the
source, so it raises `OnHit` with the trap as the aggressor and gives the player no crime and
no sneak attack.

The CK wiki says a source with no `ammo` uses the ammo it has equipped. OpenSky fires nothing
then, because a trap equips nothing. Effect weapons that some traps fire for a hit effect, such
as `BladeTrapHit`, fire the same way when their ammo has a ballistic projectile.

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

A spawned hazard expires after its lifetime and respects the record's limit. It draws its `MODL`
model where it sits.

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

## Trap contact

A trap whose scripts handle `OnTrapHitStart`, `OnTrapHit`, or `OnTrapHitStop` is checked every
frame while its animation graph runs. At cell build, each rigid mesh that a rig bone moves gives
15 sample points: the corners, face centres, and centre of its bounds, in that bone's space. A
trap with no such mesh uses its bone origins instead. Each frame the current pose moves the
points. A point that moves faster than a minimum speed and comes close to an actor's capsule hits
that actor:

- The first hit sends `OnTrapHitStart` and then `OnTrapHit` with `abInitialHit` true.
- While contact lasts, `OnTrapHit` repeats at a fixed interval with `abInitialHit` false.
- When no point is near the actor any more, `OnTrapHitStop` follows.

The velocity argument is the point's velocity over the last frame. The material argument is 0,
and the motion type is keyframed. Sources: the Creation Kit wiki pages
[OnTrapHit](https://ck.uesp.net/wiki/OnTrapHit_-_ObjectReference) and
[OnTrapHitStart](https://ck.uesp.net/wiki/OnTrapHitStart_-_ObjectReference).

The game reads contact from the trap's collision bodies. OpenSky has no collision body that
follows a bone, so it measures mesh points against capsules. A swinging blade's only bone is
its pivot, which turns but does not move, so bone origins alone never hit. The reach, minimum
speed, and repeat interval are OpenSky's own numbers; no open source gives the game's.

## Not done

A swinging blade or a battering ram reports its hits through bone contact, not a collision
body. A pushed NPC slides instead of falling as a ragdoll.
