---
type: Subsystem
title: Animation events
description: The clip annotations that ask the engine, not the behaviour graph, to act - sounds,
  camera shake, head tracking, and animation objects - which ones the graph handles itself, and
  which ones OpenSky leaves alone.
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

The Creation Kit wiki lists the events the game raises for a humanoid, in the order they fire for a
bow shot, a sword swing, a spell, and a sneak
(<https://ck.uesp.net/wiki/Animation_Events>). It confirms `SoundPlay`, `SoundStop`,
`HeadTrackingOff` and `HeadTrackingOn` around an attack, and `MRh_SpellFire_Event` as the release of
a fire-and-forget spell. The payload shapes below come from the install's clips.

## Sources

Five runtimes raise annotations, and all five send them to `AnimationEventCoordinator`:

- the player's third-person graph, through its event queue. The first-person graph runs the same
  clips, so it is not read, or every sound would play twice;
- the NPC idles. A player idle runs on the player's graph, so the idle runtime's copy of its
  events is not sent;
- the object graphs, such as the sawmill and traps;
- each NPC's and creature's own graph ([actor graphs](/engine/actor-graphs.md)). Its idle events
  are not sent again by the idle runtime;
- the graphs of the effects on an actor ([effect graphs](/engine/effect-graphs.md)). Their
  events count as the actor's.

The coordinator first passes every event on to the graphs of the effects on its source, so a
hand effect hears its caster's release event.

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

## Animation objects

An animation object is an `ANIO` record: a model an animation holds for a while, such as the
skeleton key the player shows in the Thieves Guild
(<https://ck.uesp.net/wiki/AnimObject>). A clip names one in its annotations:

| Event | Payload | Action |
| --- | --- | --- |
| `AnimObjLoad` | `ANIO` editor ID | Nothing. OpenSky loads the model at the draw |
| `AnimObjDraw` | `ANIO` editor ID | Shows the object on the actor that plays the clip |
| The object's `BNAM` event | none | Takes the object off again, such as `AnimObjectUnequip` |

The idle runtime runs these, because it holds the clip and the actor's skeleton. When an idle plan
loads, it reads the annotations of its clips and resolves each named `ANIO` to a model and a bone,
the same way as the prop the graph names ([idle runtime](/engine/idle-runtime.md#prop)).

An actor shows one prop, so a drawn object replaces the graph's prop. The player has no playback
of its own, so a player idle shows no object.

The execution clips at the chopping block name `DecapitationHeadGore` and `DecapitationNeckGore`.
No record in the vanilla load order has those editor IDs, so nothing is drawn.

## Events the graph handles

A behaviour graph raises an annotation that it declares as one of its own events
([behavior clips](/engine/behavior-clips.md)). A transition, an event-driven modifier, or another
node can wait for it, and the graph acts without the engine. Examples on the install:

- `weaponDraw` and `weaponSheathe` in the equip clips switch modifiers in `0_master.hkx`.
- `AttackWinStart` and `AttackWinStartLeft` take transitions in `1hm_behavior.hkx`.
- `FlapThrustBegin` and `FlapThrustEnd` switch a modifier in the dragon graph.

`make gaps` counts such an event as done when a graph of the clip's own folder waits for it
([gap report](/tools/gaps.md)). A graph of another folder does not count. A door graph waits for
`Open`, but a dragon clip that carries `Open` is not played by a door.

## Function events

`Func.<name>` sends `<name>` to the source's scripts as an animation event, the same way
`OnAnimationEvent` receives a graph event (<https://ck.uesp.net/wiki/OnAnimationEvent_-_Form>).
The install shows it:

- The dragon graphs declare the bare `DragonBiteEffect`, and the giant and lurker graphs declare
  `GiantStompEffect`. Their clips carry `Func.DragonBiteEffect` and `Func.GiantStompEffect`.
- Scripts call `RegisterForAnimationEvent` with `dragonbiteeffect` and `giantstompeffect`.

So the prefix only routes the event to the scripts. A script registered for the name runs its
`OnAnimationEvent`; with no registration, nothing happens.

`make gaps` also counts an event as done when a script registers for it, because the
script VM delivers it ([gap report](/tools/gaps.md)).

## Footsteps no record answers

Some creature clips carry footstep names that no `FSTP` tag matches: `FrontFoot` and `BackFoot`
on the riekling boar, the misspelled `FootFornt`, `FottFront`, `FrootBack` and `FoorRight`, and
`FootBack` and `FootRight` with a line break after the name. The footstep lookup compares whole
tags, so these play nothing. OpenSky does not correct them, because no source says the game does.

## Head tracking

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

- Paired animations, such as kill moves and the vampire lord feed. `2_SoundPlay` belongs to the
  second actor of the pair, and playing it at the source would play the sound twice.
  `NPCSoundPlay` likely plays on the other actor too; no source confirms it. `PlayAnim01` in the
  werewolf mauling clip is in the same group.
- The cast and shout release frame: `MLh_SpellFire_Event`, `MRh_SpellFire_Event`,
  `Voice_SpellFire_Event`, and `Spellfire` on the staff release clips. The cast is timed by a
  clock ([spellcasting](/engine/spellcasting.md)). The magic and shout effect graphs, such as
  `dragonmouthfire.hkx`, hear these events ([effect graphs](/engine/effect-graphs.md)), but the
  release itself does not wait for them.
- Dragon flight and its effects: `FlightLandingEffect`, `DragonTakeoffEffect`,
  `DragonLandEffect`, the crash landing events, `DiveSplashStart`, and the wing and tail attack
  effects.
- `StartAnimationDriven`: about 29 creature graphs declare it and none waits for it, so the engine
  reads it. It likely moves the actor by the clip's root motion; no source confirms it.
- The sync markers `SyncLeft`, `SyncRight`, `SyncPoint`, `SyncRun`, `SyncB_Right`, and
  `SyncF_Left` on creature run and walk clips. Many graphs declare them and none waits for them.
  OpenSky keeps blended clips in phase by their length instead
  ([behavior clips](/engine/behavior-clips.md)).
- Creature sound cues with no `SoundPlay` prefix, such as `NPCScribAttack1`, `BenthicAOE` and
  `NPCGiantFootDistantR`, and the storm atronach's `L1_Start` and `R1_Start` marks. Their graph
  declares them and nothing waits for them. No source says what the game does with them.
