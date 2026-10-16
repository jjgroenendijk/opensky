---
type: Subsystem
title: Animation events
description: The clip annotations that ask the engine, not the behaviour graph, to act - sounds,
  camera shake, and head tracking - where they come from, and which ones OpenSky leaves alone.
tags: [engine, animation, audio, camera, behavior-graph]
---

# Animation events

An animation clip carries annotations: a time and a text, such as `0.4 SoundPlay.NPCHumanClap`
([animation](/formats/hka-animation.md)). When playback passes the time, the text is raised as an
event. The behaviour graph reacts to many of them itself. Combat, archery, ragdolls, and footsteps
react to their own ([footstep sounds](/engine/footstep-sounds.md),
[combat graph names](/engine/combat-graph-names.md)). The events on this page ask for a sound, a
camera shake, or a head tracking change.

The text is `<event>` or `<event>.<payload>`. The event part is compared without case, because the
clips use `SoundPlay` and `soundPlay` both.

## Sources

Three runtimes raise annotations, and all three send them to `AnimationEventCoordinator`:

- the player's third-person graph, through its event queue. The first-person graph runs the same
  clips, so it is not read, or every sound would play twice;
- the NPC idles. A player idle runs on the player's graph, so the idle runtime's copy of its
  events is not sent;
- the object graphs, such as the sawmill and traps.

A graph declares only some of these names as events. The vanilla player graph declares about a
hundred `SoundPlay` names, such as the weapon draw sounds its states raise, but not the clip-only
ones such as the crossbow reload. So a graph passes on an annotation it does not declare, beside
its own events, and the coordinator reads both ([behavior clips](/engine/behavior-clips.md)).

The action happens at the source's feet: the player's capsule, an NPC's moved or placed position,
or an object's placed position. A source that is not loaded does nothing.

## Events

| Event | Payload | Action |
| --- | --- | --- |
| `SoundPlay` | `SNDR` editor ID | Plays the sound at the source |
| `SoundPlayAt` | `SNDR` editor ID, then a node name | Plays the sound at the source |
| `SoundStop`, `SoundRelease` | `SNDR` editor ID, maybe a node name | Ends that source's loop of the sound |
| `CameraShake` | Strength, such as `0.3` | Shakes the camera; a far source shakes it less |
| `HeadTrackingOn`, `HeadTrackingOff` | none | Lets the head turn, or holds it forward |

A `SoundPlay` key means the same in a NIF text key ([NIF sequences](/formats/nif-sequences.md)).
A door mesh's sequences write a sound as `Sound: <editor ID>` instead, which plays the same way
([sequence doors](/engine/object-animation.md#sequence-doors)).
A descriptor whose `LNAM` loops keeps playing until the same source stops it. A one-shot is not
tracked. A `SoundStop` for a sound that is not looping does nothing.

`HeadTrackingOff` is in one creature attack clip. It holds the head forward, so the attack points
where the body faces, until `HeadTrackingOn`.

## Where OpenSky differs

- `SoundPlayAt` plays at the source, not at the named node, because the object graphs do not
  give node positions to the audio code.
- `SoundRelease` stops the loop at once. The game lets the loop end at its next cycle; OpenSky
  has no release stage.
- `CameraShake` lasts `CameraShake.defaultDuration`. The payload gives only the strength, and no
  setting gives the length ([kill cam](/engine/kill-cam.md#camera-shake)).

## Not handled yet

These annotations need a system OpenSky does not have. `make gaps` lists them under "Animation
events" ([gap report](/tools/gaps.md)).

- `2_SoundPlay` and other `2_` events: in a paired animation, such as a kill move, they belong to
  the second actor. Playing them at the source would play the sound twice.
- `NPCSoundPlay`: the player graph declares it beside `SoundPlay` for the same kill move sounds,
  so it likely plays on the other actor of the pair. No source confirms it.
- `MLh_SpellFire_Event`, `MRh_SpellFire_Event`, `Voice_SpellFire_Event`: the cast release frame.
  The cast loop is timed by a clock, not by a casting graph ([spellcasting](/engine/spellcasting.md)).
- `AnimObjLoad`, `AnimObjDraw`, `AnimObjectUnequip`: a kill move's gore props and a key.
- The dragon flight events (`FlightLandingEffect`, `DragonTakeoffEffect`, and more) and `Func.*`:
  visual effects.
- `StartAnimationDriven`, `AttackWinStart`, `AttackWinEnd`, `bowZoomStop`, and the sync markers
  (`SyncLeft`, `SyncRight`, `SyncPoint`).
- Footstep names no `FSTP` record answers, such as `FrontFoot`, `BackFoot`, the misspelled
  `FootFornt`, and `FootBack` with a trailing carriage return. The game matches tags exactly, so
  OpenSky does not correct them.

## Controls

World > Environment > Actor animation:

- Animation events: on or off. Off leaves the graph's own events alone.
- Event and Send as player: runs any annotation text at the player, such as `CameraShake.0.5`.
- The readout counts each action kind, and shows the last event and how many sound editor IDs
  no `SNDR` has.
