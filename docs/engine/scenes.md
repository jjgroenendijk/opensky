---
type: Subsystem
title: Scene runtime
description: How scenes start, move through phases, run actions, speak lines, end, and save.
tags: [engine, dialogue, quests, papyrus, runtime-state]
---

# Scene runtime

A scene is a short script a quest owns: phases run in order, and each phase starts actions
such as a line of dialogue or a wait. The record layout is on the
[scene records](/formats/scenes.md) page. Lines are chosen by the
[dialogue runtime](/engine/dialogue.md), so a scene line follows the same selection rules as
a line in the dialogue menu.

Source for the rules: the Creation Kit wiki, <https://ck.uesp.net/wiki/Category:Scenes>,
"Scene", "Phases", and "Actions". Where the wiki is silent, OpenSky's choice is marked below.

## Starting

A scene starts when its quest starts and the scene has flag 0x01 (begin on quest start), when
a script calls `Scene.Start()` or `Scene.ForceStart()`, or from the Scenes control in the
sidebar. A scene starts only while its quest runs. A scene that already plays is left as it is.

Starting runs the begin fragment, then enters phase 1.

## Actors in two scenes

An actor plays in one scene at a time. A scene holds its actors from the moment it enters a
phase until it ends. A second scene that needs a held actor waits before its first phase:

- If the scene that holds the actor has flag 0x04 (interruptible), it is stopped, and the new
  scene takes the actor.
- Otherwise the new scene waits. It tries again on every tick.
- An optional actor (actor `LNAM` flag 0x02) never makes a scene wait. Its actions are done at
  once while another scene holds it, like an empty alias.

`ForceStart()` stops every playing scene that shares an actor with the new scene, then starts
it. Source: the Creation Kit pages "ForceStart - Scene" and "Scene".

## Actor behaviour flags

Each scene actor has a behaviour `DNAM`. The bits, from xEdit's `wbDefinitionsTES5.pas`:

| Bit | Meaning |
| --- | --- |
| 0x02 | Death ends the scene |
| 0x04 | Combat pauses the scene |
| 0x08 | Combat ends the scene |
| 0x10 | Dialogue with the player pauses the scene |
| 0x20 | Dialogue with the player ends the scene |
| 0x40 | Observing combat pauses the scene |
| 0x80 | Observing combat ends the scene |

Bit 0x01 (death pauses) is unused in the game. The record's `VNAM` holds only the editor's
"set all" choice, so OpenSky reads the actor `DNAM` alone.

On every tick, each actor of a playing scene is checked. An end flag that matches ends the
scene. A pause flag that matches pauses it: no phase moves and no action finishes. When no
pause flag matches any more, the scene resumes, and every running action's start time moves
forward by the length of the pause. So a timer or a line keeps the time it had left.

A dead actor's dialogue or package action is done at once. The game also lets a scene go on
past a dead actor.

OpenSky does not know yet when an actor observes combat, so bits 0x40 and 0x80 never match.

## Phases

The runtime keeps the current phase, whether it was entered, the running actions, and the
completed actions:

1. A phase is entered when its start conditions pass. Otherwise it is skipped and the next one
   is tried.
2. Entering runs the phase's begin fragments, then starts each action whose start phase is
   this phase.
3. A phase is done when every action whose end phase is this phase has finished, or when its
   completion conditions pass. An action with no end phase ends in its start phase. A phase
   with completion conditions and no actions to wait for waits for the conditions. For
   example, phase 2 of `MQ101`'s first scene waits for stage 12.
4. Finishing completes the actions that should end by now, runs the phase's end fragments, and
   moves to the next phase.
5. After the last phase, a scene with flag 0x08 (repeat while true) starts again from phase 1
   when its scene conditions pass. Otherwise it ends.

Conditions are checked with the player as subject, no target, and the scene's quest as the
alias quest. Several phases can pass in one tick. A tick takes at most twice as many steps as
the scene has phases, plus four, and repeats a scene at most once, so it cannot loop forever.

## Actions

