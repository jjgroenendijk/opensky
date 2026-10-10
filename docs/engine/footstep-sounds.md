---
type: Subsystem
title: Footstep sounds
description: How the player's footsteps are played from the behavior graph's own foot events,
  which footstep set and ground material choose the sound, and the panel that plays one standing
  still.
tags: [engine, audio, footsteps, behavior-graph, walk-mode]
---

# Footstep sounds

The player's footsteps have no step timer. The vanilla movement clips carry their own footstep
marks: annotations in the animation files, raised as events by the behavior graph. `0_master.hkx`
declares `FootLeft` and `FootRight` as the first two of its 1,217 events. So the graph already says
when a foot lands, at the moment the animation plants it. A rhythm computed from speed would drift
away from the animation the player sees ([behavior runtime](/engine/behavior-runtime.md)).

The records and the chain from tag to sound file are on the [footstep records](/formats/footstep.md)
page. How a surface names its material is on the [material types](/formats/material-type.md) page.

## The route

Once per frame:

1. As each fixed step runs, the fired events of the third-person graph are queued. Only that graph
   feeds the queue. Both graphs run the same clips and fire the same events, so reading both would
   play every step twice.
2. The audio update reads the queue and passes the names to the footstep player, with the current
   gait and the capsule's feet position. The queue is read even outside walk mode and with no
   player attached, so an unread queue cannot flush all at once when audio is turned on. The whole
   update is skipped while the world is paused, and a paused frame fires nothing, so the two agree.
3. Each name is offered to the current gait's footstep list, and whatever resolves plays. The graph
   fires many other names, from combat and magic. Those cost one string compare and are dropped.

## Which sound

The ground material under the capsule is passed along too. The impact table is keyed by it, so
snow, wood, grass, and gravel choose different `IPCT` records and different sounds
([walk mode](/engine/walk-mode.md)).

The footstep set comes from `ARMA` `SNDD` on the armature in the feet slot of the built body. With
none, it is `DefaultFootstepSet`. Worn parts come before skin parts in a resolved appearance, so
boots win over the bare foot they cover with no extra ranking.

Footsteps are positional, placed at the feet, not at the listener. That is what makes third person
sound right.

A routed step also shows the `IPCT` impact model at the feet, such as dust
([impacts and decals](/rendering/decals.md)).

## Controls

World > Audio > Footsteps:

- Enabled.
- Tag: the tags the current footstep set answers to, for the gait the player is in. The list is
  rebuilt on every refresh, because the gait changes as the player moves. A choice that is still in
  the new list is kept.
- Material: "Ground contact" (the default, the surface under the walk controller), or any `MATT`.
  Choosing a `MATT` pins it, and the readout adds `(forced)`. Both graph events and the play button
  use it. This is how to hear snow while standing on stone. A pinned material counts as a change, so
  reset clears it.
- Play footstep: plays one step at the player's feet without walking, so the whole chain can be
  checked standing still.
- Readout: the set, the material, the tags, how many events were routed and played, and the last
  sound file. Routed and played differ by the tags the set has no sound for, which is normal
  vanilla data.
