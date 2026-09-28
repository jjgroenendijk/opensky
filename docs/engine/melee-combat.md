---
type: Subsystem
title: Melee combat
description: Draw and sheath, attack and block, the hit volume, damage and the block formula,
  stagger, and impact sound, all driven by the behavior graph's own events.
tags: [engine, combat, melee, behavior-graph, weapons, damage, gmst]
---

# Melee combat

This page covers one swing, from the key press to the health that comes off. The graph is on the
[behavior runtime](/engine/behavior-runtime.md) page, and the names it uses on the
[combat graph names](/engine/combat-graph-names.md) page. The sweep comes from
[dynamic body contacts](/engine/dynamic-narrowphase.md). Health is on the
[actor values](/engine/actor-values.md) page.

## The graph decides

The engine raises `attackStart`. It does not decide that an attack began. The behavior graph
decides whether an attack state was entered, how long the windup lasts, and which frame connects.
It says so by firing events back. So every melee state is read from the graph, not timed beside
it.

The footstep sounds follow the same rule for the same reason. A phase from a separate clock drifts
away from the animation the player sees, and a hit on that clock lands when the swing is not
there. Also, there is no engine swing timer to cancel: a stagger that takes away the attack state
takes the phase with it.

One frame of melee, in order:

1. Input edges become raised events.
2. The fixed steps advance the graph.
3. The fired events move the melee state. On the contact frame, the sweep runs and damage applies.

## Graph events reach several listeners

The queue of fired graph events keeps one cursor per listener: footsteps and melee. Each listener
sees every name once, in order, however many frames apart it reads. A queue that is emptied by
reading cannot have two listeners: the first would take everything.

Cursors are positions in a sequence that only grows, not indexes into storage. So dropping old
names from the front cannot move anyone's place. A name is dropped once every listener has read
past it. The limit, 64, counts unread names, so a listener that stops reading loses only its own
tail. With no listener, names are dropped at once. So both cursors are created up front: a cursor
created on first read would find the queue already empty.

## Draw and sheath

| State | The weapon is on |
| --- | --- |
| Sheathed | The sheath node |
| Drawing | The sheath node |
| Drawn | The hand node (`Weapon`) |
| Sheathing | The hand node |

The weapon moves on the clip mark, not on the request. `weaponDraw` starts drawing, and the weapon
stays where it is. `BeginWeaponDraw` arrives when the hand reaches it, and that frame moves the
model. Sheathing is the mirror. The node names are on the
[actor appearance](/engine/actor-appearance.md) page.

Not every equip clip has that mark. `1HM_Equip.hkx`, `Bow_Equip.hkx`, and `CrossBow_Equip.hkx`
have it at time 0.0. `Dag_Equip.hkx`, `Axe_Equip.hkx`, `Mac_Equip.hkx`, `2HC_Equip.hkx`, and
`2HW_Equip.hkx` have none, and only mark `weaponDraw` in the middle of the clip, which is easy to
confuse with the engine's own `weaponDraw`. So the graph's `WeapEquip_Out`, the transition
`0_master.hkx` takes into `Weap_Readied_State`, is a second way in, and `Unequip_Out` its mirror.
The clip mark is earlier and wins when a clip has it. The transition keeps a dagger from being
stuck mid-draw. Whichever comes first moves the weapon, once.

A mark at the clip's very first frame is why the first update of a clip checks a closed interval
([behavior runtime](/engine/behavior-runtime.md)). Under the half-open rule of later updates,
`BeginWeaponDraw` at 0.0 could never fire.

## Attack phase

```text
idle -> windup (attackStart) -> swinging (preHitFrame) -> contact (HitFrame)
     -> recovery -> idle (attackStop)
```

Only the contact phase can hit. `preHitFrame` says a hit is near, so a listener has a frame to
prepare. The sweep still runs on the contact frame. Recovery starts at the end of the frame, so a
swing that fires `HitFrame` and nothing else does not stay in the hit phase forever.

A sheath or a `staggerStart` drops the phase to idle. No swing starts with a sheathed weapon or
during a stagger.

## Reach and the hit volume

Reach is the documented combat distance formula:

