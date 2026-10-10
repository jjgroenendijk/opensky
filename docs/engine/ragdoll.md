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

## Not done yet

- Ragdolls without death, such as paralysis or a knockdown.
- Dismemberment.

## Controls

World > Combat & Physics > Death & Ragdoll:

- Ragdoll selected actor: kills and hands off the crosshair target, or else the nearest loaded
  actor. It calls the same function as a death in a fight, so the two cannot differ.
- Clear ragdolls: removes every live ragdoll. The deaths stay.
- Freeze ragdoll stepping: stops the solver with the corpses where they are.
- Bones collide with each other: turns self-collision on or off for the allowed pairs, and wakes
  every corpse so the change shows.
- Readout: live and settled counts, bone bodies and joints, solver iterations and errors, allowed
  pairs and bones touching, and final pose corrections.
