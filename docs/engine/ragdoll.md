---
type: Subsystem
title: Death and ragdoll
description: How an actor at zero health dies and hands its skeleton to physics, how the
  simulated pose reaches skinning, what is saved about a corpse, and how a corpse is looted.
tags: [engine, physics, havok, ragdoll, actors, animation, persistence]
---

# Death and ragdoll

An actor whose health reaches zero raises the death events its behavior graph declares. When
the graph reaches its ragdoll hand-off, the skeleton's Havok bone bodies are created at the pose
the animation holds. The joints are then solved on the fixed physics step
([ragdoll joint solver](/engine/ragdoll-solver.md)). The simulated bones write back through the
same pose path skinning reads. The corpse settles, its resting place is saved, and using it opens
a container over its inventory.

## Death and the hand-off

Every name here came from the behavior census over the local install
([behavior runtime](/engine/behavior-runtime.md)):

| Direction | Names |
| --- | --- |
| Raised when health reaches zero | `bleedOutStart`, `DeathAnim` |
| Watched for as the hand-off | `AddRagdollToWorld`, `NPCAddRagdollToWorld`, `Ragdoll`, `RagdollInstant` |

One frame runs in this order:

1. Zero health becomes a death. The engine writes the death component and asks the graph to play
   the death. It does not decide when the animation ends.
2. The fixed steps advance the graph, and the graph fires its events.
3. A hand-off event creates the bodies. `RagdollInstant` asks for no blend. The other three blend
   over the `m_durationToBlend` of the controlling `hkbRigidBodyRagdollControlsModifier`.
4. The live ragdolls step. Any that came to rest write their resting transform into their death
   component.

A death whose graph never hands off costs one death component and no bodies. That is wrong in a
visible way: the actor is dead and still standing, not dead in a pose the engine made up.

Only the player has a behavior graph. So an NPC declares none of these names. When no graph takes
the death event, the hand-off happens at once. The two routes are counted separately, so a
session can tell "the graph drove this" from "the engine had to".

## Writing the pose back

The pose path ends in one skeleton-space matrix per bone name, which skinning reads
([actor animation](/engine/actor-animation.md)). A simulated bone writes into the same table. The
scene keeps one ragdoll pose per corpse `ACHR`, laid over the clip's pose during the animation
update. So a corpse reaches skinning through the same call as an idle animation, and the renderer
knows nothing about physics.

Bones the ragdoll does not simulate (fingers, the skirt chain, weapon nodes) keep the animated
pose. That is why a corpse still has hands. During the blend, the two poses mix per bone:
translation by linear interpolation, rotation by spherical interpolation. After it, only the
simulated pose is used.

## Saving a death

Death is its own world state component, beside actor values, not inside them. Current health is
rewritten every regeneration step. Death is a latch that only a resurrection clears. It is saved
in its own `DETH` chunk. A build that does not know the chunk skips it and loads the rest
([save chunks](/formats/opensky-save-actor-chunks.md)).

The resting root transform is saved. The pose of each bone is not. 18 bodies is 144 floats per
corpse, and each would have to survive a save, a load, and a cell rebuild.

A player can see the result: a corpse reloads at the place and facing where it came to rest, but
in the skeleton's rest pose, not in the exact shape it died in. A body that fell face down across
a stair comes back face down at the foot of the stair, lying straight. Saving the full pose later
would add a field to the component, not change its shape.

## Looting a corpse

There is no new menu and no new session type. A container session opens over any inventory
owner. An `ACHR`'s inventory starts from its `NPC_` `CNTO` list, just like a chest's
([interaction](/engine/interaction.md)). Opening the container menu with no chest under the
crosshair picks the nearest dead actor.

It picks the nearest one, not the crosshair target, because an `ACHR` is not a usable target. The
cell build makes those from `CONT`, `DOOR`, `ACTI`, `TREE`, `FURN`, and item bases. A "Search"
prompt on actors would also appear on living ones.

## Behavior modifiers

Three ragdoll modifier classes are decoded ([behavior node classes](/formats/hkx-behavior-nodes.md)):

| Class | Status |
| --- | --- |
| `hkbRigidBodyRagdollControlsModifier` | Used: gives `m_durationToBlend` as the hand-off blend time |
| `hkbPoweredRagdollControlsModifier` | Used: gives the motor that holds the bones during the blend |
| `BSRagdollContactListenerModifier` | Used: its `m_contactEvent` fires when a ragdoll first touches the world |

`m_bones` is not read. The ragdoll is every bone the skeleton NIF has a body for. That is the same
set on every vanilla character, and it comes from the physics data, not the graph. `0_master.hkx`
has exactly one instance of the class, `DriveRagdollRB`, which blends over 0.5 seconds. A session
with no graph uses that value.

The modifiers run each graph update. When a modifier stops running, its setting stops applying.

The powered modifier gives `m_tau`, `m_damping`, `m_maxForce`, and the two recovery velocities.
During the blend, a motor pulls each bone body back toward the pose it had at the hand-off. Each
step changes the body's velocity toward a target speed: `m_proportionalRecoveryVelocity` times the
distance, plus `m_constantRecoveryVelocity`. `m_tau` is how much of the gap one step closes, and
`m_damping` slows the body's own motion. The pull fades as the simulation takes over, and stops
when the blend ends. The force and the constant speed are in metres in the file, so OpenSky scales
them by the Havok-to-engine scale.