```text
reach = fCombatDistance * actorScale * WEAP.reach
```

UESP "Skyrim Mod:Mod File Format/WEAP" states it for `DNAM` offset `0x08`: "For melee weapons,
this is a multiplier used in the reach formula: `fCombatDistance * NPCScale * WeaponReach`".
xEdit names the same `DNAM` member at the same offset. `fCombatDistance` is 141.000 on the local
install.

The swing volume is a swept capsule. A swing is a blade segment moving along an arc, and a swept
capsule is a safe outer shape for it. The arc is not rebuilt from the animation pose. A hit from
one sampled frame of a 30 Hz clip lands wherever that frame was, and the contact frame is one mark,
not a window. The volume uses the attacker's facing at the contact frame, which is where the
player aimed.

Two numbers are OpenSky's choices. Vanilla's hit volume is in its code, not in the install:

- Half height: 0.25 x capsule height, centered on the chest. It reaches a target on the same
  floor, but not one standing on a table.
- Radius: 0.75 x capsule radius. It stands in for the width of the arc, not for the blade.

The test against a target is capsule against capsule: the shortest distance between two segments
against the sum of the radii, which is exact. The sweep is sampled at 24 steps with no bisection. A
tunneling guard needs the exact moment of contact, but a swing only needs whether it hit and
roughly where.

## Targets

1. Only actors. The caller gives the target list, so a barrel is never in it.
2. Never the attacker. Matched by `ReferenceKey`, not distance. The swing starts inside the
   attacker's own capsule, so otherwise it would always be the nearest.
3. At most one hit per swing per target. This is held by swing number, not time. A graph can fire
   two contact marks in one attack (the census shows `2_HitFrame` beside `HitFrame`), and it still
   lands once. The next swing can hit the same target again.

Every target the swing reaches is hit, not only the nearest. A two-handed sweep through a crowd
hits the crowd. Picking one would be a rule made up here. Order is nearest first, then the lower
reference.

## Damage

Unblocked damage is the `WEAP` `DATA` base damage. How blocking and bonus terms change it is on
the [melee damage](/engine/melee-damage.md) page.

## Stagger

A hit whose weapon has `DNAM` `stagger` writes `staggerMagnitude` on the target's graph, then
raises `staggerStart`. Writing first means the stagger reads this hit's magnitude, not the last
one's.

Only the player has a behavior graph. A stagger raised on an NPC answers false, and the trace
records the hit as not staggered.

## Impact sound

This is the footstep chain with one link changed:

```text
footstep: graph event -> FSTP tag  -> IPDS -> IPCT for the material -> SNDR
melee:    HitFrame    -> WEAP INAM -> IPDS -> IPCT for the material -> SNDR
```

From `IPDS` on, the two are the same code ([footstep](/formats/footstep.md)). `WEAP` `INAM` is
"Normal weapon swing impact set. Points to a IPDS" (UESP). `BIDS` is the block and bash set, read
only by a bash ([item records](/formats/item-records.md)).

The material is the ground under the player, not the body part that was hit. Actors have no Havok
material per body part here. Every link is optional. A missing link ends the chain with a silent
hit, not an error. Hit decals and visual effects are not done.

## Input

| Key | Action | Kind |
| --- | --- | --- |
| `R` | Draw or sheath | One press, one binding for both |
| Left mouse | Attack | One press (the first click still captures the cursor) |
| Right mouse | Block | Held, raised on press and release |

These take the same input path as sneak, sprint, and jump. The fixed movement step never reads
them: attacking does not move the capsule. The graph does that, if its attack clips carry movement.

Losing cursor capture drops the guard, because a block held through a lost mouse-up would stay up
forever. The drawn state stays, like sneak, because the player set it on purpose.

## Controls

World > Combat & Physics > Melee: Weapon drawn (raises draw or sheath), Attack (one swing), Clear
hit trace, and a readout of the state, weapon, reach, both hand types, and the last hits.

Block is held, so it is shown live in the state line, not as a checkbox. A checkbox would hold it
for one frame and look broken. The section has no reset. A drawn weapon is world state, and "Reset
all" must not sheath it.
