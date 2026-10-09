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

`ForceStart()` acts like `Start()`. In the game it also stops other scenes that use the same
actors. OpenSky does not track which actor is in which scene yet.

Starting runs the begin fragment, then enters phase 1.

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

A save stores the playing scenes in the `SCNS` chunk
([world chunks](/formats/opensky-save-world-chunks.md)). After a load, a scene goes on from the
same phase with the same running actions.

## Observed on the install

`Skyrim.esm` has 1,706 scenes the catalog can name. Of the scenes whose actors are all
forced-reference aliases and whose actions are dialogue or timers, 26 were played with no
loaded cell. `DialogueWinterholdInnInitialScene` plays four phases, one line each, between
its two speakers and ends.

## Not done yet

- Scenes play no idles and turn no heads (`HTID`).
- A scene line is timed by its voice file, but the voice is not played.
- `ForceStart()` does not stop other scenes.
- Actor behavior flags (`VNAM`, actor `DNAM`), such as "interrupt on combat", are decoded
  but not used.
