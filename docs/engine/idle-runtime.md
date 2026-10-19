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

An `IDLE` names a behavior file (`DNAM`), or takes its nearest ancestor's
([IDLE](/formats/idle.md#idle)), and an animation event (`ENAM`). An NPC that runs its own
graph ([actor graphs](/engine/actor-graphs.md)) gets the event, and the graph plays the idle.
For an actor without a running graph, such as one past the graph distance, OpenSky resolves
the clip statically:

1. Open the behavior file and its project folder, for example
   `meshes\actors\character\behaviors\0_master.hkx`.
2. Find the transition that the event fires. When the transition target is a nested state
   (transition flag 0x2000), use the first state machine below that state. A wrapper
   generator can sit between the state and the state machine.
3. Take the first clip generator below the target state. A state machine on the way enters
   its start state (`m_startStateId`), as a live graph does. The clip path is relative to the
   project folder (`meshes\actors\character\`). Paired idles use `..\` in the path, which
   is resolved before the lookup.
4. When that clip plays once, and one of its clip triggers fires a transition of its own state,
   the clip of the next state follows. The chain stops at a clip that loops, or after four clips.

OpenSky remembers the state where the chain ended for each actor. The actor's next idle event
is looked up there first: a transition of that state, then a wildcard of its machine. Only when
neither takes the event does the lookup start again from the root. This matters because one event
can lead to different clips: `IdleExecutionerChop` takes the executioner, the guard, and the
prisoner each to their own chop clip in `mt_behavior.hkx`. The state is forgotten when the idle
ends.

When the event is not in the graph, OpenSky tries a clip named after the event. It tries two
names, relative to the project folder:

1. `Animations\<event>.hkx`. For example, `IdlePray` plays `Animations\IdlePray.hkx`.
2. `Animations\male\MT_<stem>.hkx`, where the stem is the event without a trailing `Trans`.
   `idlebehavior.hkx` has a state and a clip of that name for each such event. For example,
   `idle_A_sway_fastTrans` of the drunk marker plays `Animations\male\MT_idle_A_sway_fast.hkx`.

[WARNING] The second rule is a naming pattern observed on the install, not a confirmed engine
rule. `0_master.hkx` lists these events, but no state machine transition in `0_master.hkx`,
`idlebehavior.hkx`, or `mt_behavior.hkx` fires on them. How the game routes them is unknown.

The sidebar reports which path served the idle: "graph event", "clip named after the event",
or "nothing" with the reason.

On the install, 1,034 idles name `0_Master.hkx`. 795 resolve to a clip through the graph, and
213 have no event because they only group other idles. 10 play through the second name rule.
15 still name an event that neither the walk nor a name finds, such as `idle_A_pull_pants`,
`TG05_KnockOut`, and the kill moves, so they do not play.

The loop count comes from the idle's `DATA`: a random count between the loop minimum and
maximum. A zero maximum plays the clip once, unless the clip loops.

A clip generator's `m_mode` says how its clip plays: 0 once, 1 in a loop, 3 back and forth
(`hkbClipGenerator` playback modes). A state whose clip loops does not end on its own in the game; it
holds until an event leaves it. So an idle whose clip loops and whose `DATA` gives no loop count
holds until another idle replaces it. The cart seat idles work this way: every seat and sway state
of the `Cart` machine in `0_master.hkx` loops, and every exit state plays once (read on the install).
A held idle sends its clip's annotations on every loop. When another idle replaces it, its state's
exit events fire. At a marker, the next pick comes after the marker timer, or one second.

A clip's annotations become animation events. Each annotation is a time and a name, such as
`CartExit`, and it fires once per loop at that time. An annotation past the end of the last loop
does not fire. A script that called `RegisterForAnimationEvent` on the actor gets
`OnAnimationEvent` with the name.

A clip generator's triggers (`hkbClipTriggerArray`) become animation events too, at their time in
the clip. A time marked "relative to end of clip" counts back from the end. A trigger that copies
an annotation (`m_isAnnotation`) is skipped, because the annotation already fires. Example from the
install: `AOExecutioneeChop.hkx` is 20 s long and raises `Decapitate` 8.161 s and `KillActor`
3.394 s before its end.

[WARNING] `KillActor` kills the actor that plays the clip, at once. No source documents the event;
this is OpenSky's reading of its name and of where the clips raise it.

The state the idle's event leads to can also send events: its enter notify events fire when the
idle starts, and its exit notify events when it ends. The cart exit states send `ExitCartEnd`
this way; no clip annotation carries it.

The player can play an idle too, such as the cart seat and the cart exit in `MQ101`. OpenSky
raises the idle's event on the player's own behavior graph, which poses the body. It also loads the
clip, against the character skeleton, to time the idle's events.

## Furniture

When a package seats an actor on a furniture marker, the actor picks an entry idle from the tree
under the `ActionActivate` action (`AACT`). The tree's conditions read the seat through these
functions ([Condition functions](/engine/condition-functions.md#furniture)):

- `GetSitting` is 2 (getting ready to sit) while the idle is picked, 1 while an NPC's sit idle
  still loads, and 3 once it plays. When the actor gets up it reads 4 for one second, then 0.
- `IsFurnitureAnimType` is the marker's animation type: 1 sit, 2 lay, 4 lean.
- `IsFurnitureEntryType` is the one entry the actor uses. It is the allowed side of the marker
  that faces the actor most; "up" counts only when no side is allowed.
- The furniture reference is the Target. The executioner tree runs
  `HasKeyword FurnitureExecutioner` on the Target, and only the block has that keyword.
- The tree mixes idles of other graphs, such as the lever's `PlayerLeverActivate`. An idle
  plays only on the graph whose project folder holds its file. The actor's project is the folder
  above its skeleton's assets folder, so `character assets female\` is a human too.

Example: on the chopping block, the prisoner's chain is `ActivateRootChar` > `Chair` >
`ExecutioneeRoot` > `IdleExecutioneeIdle`. Its event enters the executionee machine, which plays
`AOExecutioneeEnter.hkx` and then holds `AOExecutioneeIdle.hkx`. The idle stops when the package
lets the actor stand up.

[WARNING] The entry side rule is OpenSky's reading. The game's choice of entry is not documented.

## Dependents

`AddDependentAnimatedObjectReference` makes one actor a dependent of another. A dependent takes
every idle its owner is told to play, from the state its own graph is in. The chopping block
script adds the executioner and the guard to the prisoner, then plays the chop idle on the
prisoner alone, and the three machines each have a transition on that event. Bethesda documents
no rule; this is OpenSky's reading of the script and the graph.

## Prop

A prop is a held object, such as a broom or a tankard. It is an `ANIO` record.

- The behavior graph sends an `AnimObjDraw` event with a string payload while the idle
  plays. The payload is the editor ID of the `ANIO`. OpenSky collects the payloads of the
  `HKBStringEventPayload` objects below the target state.
- The `ANIO` mesh holds a `NiStringExtraData` named `Prn`. Its value is the bone the prop
  rides on, such as `AnimObjectR` or `NPC R Hand [RHnd]`
  ([NIF](/formats/nif.md#nistringextradata)). A value without the bone's tag, such as
  `NPC R Hand`, takes the skeleton bone whose name starts with it.
- A clip can name an `ANIO` in its own annotations instead, as `AnimObjDraw.<editor ID>`. The
  object shows when the annotation passes, and leaves at its unload event
  ([animation objects](/engine/animation-events.md#animation-objects)).

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
  clip. A transition that waits for a condition or a variable is taken at once.
- The actor does not turn to the marker's facing.
- Props and idles are not saved. A loaded game starts with no idle playing.
