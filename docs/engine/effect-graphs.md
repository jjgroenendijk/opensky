---
type: Subsystem
title: Effect graphs
description: How the behaviour graph of an effect's art model hears the animation events of the
  actor it is on, and how to read the running effect graphs.
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

## How OpenSky runs them

`EffectGraphCoordinator` runs on the main actor, after the object graphs in the world update.

- Each live visual effect that is anchored to an actor and draws an art model is a candidate.
  The coordinator reads the model's NIF off the main actor and loads the project it names. A
  model that names no graph is remembered and not read again.
- A new effect starts its own graph instance. The project's decode and clips are shared by every
  effect of the same model. An effect that ends drops its graph.
- `AnimationEventCoordinator.handle` is the one place every animation event passes
  ([animation events](/engine/animation-events.md#sources)). It first sends the event to the
  graphs of the effects on the event's source, in effect order. So the graph hears it in the
  same frame.
- A graph that does not declare the event as one of its own events ignores it.
- An event that an effect graph fires goes back to `handle` as an event of the actor. It does
  not go back to the effect graphs, so a graph cannot hear its own event twice.

## Reading them

`openskycli game state effects [ref]` lists each running effect graph: the effect, the actor,
the effect's name, the project, the active state, the last actor event the graph took, and how
many it took. With a reference, it lists only the effects on that actor.

## Where OpenSky differs

- The graph's pose moves the effect model through its own posed copy
  ([posed effect models](/rendering/visual-effects.md#posed-effect-models)). The model's rig
  is matched to the NIF's nodes by name; a rig bone the NIF does not name moves nothing.
- The graph gets no character context, so a modifier that reads the actor's position or speed
  reads zero.
