---
type: Engine
title: Idle runtime
description: How OpenSky sends actors to idle markers, picks an idle from the IDLE tree,
  plays its clip, and shows its prop, and where this differs from the game.
tags: [engine, animation, ai]
---

# Idle runtime

An idle is a short animation an actor plays while it waits: leaning on a wall, praying,
sweeping. Each idle is an `IDLE` record. An idle marker (`IDLM`) is a placed object that
lists the idles an actor may play there. The record layouts are in
[Idle records](/formats/idle.md).

The runtime has four parts:

1. Marker claim: which actor goes to which marker.
2. Selection: which idle of the marker plays.
3. Playback: which clip that idle plays.
4. Prop: which object the actor holds while it plays.

## Marker claim

An actor looks for a marker when its current package is a sandbox package, or a package
whose procedure name contains `IdleMarker`. A dead actor does not look.

- The actor takes the nearest marker within 1024 units (about 15 m) that no other actor
  holds. A tie goes to the lower reference.
- The actor walks to the marker through the normal move command. A marker it cannot reach
  is skipped for that actor, so it does not retry every frame.
- The actor has arrived when it stands within 48 units of the marker.
- The actor lets go of the marker when it dies, leaves the loaded cells, or changes to a
  package that does not use markers. A playing idle finishes first.

World > AI & Navigation > Idles lists the markers of the loaded cells. Its checkbox "Send
sandboxing actors to markers" turns the claim off for every actor. "Play idle" plays a
chosen idle on the selected actor, and "Pick at marker" runs the marker's own choice.

## Selection

The marker's `IDLA` list is the list of candidates.

- Flag 0x01 (run in sequence) tries the entries in order, starting after the last one that
  played, and plays the first that passes. Without it, every entry is tested and one of
  the passing entries is picked at random.
- Flag 0x04 (do once) skips an idle this actor already played at this marker.
- A candidate plays only when its conditions pass for the actor. A candidate with children
  in the `IDLE` tree hands over to its first passing child, in sibling order. It plays
  itself only when no child passes.
- A candidate without an animation event (`ENAM`) never plays itself.

Every candidate gets a verdict in the trace: chosen, passed, failed (with the name of the
first failing condition function), not reached, already played, or no animation. The
sidebar shows the trace of the last pick.

The next pick happens after the longer of the clip time and the marker timer (`IDLT`),
and at least one second later.

## Playback

An `IDLE` names a behavior file (`DNAM`) and an animation event (`ENAM`). OpenSky does not
run a behavior graph for NPCs, so it resolves the clip statically:

1. Open the behavior file and its project folder, for example
   `meshes\actors\character\behaviors\0_master.hkx`.
2. Find the transition that the event fires. When the transition target is a nested state
   (transition flag 0x2000), use the first state machine below that state. A wrapper
   generator can sit between the state and the state machine.
3. Take the first clip generator below the target state. Its clip path is relative to the
   project folder (`meshes\actors\character\`). Paired idles use `..\` in the path, which
   is resolved before the lookup.

When the event is not in the graph, OpenSky tries a clip named after the event. The
sidebar reports which path served the idle: "graph event", "clip named after the event",
or "nothing" with the reason.

On the install, 1,034 idles name `0_Master.hkx`. 795 resolve to a clip this way, and 213 have
no event because they only group other idles. 25 name an event that the walk does not find,
such as `idle_A_sway_fastTrans` of the drunk marker, so they do not play.
For example, `IdlePray` plays `Animations\IdlePray.hkx`.

The loop count comes from the idle's `DATA`: a random count between the loop minimum and
maximum. A zero maximum plays the clip once.

## Prop

A prop is a held object, such as a broom or a tankard. It is an `ANIO` record.

- The behavior graph sends an `AnimObjDraw` event with a string payload while the idle
  plays. The payload is the editor ID of the `ANIO`. OpenSky collects the payloads of the
  `HKBStringEventPayload` objects below the target state.
- The `ANIO` mesh holds a `NiStringExtraData` named `Prn`. Its value is the bone the prop
  rides on, such as `AnimObjectR` or `NPC R Hand [RHnd]`
  ([NIF](/formats/nif.md#nistringextradata)). A value without the bone's tag, such as
  `NPC R Hand`, takes the skeleton bone whose name starts with it.

On the install, 48 idles of `0_Master.hkx` show a prop. The lute does not: its prop event is
outside its target state, so OpenSky shows no lute.

A prop is not part of the cell build. The model loads once on the build queue, because the mesh
library may only run there, and stays cached. The streamer then draws it beside the cell scene,
at the actor's build position, posed by the actor's own animation. So starting or ending an idle
changes only that actor's draw list and rebuilds no cell. When the actor's cell is rebuilt for
another reason, the actor gets a new animation object, and the next drawn scene binds the prop to
it.

## Differences from the game

- No behavior graph runs for NPCs. The clip and the prop are found statically through the
  graph, so a graph that picks a clip at random or by a variable always plays the first
  clip.
- The actor does not turn to the marker's facing.
- Props and idles are not saved. A loaded game starts with no idle playing.
