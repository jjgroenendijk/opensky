---
type: Subsystem
title: Effect graphs
description: How the behaviour graphs of effect art and armour addon models run as an actor's
  sub-graphs, what they read from the actor, and how to read them.
tags: [engine, animation, behavior-graph, magic]
---

# Effect graphs

Many magic and shout effects draw an art model whose mesh names a Havok behaviour graph. The mesh
names it with `BSBehaviorGraphExtraData` ([NIF extra data](/formats/nif-extra-data.md)), as a trap
mesh does ([object animation](/engine/object-animation.md)). On the install, about 1,250 meshes
carry it, many under `meshes\magic` and `meshes\effects`.

Such a graph waits for the animation events of the actor the effect is on. A hand effect waits for
`MLh_SpellFire_Event` or `MRh_SpellFire_Event`, and a shout effect for `Voice_SpellFire_Event`.
These events come from the actor's own clips and graph. The Creation Kit lists them on its
[Animation Events](https://ck.uesp.net/wiki/Animation_Events) page. So the game passes every event
of an actor on to the graphs of the effects on that actor.

The game calls these graphs the actor's sub-graphs. The Creation Kit wiki says that art objects
and armour addons can have behaviour graphs, and that both run as sub-graphs of the actor
([SetSubGraphFloatVariable](https://ck.uesp.net/wiki/SetSubGraphFloatVariable_-_Actor)). Two
natives reach them ([Actor Script](https://ck.uesp.net/wiki/Actor_Script)). Both return nothing:

- `PlaySubGraphAnimation(asEventName)` sends the event to every sub-graph of the actor.
- `SetSubGraphFloatVariable(asVariableName, afValue)` sets the variable on every sub-graph.

The SKSE64 source (commit `25b72352`) has no more about sub-graphs. Its `Actor.psc` gives the same
two natives, and SKSE adds no native for them.

## How OpenSky runs them

`EffectGraphCoordinator` runs on the main actor, after the object graphs in the world update.

- Each live visual effect that draws an art model is a candidate, and so is each armour addon
  model a loaded actor or the player wears. The coordinator reads the model's NIF off the main
  actor and loads the project it names. A model that names no graph is remembered and not read
  again.
- An effect at a point, such as an explosion or an impact, also runs its graph. Its graph stands
  at the point and hears no actor's events.
- A new effect or addon starts its own graph instance. The project's decode and clips are shared
  by every effect of the same model. An effect that ends drops its graph.
- `AnimationEventCoordinator.handle` is the one place every animation event passes
  ([animation events](/engine/animation-events.md#sources)). It first sends the event to the
  graphs of the effects on the event's source, in effect order. So the graph hears it in the
  same frame.
- A graph that does not declare the event as one of its own events ignores it.
- Before each step, a sub-graph reads its actor's placement and the actor's own graph variables.
  Each variable that both graphs declare, matched by name without case, takes the actor's value.
  So `Speed` or `Direction` in a sub-graph reads the actor's speed and direction. An actor
  without a graph gives its placement only.
- `PlaySubGraphAnimation` sends its event the same way an actor event goes.
  `SetSubGraphFloatVariable` sets the variable on each sub-graph that declares it. From then on,
  that graph keeps the script's value and no longer takes the actor's.
- An event that an effect graph fires goes back to `handle` as an event of the actor. It does
  not go back to the effect graphs, so a graph cannot hear its own event twice.

## Armour addon poses

An armour addon mesh that names a graph carries copies of the bones it is skinned to. For
example, `meshes\actors\character\character assets\maletailargonian.nif` names
`AuxBones\Tail\TailProject.hkx` and holds `NPC Pelvis` and `TailBone01` to `TailBone05`. On the
install, 112 armour addon meshes name a graph. Most are skin effects of dragons and vampire lords;
four are the Argonian and Khajiit tails.

The addon's graph moves the actor's bones of the same name. A graph bone moves an actor bone only
when the bone's name and its parent's name both match, matched without case, so the local pose
means the same in both rigs. A root bone has no parent and moves nothing. The actor's pose buffer
keeps these bones on each pose the actor's own graph publishes, until the addon graph ends. An
actor without a running graph has no pose buffer, so its addon graphs move nothing.

## Reading them

`openskycli game state effects [ref]` lists each running sub-graph: the effect id or the armour
addon (`armorAddon`), the actor (null at a point), the point, the name, the project, the active
state, the last actor event the graph took, and how many it took. With a reference, it lists
only the sub-graphs on that actor.

## Where OpenSky differs

- The graph's pose moves the effect model through its own posed copy
  ([posed effect models](/rendering/visual-effects.md#posed-effect-models)). The model's rig
  is matched to the NIF's nodes by name; a rig bone the NIF does not name moves nothing.
- A sub-graph copies the actor's variables one way, at each step. No source says whether the
  game shares one variable store between the graphs. A value a sub-graph writes does not reach
  the actor's graph.
- An armour addon's pose reaches the actor one frame late, because sub-graphs step after the
  actor graphs.