This differs from the game. Havok drives the bones with constraint motors toward the pose the
animation holds now. OpenSky changes velocities toward the hand-off pose. The result is the same
kind of motion: a corpse sags over the blend instead of dropping at once.

The contact listener fires once when a ragdoll begins touching the world. It fires again only
after the ragdoll has left the ground. OpenSky counts contacts per ragdoll, not per bone, so the
modifier's `m_bones` list is not used.

## Death effects

The install's game settings drive what a death leaves besides the fall. The Creation Kit wiki
lists their values but not their rules (<https://ck.uesp.net/wiki/Category:Settings>), so each
use below is OpenSky's reading. Confirm the look in a play test.

| Setting | Value in `Skyrim.esm` | OpenSky's use |
| --- | --- | --- |
| `fDeathForceDamageMin`, `...Max` | 1, 40 | Melee damage range of the push |
| `fDeathForceForceMin`, `...Max` | 4, 12 | Push for that range, blended and held at the ends |
| `fDeathForceRanged...` | 1, 50; 10, 30 | The same for arrows and bolts |
| `fDeathForceSpellImpactMult` | 2 | A spell pushes as a ranged hit times this |
| `iDeathDropWeaponChance` | 100 | Chance in percent that the dead drop a drawn weapon |
| `iCombatDismemberPartChance` | 50 | Chance in percent that a qualifying kill cuts the head |
| `iRemoveExcessDeadCount` | 15 | More dead than this loaded, and the oldest go |
| `fRemoveExcessDeadTime` | 10 | Seconds a body must be dead before it can go |

The push:

- The last landed hit counts for 2 seconds. A later death, such as from bleeding, pushes nothing.
- A spell's damage is the sum of its magnitudes. It pushes from where it landed.
- The push is a Havok impulse on the heaviest bone body. It points away from the attacker and
  leans up by a quarter, so the body lifts a little as it falls back.

The weapon drop puts the right-hand weapon on the ground under the hand. The visuals of an NPC
are built once, so the weapon's node and its sheath node are shrunk to a point in the published
pose instead of the mesh being rebuilt.

Decapitation is the only dismemberment in Skyrim. The head is body part type 1
(<https://ck.uesp.net/wiki/Skyrim_bodyparts_number>). In the game, a standing power attack can
decapitate when the attacker has the Savage Strike (one-handed) or Devastating Blow (two-handed)
perk (<https://en.uesp.net/wiki/Skyrim:One-handed>, <https://en.uesp.net/wiki/Skyrim:Two-handed>).
OpenSky rolls `iCombatDismemberPartChance` on such a kill, with any blade, axe, or mace. The cut:

- The node of the race's `BPTD` head part, with every bone under it, is shrunk to a point. The
  node is kept in the death state, so a loaded save shows the body without its head.
- The part's severable explosion plays unless the race has the no-blood-spray flag.
- The race's `NAM7` decapitation art is attached. Without it, `sDismemberParticleDefault` plays,
  which `Skyrim.esm` leaves empty.
- The default blood decal goes on the ground unless the race has the no-blood-decal flag.

A body is kept from removal while any quest alias holds it. Removal deletes the reference.

## Bleedout

An essential actor does not die. When its health share falls to the "Bleedout Default" ratio of its
class, or its health reaches zero, it kneels in bleedout instead (Creation Kit wiki
[Class](https://ck.uesp.net/wiki/Class)). A protected actor does the same, unless the player dealt
the last blow. A kneeling actor leaves combat, and its scripts get `OnEnterBleedout()`. A script's
`SetEssential` or `SetProtected` wins over the base flag. After `fEssentialDeathTime` seconds the
actor stands up with full health (UESP "Skyrim:Essential NPCs" and "Skyrim:Protected NPCs").
An actor whose class is unknown uses `fBleedoutDefault` as its ratio. No open source defines the
two settings; OpenSky reads them from their names. `fBleedoutMin`, `fBleedoutRate`, and
`fBleedoutRecover` are not read. Sources for the events: the Creation Kit wiki pages
[OnEnterBleedout](https://ck.uesp.net/wiki/OnEnterBleedout_-_Actor) and
[StartDeferredKill](https://ck.uesp.net/wiki/StartDeferredKill_-_Actor).

`SetNoBleedoutRecovery(true)` keeps a kneeling actor down until a script clears it.

`StartDeferredKill` holds the death of an actor at zero health. The actor stays alive until a
script calls `EndDeferredKill`; the next zero-health frame after that kills it.

To see it in the running game, set an essential actor's health near zero with
`openskycli game debug av Health --value 1 --ref <id>`, then read its `bleedingOut` flag with
`openskycli game state scripts <id>`.

The player does not bleed out yet, and a quest alias that makes an actor essential or protected
is not read.

## Not done yet

- Ragdolls without death, such as paralysis or a knockdown.
- The neck stump armour of the race (`DNAM`) and the flying head. The NPC visuals do not rebuild
  when equipment changes.
- The skin partitions of `BSDismemberSkinInstance` are not used; the cut hides bones instead.