| Type | What OpenSky does |
| --- | --- |
| 0, dialogue | The action's alias names the speaker. The topic's responses are selected for that speaker, the winner is marked said, and its result script runs. The action lasts as long as the line. |
| 1, package | The actor in the action's alias runs the action's packages ahead of its own schedule. The action is done when the package reaches its Done state. |
| 2, timer | Lasts the `SNAM` duration in seconds. |

An action whose alias is empty is done at once. The Creation Kit says a scene goes on when an
actor is dead or disabled, and an empty alias is the same case for OpenSky. A dialogue action
whose topic has no passing response for the speaker is also done at once.

### Package actions

The Creation Kit says a scene's package overrides every other package of the actor. While a
package action runs, the [package selector](/engine/package-schedules.md#scene-packages) picks
from the action's packages instead of the actor's own list. When the action ends, the actor
goes back to its own list. The runtime asks for the packages again on every tick, so a scene
that a save restored gives them back.

The Creation Kit says: "Package actions are completed when the package reaches the Done
state. Actions with packages that have no Done state can never be completed." So a travel
package is done when the actor arrives. Sandbox, wander, sleep, and eat never end; their
phase needs completion conditions. A procedure that OpenSky cannot run yet counts as done at
once. This is OpenSky's choice, so that a scene with such a package does not wait forever.

[WARNING] A done package action keeps its actor until its end phase ends, or until the scene
ends. The Creation Kit does not say this; it is OpenSky's reading. Without it, an actor who sits
down in an early phase stands up and walks back to its schedule before the scene moves on. In
`MQ101Scene4`, the first prisoner kneels at the block in one phase, and the action holds them
for two more.

### Line length

A line lasts as long as its voice file, as in the game. The file is
`sound\voice\<plugin>\<voice type>\<name>.fuz` ([voice files](/formats/fuz.md)). Its length
is the playing time in the xWMA packet table. The voice type is the speaker's `VTCK`. The
file is read off the main actor, and the line's clock starts when the length is known. So the
next line starts in the tick this one ends: no gap and no overlap.

A response with no voice file lasts the time of its text: one second per 15 characters, at
least 1.5 seconds. A line with no text lasts 3 seconds. This is OpenSky's estimate. A save
loaded while a line waits for its voice file ends that line at once.

## Time

Scene time is game seconds divided by the time scale, so it runs at real speed while the game
clock runs. It stops when the game clock stops, for example in a menu.

## Ending

A scene ends after its last phase, when a script or the sidebar stops it, or when its quest
stops. Each way runs the end fragment. A scene with flag 0x02 (stop quest on end) stops its
quest, but only when it finished on its own.

## Fragments

Scene fragments are in the `VMAD` tail of the `SCEN` ([VMAD](/formats/vmad.md)). Slot 0x01 is
the begin fragment and 0x02 the end fragment. A phase fragment has flag 0x01 for phase begin
and 0x02 for phase end. A fragment with no script runtime to run it is noted as not run in the
trace, not dropped.

## State and saving

A playing scene has a world-state component, `scene`, keyed by the `SCEN`. A scene that is not
playing has no component, so the baseline is "not playing" and costs nothing. Playback writes
the component only when the state changed, because any write to a base record rebuilds the
loaded cells.

A save stores the playing scenes in the `SCNS` chunk, and the pause time of each paused scene
in the `SCNP` chunk ([world chunks](/formats/opensky-save-world-chunks.md)). After a load, a
scene goes on from the same phase with the same running actions, still paused if it was.

## Observed on the install

`Skyrim.esm` has 1,706 scenes the catalog can name. Of the scenes whose actors are all
forced-reference aliases and whose actions are dialogue or timers, 26 were played with no
loaded cell. `DialogueWinterholdInnInitialScene` plays four phases, one line each, between
its two speakers and ends.

## Not done yet

- Scenes play no idles. A line turns the speaker's head toward its `HTID` alias
  ([head tracking](/engine/head-tracking.md)).
- Observing combat is not known, so the observe-combat behaviour flags never act.
