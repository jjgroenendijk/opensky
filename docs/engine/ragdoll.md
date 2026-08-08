---
type: Subsystem
title: Death and constraint-solved ragdoll
description: How a zero-health actor dies, hands its skeleton to the physics, and collapses
  under a sequential-impulse joint solver - the ragdoll build, the constraint reading, the
  animated-to-simulated blend, pose write-back, persistence, and corpse looting.
tags: [engine, physics, havok, ragdoll, actors, animation, persistence]
timestamp: 2026-08-07T00:00:00Z
---

# Death and constraint-solved ragdoll

Milestone 15 item 15.6 is where an actor stops being an animation and becomes physics. An
actor whose health reaches zero raises the death events its behavior graph declares; when
the graph reaches its ragdoll hand-off, the skeleton's per-bone Havok bodies are spawned at
the pose the animation currently holds and solved against the joints
[item 15.1](/formats/nif-collision.md) decoded, on the same fixed step
[item 15.2](/engine/dynamic-bodies.md) already runs. The simulated bones write back through
the pose path the skinning palette already reads, the corpse settles, its resting transform
persists, and activating it opens a container over its inventory.

## Contents

* [Where the pieces live](#where-the-pieces-live)
* [Building a ragdoll](#building-a-ragdoll)
* [Reading the constraint angles](#reading-the-constraint-angles)
* [The solver, and the alternative it beat](#the-solver-and-the-alternative-it-beat)
* [Self-collision](#self-collision)
* [Settling](#settling)
* [Death and the hand-off](#death-and-the-hand-off)
* [Writing the pose back](#writing-the-pose-back)
* [Persistent death](#persistent-death)
* [Corpse looting](#corpse-looting)
* [The behavior modifier delta](#the-behavior-modifier-delta)
* [Sidebar and readouts](#sidebar-and-readouts)
* [Known limits](#known-limits)

## Where the pieces live

| File | What it holds |
| --- | --- |
| `opensky/Engine/Physics/RagdollDefinition.swift` | The immutable ragdoll: bones, joints, limits, bind frames |
| `opensky/Engine/Physics/RagdollDefinitionBuilder.swift` | Resolving a decoded `skeleton.nif` onto an animation skeleton |
| `opensky/Engine/Physics/RagdollJointGeometry.swift` | Anchors and angular violations; what the authored angles mean |
| `opensky/Engine/Physics/RagdollConstraintSolver.swift` | The sequential-impulse joint solver |
| `opensky/Engine/Physics/RagdollInstance.swift` | One live ragdoll: hand-off, blend, pose write-back, settling |
| `opensky/Engine/Physics/RagdollWorld.swift` | The registry, the fixed-step clock, the settled-pose drain |
| `opensky/Engine/Physics/RagdollRuntime.swift` | Death, event raising, activation, persistence, looting |
| `opensky/Engine/Combat/RagdollGraphNames.swift` | The census-named death and hand-off events |
| `opensky/Engine/Actors/ActorDeathComponent.swift` | The persistent death component |

The joints enter the existing step rather than a second one:
`DynamicBodySolver.step(bodies:world:dt:joints:)` takes them, and a non-empty list means
"these bodies are one ragdoll".

## Building a ragdoll

A skeleton NIF carries no ragdoll container class. What it carries is a set of
`bhkRigidBody` blocks each hanging off a `bhkBlendCollisionObject` that targets a named
`NiNode`, plus constraint blocks binding pairs of them
([NIF collision](/formats/nif-collision.md)). `RagdollDefinition(model:boneNames:bindMatrices:scale:)`
turns that into something the solver can advance:

* Each simulable body becomes one `DynamicBodyDefinition`, resolved onto an animation bone
  **by name** — the `NiNode` a carrier targets is spelled exactly as the `hkaSkeleton` bone
  is (`NPC L Calf [LClf]`).
* Each constraint becomes one joint, with both pivots and axes carried out of the entity's
  own local space, through `NIFCollisionBody.transform`, and into the body's
  centre-of-mass-local frame — the frame `DynamicBodyDefinition` re-centres its shapes into
  and the point every impulse is measured against.
* Each bone keeps its **bind-pose** matrix, which is where the animation skeleton draws it
  with nothing animated. `animatedBoneMatrix * bindInverse` is then the rigid transform that
  carries a body from its bind placement to wherever the animation has taken the bone;
  handing a ragdoll off is that product and writing a simulated bone back is its inverse.

Nothing is dropped silently. A body whose target names no bone, a body with no simulable
mass, a joint whose end points outside the decoded set, and a constraint class with no
limit model all land in `RagdollDefinition.skipped`. The vanilla humanoid produces an empty
list: 18 bones and 17 joints, none skipped.

## Reading the constraint angles

`bhkRagdollConstraint` stores five angles and `bhkLimitedHingeConstraint` two. Havok does
not publish what it does with them, so the readings below are stated rather than assumed.

| Field | Read as | Confidence |
| --- | --- | --- |
| `coneMaxAngle` | Upper bound on the angle between the two bodies' twist axes | Firm - it is what a cone limit means |
| `planeMinAngle` / `planeMaxAngle` | Signed bound on the twist axis leaving body A's plane | The one that could be something else |
| `twistMinAngle` / `twistMaxAngle` | Bound on the roll about the shared twist axis | Firm |
| `minAngle` / `maxAngle` (hinge) | Bound on the hinge's own rotation, same measurement as twist | Firm |
| `maxFriction` | A *rate*: fraction of the joint's relative angular velocity removed per second | A modelling choice, see below |

Two of those were settled by measuring the vanilla humanoid at its bind pose rather than by
reasoning, and the measurements are worth keeping.

**The direction the roll is measured in.** The angle runs from body B's reference axis to
body A's. That direction puts all four hinge kinds the skeleton carries inside their
authored ranges — knee -0.054 in `[-1.920, 0]`, ankle -0.498 in `[-0.596, 0.063]`, elbow
+0.019 in `[0, 1.920]`, wrist -0.060 in `[-0.087, 0.349]`. The opposite direction puts three
of the four outside, the ankle by 0.44 radians, which would have a standing skeleton
fighting its own ankle limit before anything moved. The vanilla cones all carry symmetric
twist ranges and so cannot tell the two directions apart; they follow the hinges.

**`maxFriction`'s unit.** The vanilla humanoid authors exactly two values across its
seventeen joints — 10.0 on every cone and 0.01 on every limited hinge — so there is no
distribution to infer a unit from. This engine reads it as a rate. The reading is bounded
in the only way that matters: friction can only take energy out, so a wrong scale makes a
corpse stiff or floppy and can never make one unstable.

The bind pose is otherwise very nearly satisfied, which is the evidence that the frame
mapping is right: every cone and plane angle comes out under 0.08 radians, and the pivots
coincide exactly on fourteen of the seventeen joints. The other three carry authored slack —
the knees by 4.3 engine units, the elbows by 2.6, the neck by 1.4, symmetrically left and
right — which is Bethesda's data rather than a decode error.

## The solver, and the alternative it beat

**Sequential impulse.** Each joint is visited a fixed number of times per substep; each
visit computes the constraint's current violation, solves for the impulse that removes the
violation's *rate*, and applies it to both bodies. Whatever drift survives is then pushed
out of the *poses* — positions and orientations — rather than out of the velocities.

**The rejected alternative was position-based dynamics (XPBD):** project the positions onto
the constraint manifold directly and read the velocities back out of the projection. PBD is
more forgiving of stiff joint chains at low iteration counts, which is a real advantage for
an eighteen-bone ragdoll, and it was seriously considered. It lost on one point: the contact
solver item 15.2 already shipped is sequential-impulse with position-level penetration
recovery, and a ragdoll bone is in contact with the floor and jointed to its neighbour *in
the same substep*. Running two solver families over one body's velocities means each undoes
part of the other's work every iteration, and the joint that lost the argument is whichever
was visited first. Matching the contact solver's family makes the two passes composable and
keeps one set of tuning constants for both.

Three rules keep it bounded, and each was put there by a measurement rather than by taste.

* **No restoring bias on a limit.** A first draft drove the violation's rate to a negative
  multiple of the error, so a violated limit would recover through the velocities. That is
  the textbook Baumgarte term, and it is exactly what the contact solver already refuses to
  do with penetration. The velocity it writes is energy the constraint invented: the
  real-data probe measured a vanilla humanoid climbing from 20 engine units a second to 52
  over thirty seconds, with one ankle limit's violation pumped from 0.27 to 1.77 radians.
  Recovery moved to the pose correction and the divergence went away.
* **The pose corrections accumulate and are applied once.** They make several passes over
  the joint list first, because a correction propagates exactly one link per pass and a
  humanoid is six links from pelvis to hand; with a single pass the knees sat seven engine
  units apart forever. But applying each pass in turn lets one substep spend the whole
  correction budget several times over, which is a teleport rather than a correction — and a
  teleport does work against gravity. Accumulate, clamp once, apply once.
* **Contacts and joints are one velocity solve.** Ordinary clutter still takes four contact
  iterations. A ragdoll takes sixteen combined iterations, alternating whether the contact or
  joint rows run first. Their accumulated impulses survive for the whole substep, so the
  floor and the chain converge together instead of four contact passes handing their answer
  to eight joint passes that always overwrite it last. Pose recovery restores joint drift
  first and floor penetration last, so it cannot manufacture the next substep's contact.
  The synthetic chain and vanilla humanoid both reach the ordinary per-body sleep thresholds
  through this path.
* **Every impulse is finite-checked and every effective mass is checked for magnitude before
  it divides anything.** A degenerate joint contributes nothing rather than a NaN.

Determinism follows the same shape as the contact solver: joints are visited in list order,
for a fixed iteration count, with no early exit that depends on anything but the joint's own
numbers. Two identical runs produce bit-identical poses.

## Self-collision

**A ragdoll's bones do not collide with each other.** A vanilla humanoid is eighteen
capsules whose radii run to eighteen engine units on bones about twenty long, so they
overlap heavily by construction — not just at the joints, but left thigh against right thigh
at the pelvis and upper arm against spine at the shoulder. Left switched on, the real-data
probe measured a corpse lying still on a floor carrying thirty to forty-five contacts and
jittering forever, because every overlap pushes and every joint pulls back.

The cost is the classic ragdoll self-intersection: a limb can pass through the torso. Havok
avoids it with a per-biped-part collision filter whose semantics this engine has not
confirmed against an open source. Reading `NIFCollisionFilter`'s biped bits correctly is the
honest way to get self-collision back, and it is tracked on
[issue #413](https://github.com/jjgroenendijk/opensky/issues/413) rather than guessed at
here.

## Settling

A ragdoll's interleaved constraint solve lets every bone reach 15.2's ordinary per-body
sleep thresholds. Before issue #407, the separate passes traded a thirty-to-fifty-unit-per-
second residual back and forth: the contact pass satisfied the floor, the joint pass always
ran last and reopened that solution, and the corpse crept about a unit a second.

`RagdollInstance` still carries a coordinated settling test. It asks the question a viewer
actually asks — has the body stopped *going* anywhere — and asks it of displacement rather
than the noisiest individual bone. The root travelling less than `settleDistance` over
`settleWindow` puts every bone to sleep together, so an uneven floor cannot let one marginal
bone delay persistence after the corpse has stopped. It cannot fire mid-fall: gravity moves
a falling body hundreds of units in that window. It also waits until every pivot is within
two engine units and every angular limit within 0.06 radians, so the coordination cannot
freeze an unfinished pose merely because the root stopped first. It then makes one final
pose-only joint projection after sleeping the bones; no velocity is derived from that move.
An impulse wakes the ragdoll again exactly as it wakes any 15.2 body.

A sleeping ragdoll is not solved at all — the joint pass is skipped along with the
integration. So a settled corpse costs nothing, and it keeps the pose it settled into
rather than being ground toward zero forever by a pass nothing else is moving. Measured on
the vanilla humanoid, that resting pose holds its pivots within about a unit and its limits
within two degrees.

## Death and the hand-off

Every name below came out of the M14 behavior census over the local install, never from
memory (`RagdollGraphNames`).

| Direction | Names |
| --- | --- |
| Raised when health reaches zero | `bleedOutStart`, `DeathAnim` |
| Observed as the hand-off | `AddRagdollToWorld`, `NPCAddRagdollToWorld`, `Ragdoll`, `RagdollInstant` |

The order a frame runs in:

1. `RagdollRuntime.noteZeroHealth(_:)` — the 15.3 zero-health flag becomes a death. The
   engine writes the death component and *asks* the graph to play the death. It does not
   decide the animation has finished.
2. The fixed steps advance the graph, and the graph fires whatever it fires.
3. `handleGraphEvents(_:on:)` — a drained hand-off event spawns the bodies.
   `RagdollInstant` asks for no blend; the other three blend over the controlling
   `hkbRigidBodyRagdollControlsModifier`'s `m_durationToBlend`.
4. `advance(by:)` — the live ragdolls step, and any that came to rest write their resting
   transform into their death component.

A death whose graph refuses to hand off costs one death component and no bodies, which is
visibly wrong in the right way: the actor is dead and still standing, rather than dead and
in a pose the engine invented.

**The graph-less fallback.** Item 14.6 attached a behavior graph to the player and to nobody
else, so an NPC declares none of these names. `RagdollWorldSeam.raiseRagdollEvent` reports
whether a graph took the event, and a death no graph took hands off immediately instead.
The runtime counts the two routes separately — `graphDrivenDeathCount` and
`fallbackDeathCount` — so a session can tell "the graph drove this" from "the engine had
to" rather than assume.

## Writing the pose back

The pose path already ends in `[String: float4x4]` — one skeleton-world matrix per bone
name, handed to `SkinningPalette.posed(by:)`. A simulated bone writes into exactly that
dictionary. `RenderScene.ragdollPoses`, keyed by the ACHR each corpse stands for, is laid
over the clip's own pose inside `updateAnimations(at:)`, so a ragdolled corpse reaches the
skinning palette through the call an idle animation makes and the renderer knows nothing
about physics.

Bones the ragdoll does not simulate — fingers, the skirt chain, weapon nodes — keep whatever
the animation left there, which is why a corpse still has hands. During the blend the two
poses are mixed per bone, translation lerped and rotation slerped; past it the animated side
is dropped entirely, so the corpse's steady state is exactly the simulated pose.

## Persistent death

`ActorDeathState` is its own `WorldStateComponentKind`, beside `actorValues` rather than
inside it: a current-health float is rewritten every regeneration step, while death is a
latch nothing but a resurrection clears. It travels in its own additive `DETH` save chunk,
so a build that knows nothing about the chunk skips it and loads the rest of the world
([runtime state](/engine/runtime-state.md)).

**The resting root transform is persisted; the per-bone pose is not.** Eighteen bodies is a
hundred and forty-four floats per corpse, every one of which would have to survive a save, a
load and a cell rebuild to be worth recording.

The visual consequence is stated plainly because a player can see it: **a corpse reloads
lying at the place and facing it came to rest, in the skeleton's rest pose rather than in
the exact tangle it died in.** A body that fell face-down across a stair comes back
face-down at the foot of the stair, laid out straight. Recording the full pose is a later
item's to take on if it is ever worth the save-file cost; nothing here forecloses it,
because the component would gain a field rather than change shape.

## Corpse looting

No new menu and no new session type. `ContainerSession` opens over any `InventoryHolder`,
and an ACHR's holder re-derives its baseline from the NPC_'s own CNTO list exactly as a
chest's does, so opening the container menu with no chest under the crosshair nominates the
nearest dead actor instead ([interaction](/engine/interaction.md)).

Nearest rather than the crosshair target, because ACHRs carry no `PlacedInteraction` — the
cell build makes those from CONT, DOOR, ACTI, TREE, FURN and item bases, and an actor is
none of them. Giving corpses a crosshair prompt of their own belongs with the rest of actor
interaction in item 15.7; inventing one here would put a "Search" prompt on the living too.

## The behavior modifier delta

Item 14 decoded three ragdoll modifier classes and evaluated all three as pass-through
([HKX behavior node classes](/formats/hkx-behavior-nodes.md)). This item moves one of them.

| Class | M14 | Now |
| --- | --- | --- |
| `hkbRigidBodyRagdollControlsModifier` | Pass-through, 684 evaluations | **Implemented**: publishes `m_durationToBlend` as the hand-off's blend |
| `hkbPoweredRagdollControlsModifier` | Pass-through | Still pass-through - it drives a ragdoll toward the animated pose with motors, which is a live actor's behaviour and out of this item's scope |
| `BSRagdollContactListenerModifier` | Pass-through | Still pass-through - activation needs no contact events from it |

`m_bones` is deliberately not read on the implemented one: the ragdoll this engine spawns is
every bone the skeleton NIF carries a body for, which is the same set on every vanilla
character and is resolved from the physics data rather than from the graph's index array.
`0_master.hkx` carries exactly one instance of the class, `DriveRagdollRB`, blending over
0.5 seconds; that value is the fallback a session with no evaluated graph uses.

## Sidebar and readouts

Sidebar path `World > Combat & Physics > Death & Ragdoll` (`Destination-combatPhysics`,
`PanelSection-combatRagdoll`), beside Melee and Archery. The section shipped under
`World > Player & Locomotion` and moved with the M15 gate (issue #198): the surface did
outgrow that panel, which is exactly what items 15.4, 15.5 and 15.6 each said would decide
it.

| Control | Accessibility id | What it does |
| --- | --- | --- |
| Ragdoll selected actor | `RagdollTriggerControl` | Kills and hands off the crosshair target, else the nearest resident actor |
| Clear ragdolls | `RagdollClearControl` | Drops every live ragdoll; the deaths stand |
| Freeze ragdoll stepping | `RagdollFreezeControl` | Suspends the solver with the corpses where they are |
| Readout | `CombatRagdollStatsLabel` | Live and settled counts, bone bodies over joints, solver iterations and violations, pose recoveries |

The trigger goes through the same `RagdollRuntime.trigger(_:)` a zero-health death reaches,
so a collapse requested from the sidebar is indistinguishable downstream from one a fight
caused — which is what makes the sidebar a way to verify the route rather than a second
implementation of it.

## Known limits

* **No self-collision within a ragdoll**, as above. Tracked by
  [issue #413](https://github.com/jjgroenendijk/opensky/issues/413).
* **Ragdolls do not collide with each other.** Two corpses in a pile would need the solver
  to arbitrate between two constraint sets at once, which is more than this item takes on.
* **Only the player's graph can be raised on**, so every NPC death takes the fallback route.
  Attaching graphs to NPCs is item 15.7's.
* **Non-death ragdolls** — paralysis, impact knockdown — are M18+, and dismemberment is not
  scoped at all.

## Tests

| Suite | What it pins |
| --- | --- |
| `RagdollConstraintSolverTests` | Limits hold under gravity, the solver converges, energy never grows, two runs match exactly, and a chain with the limit removed *does* fold past it |
| `RagdollStabilityTests` | Sixty collapses over four simulated minutes without NaN, divergence or growing joint separation |
| `RagdollDefinitionTests` | Bodies resolve by name, skips are reported, pivots coincide at the bind pose, the bind frame round-trips |
| `RagdollRuntimeTests` | Death raises the events, the hand-off spawns bodies, the fallback fires, settling persists, looting is recorded |
| `RagdollDeathSaveTests` | The `DETH` chunk round-trips and an older build skips it |
| `PlayerLocomotionRagdollPanelTests` | The sidebar ids and the readout |
| `RagdollRealDataTests` | The vanilla humanoid: 18 bones, 17 joints, nothing skipped, collapses onto a floor and settles with every constraint resolved |
