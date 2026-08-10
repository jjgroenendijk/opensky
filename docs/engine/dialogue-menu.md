---
type: Subsystem
title: Dialogue menu
description: Talk activation on an actor, the vanilla dialoguemenu.swf topic list, the
  per-menu world-pause policy that lets the world keep running during a conversation, and
  gameplay subtitles on the HUD.
tags: [engine, ui, dialogue, menu, interaction, swf]
timestamp: 2026-08-10T00:00:00Z
---

# Dialogue menu

Roadmap item 17.3 (issue #205). The player-facing entry to dialogue: pressing the use key
on an NPC, the vanilla `interface\dialoguemenu.swf` listing that speaker's topics, the
response text and its subtitle, and the input and pause policy around all of it.

What is *offered* is [dialogue selection](/engine/dialogue.md) (item 17.2), which this
sits on top of and does not duplicate. The camera and speaker facing are item 17.4, voice
playback and line timing item 17.5, and lip movement items 17.6 and 17.7. None of those
exist yet, and the seams this leaves for them are named below rather than stubbed.

## Contents

- Talk activation
- Menu-mode pause policy
- The measured movie contract
- What the model owns
- Text resolution
- Subtitles
- Input
- What is deferred, and to where
- Verification surface
- Acceptance record

## Talk activation

An actor under the crosshair becomes an ordinary crosshair target with a new
`InteractionAction.talk`, so the HUD prompt, the compass marker and the
`World > HUD & Interaction > Target` readout all reach it through the path they already
had. Pressing the use key publishes `TalkActivationEvent`, which carries the speaker's
session-stable `ReferenceKey` — the identity selection, said-state and a save all address a
response by, and the one thing an ordinary `InteractionEvent` cannot carry.

### Why the pick is not the interaction raycast

[Interaction](/engine/interaction.md)'s `InteractionRaycaster` answers against
`StaticCollisionShape`, the immutable per-cell NIF collision the streaming BVH indexes.
Actors are not in it and should not be: an ACHR is built on a separate path
(`CellSceneBuilderActors`) that produces no placed collision and no `PlacedInteraction`, and
it moves every frame, which is the opposite of what an immutable per-cell structure is for.
Putting actor bodies in there would mean rebuilding the BVH whenever anybody took a step.

`opensky/Engine/World/TalkTargeting.swift` instead reuses the narrowphase
[melee combat](/engine/melee-combat.md) already resolves a swing against actors with:
`MeleeHitDetector.closestApproach`, the exact segment-to-segment distance. A view ray is a
segment and an actor is a capsule, so the answer is one call. The M16
[detection](/engine/detection.md) line of sight was the other candidate and was not taken —
it answers "can this observer see that actor", a question about one named pair, whereas
targeting has to rank every resident actor against one ray.

### Occlusion and filtering

`TalkTargeting` tests no walls. `CellStreamer.updateInteractionTarget(ray:)` owns that,
because it is the one holding both answers: the talk hit counts only when it is nearer than
the nearest *solid* hit along the same ray, whether or not that solid hit activates
anything. A shopkeeper behind a shut door is behind a solid hit that opens rather than
talks.

Who is a candidate at all is the app's question, answered in
`GameViewControllerDialogue.talkCandidates()` through `CellStreamer.talk.candidateSource`,
and filtered on exactly two facts:

| Filter | Source | Why |
| --- | --- | --- |
| Alive | `ActorDeathState` | The same latch combat targeting reads, so the two cannot disagree |
| Not hostile | `ActorCombatState.hostility` | What a fighting actor says is DIAL's combat category, and selection offers only category 0 |

Deliberately *not* filtered on having anything to say. A speaker whose topics all fail their
conditions still opens a menu with an empty list, because "this actor had nothing to say" is
a result the condition trace can explain, while a prompt that silently never appeared is
not.

Talk distance is `InteractionRay.defaultMaximumDistance`, the interaction reach, stated once
in `TalkTargetPicker.defaultMaximumDistance`. Nothing measured out of the install gives a
separate number, and inventing one would mean an actor the crosshair reports as a target
that the use key then refuses.

## Menu-mode pause policy

[Menu mode](/engine/menu-mode.md) used to equate menu mode with a paused world. Vanilla
dialogue does not: the world keeps running while the player reads the list, which is what
lets a speaker keep breathing, walking and being heard, and what items 17.4 through 17.7
have to advance on.

`MenuModeController.present(_:policy:)` therefore takes a `MenuWorldPolicy` —
`pausesWorld`, the default every existing menu keeps, or `leavesWorldRunning`, which
`"Dialogue Menu"` alone uses. `isWorldSimPaused` is true while *any* open menu declares
`pausesWorld`, so the system menu opened over a conversation still stops the world and
closing it hands the running world back.

The consequence for callers is that the input route and the pause gate no longer move
together, so `onModeChange` reports both:

```swift
menuMode.onModeChange = { route, paused in
    renderer.worldSimPaused = paused
    if route == .menu { cameraInput.releaseAll() }
}
```

Held world input is released on the *route* flip rather than on the pause, because a key
held into a non-pausing menu would otherwise keep driving a camera nobody is steering.

## The measured movie contract

Measured with `openskycli swf dialogue-menu` and `openskycli swf action-run --movie
dialoguemenu.swf`; nothing below is from memory of the shipped game. The movie starts and
ticks with **zero faults and zero unimplemented opcodes** over 57 display nodes.

| Path | What it is |
| --- | --- |
| `/DialogueMenu_mc` | the menu, class `DialogueMenuObj` |
| `/DialogueMenu_mc/SpeakerName` | who is talking |
| `/DialogueMenu_mc/SubtitleText` | the line being said |
| `/DialogueMenu_mc/TopicListHolder` | frame labels `moveDown`, `moveUp`, `topicClicked`, `fadeListIn`, `slideListIn` |
| `/DialogueMenu_mc/TopicListHolder/List_mc` | class `TopicList`; the topic rows |
| `/DialogueMenu_mc/ExitButton` | frame labels `up`, `over`, `down`, `disabled` |

`DialogueMenuObj` publishes its own state vocabulary as class constants — `SHOW_GREETING`
0, `TOPIC_LIST_SHOWN` 1, `TOPIC_CLICKED` 2, `TRANSITIONING` 3 — and the live instance
carries `eMenuState`. OpenSky writes that field, reading the value off the class rather than
pinning a number: measurement shows the entry points do not set it themselves, and routing
key input into a movie whose state field disagreed with what is on screen is how a menu
starts answering the wrong key.

The list is the same CLIK family every other OpenSky menu drives. `TopicList` adds
`UpdateList`, `SetSelectedTopic`, `SetEntryText` and `RepositionEntries` over a
`BSScrollingList` base carrying `EntriesA`, `iSelectedIndex` with -1 for none,
`InvalidateData` and `ClearList`. `iMaxItemsShown` is 8 and `iNumTopHalfEntries` is 4, which
is why the movie ships eight `Entry` clips and centres the selection.

**`SetSelectedTopic` is measured and deliberately unused.** `swf dialogue-menu --down 2`
reports the movie back at row 0 when that method is called with the row index and at row 2
when it is not, so whatever it takes, it is not the index. The selection is written onto
`iSelectedIndex` and followed by `UpdateList`, which is what repositions the centred entry
clips.

Row fields are `text`, `topicIndex`, `topicIsNew` and `responseHash`, structurally resolved
by `swf action-sweep`. `swf dialogue-menu --probe-rows` — the journal's cross-check — moves
no row-field name into the missing tally at all, because the centred list draws a row
through the entry clip's own `SetEntryText` rather than by reading named properties off the
row on the way past. `topicIsNew` is published false rather than guessed: OpenSky does not
model whether a player has heard a topic, and per-INFO said-state is a different question.
`responseHash` carries the winning INFO's FormID, the identity OpenSky addresses a response
by.

## What the model owns

`DialogueMenuModel` is movie-free and unit-tested without a window: rows, a cursor, and a
three-state machine — `greeting`, `topicList`, `response`. The movie's fourth state,
`TRANSITIONING`, is left to the movie, which owns the animation between them; a fourth
engine state that only mirrored an animation frame would be a second clock to keep in step.

The engine model is authoritative for the selection, unlike the [journal](/engine/journal.md)
where the movie owns it and the engine reads it back. That follows directly from
`SetSelectedTopic` above: there is no movie-side cursor to trust. The movie still receives
every key, so its own focus art and sounds run.

## Text resolution

Two record facts, measured with `swf dialogue-menu --text`, which resolves each field out of
all three string tables and prints what each answered:

| Field | Table | Rule |
| --- | --- | --- |
| DIAL `FULL` | `.strings` | the topic's own name, what a row reads by default |
| INFO `RNAM` | `.strings` | the prompt, which overrides the parent topic's text when present |
| INFO `NAM1` | `.ilstrings` | one TRDT response run, the line the speaker says |

`RNAM` is "the player's response to a question (INFO with TCLT options). If present,
overrides the default text coming from the parent dialogue topic"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO>); OpenSky's decoder calls it
`prompt`. A row whose text resolves to nothing falls back to the topic's editor ID and then
to its FormID, because an unlabelled row cannot be chosen on purpose.

## Subtitles

`HUDMovieBridge.setSubtitleText(_:runtime:)` writes
`/HUDMovieBaseInstance/SubtitleTextHolder/textField` and shows or hides the holder around
it. The holder is hidden rather than only blanked when there is no line, because it carries
authored art and a blank field inside a visible holder is an empty box on screen. The HUD
instance's `SubtitleText` property is that field's bound variable name, and
`SWFMovieRuntime.setText(_:of:)` writes both, so the drawn string and the variable the movie
reads stay in step.

M8.4.2 located this field and deliberately left it hidden because the vanilla movie ships an
authoring sample in it; this is the milestone that comment reserved it for.

The renderer owns one SWF layer, so the HUD and the dialogue menu are never up together:
while a conversation is open its own `SubtitleText` carries the line, and the HUD's field is
what a line must not survive into. Lines clear on advance and on exit. Precise end-of-line
timing arrives with item 17.5's playback clock.

## Input

| Event | Effect |
| --- | --- |
| `.move(.up)` / `.move(.down)` | moves the selection, stopping at the ends rather than wrapping |
| `.button(.accept)` | chooses the selected topic, or advances the line being said |
| `.button(.cancel)` | leaves the conversation |
| `.move(.left)` / `.move(.right)` | nothing; one vertical list |
| `.pointer` | not routed |

Pointer selection is skipped, and issue #205 made that conditional on matching the inventory
precedent: `MenuInputEvent.pointer` carries a delta while a movie hit test needs an absolute
stage position, so [the inventory menu](/engine/inventory-menu.md) and the
[system menu](/engine/system-menu.md) both map it to nothing, and so does this.

A conversation that opens on a greeting records it through `DialogueRuntime.choose` at the
moment it opens, so a say-once greeting spends itself and its result script runs. Its TCLT
links are deliberately dropped rather than becoming the topic list: a greeting is said
*over* the offered topics, and taking its links would replace the list the player is about
to read.

Choosing a topic runs `DialogueRuntime.choose`, which records said-state, dispatches the
response's result fragments and returns the topics it links to. Those links are held until
the line finishes rather than re-asked for, because re-asking would re-run the result
scripts. A response with no links returns the speaker to a freshly re-selected general list,
because choosing a say-once line has just changed it. A goodbye response closes the
conversation.

## What is deferred, and to where

`docs/decisions/swf-as2-scope.md` requires every unimplemented host API to be an accounted
no-op rather than a crash, and to be listed rather than silently absent.
`DialogueMenuMovieBridge.deferredEntryPoints` is that list:

| Entry point | Owner |
| --- | --- |
| `OnVoiceReady`, `SkipText` | item 17.5's voice clock — line timing is what tells the menu a line finished |
| `SetAllowProgress`, `StartProgressTimer` | the same gate from the movie's side, on its 750 ms `ALLOW_PROGRESS_DELAY` |
| `AdjustForPALSD` | standard-definition television layout; no use on a macOS target |

## Verification surface

`World > HUD & Interaction > Dialogue` (`Destination-hudInteraction`, section
`PanelSection-dialogue`). It sits beside the Target section because that is where the
crosshair lives, and moving it under item 17.8's own destination is a registry edit that
changes no control id.

| Control | Id |
| --- | --- |
| Open dialogue | `DialogueOpenControl` |
| Leave | `DialogueLeaveControl` |
| Up / Down / Choose | `DialogueUpControl`, `DialogueDownControl`, `DialogueChooseControl` |
| Topics and target readout | `DialogueTopicsStatsLabel` |
| Condition trace readout | `DialogueConditionsStatsLabel` |
| Movie readout | `DialogueMovieStatsLabel` |

Open dialogue is the same `openDialogue()` the use key reaches, and the four navigation
controls go through the same `MenuInputEvent` path as the live keys, so the key is an
accelerator for a listed control rather than an unadvertised keystroke.

The condition-trace readout is #426's `DialogueSelection` reduced to lines rather than
re-evaluated: it names every considered topic that offered nothing and the reason each of
its responses lost, which is how "the line I expected is missing" becomes answerable.

## Acceptance record

| Question | Evidence |
| --- | --- |
| Does the use key on an actor open a conversation? | `TalkTargetingTests`, `DialogueSectionTests` |
| Does the world keep running with it open? | `MenuModeControllerTests.dialogueMenuCapturesInputWithoutPausingTheWorld`, and the `world running` line in `DialogueTopicsStatsLabel` |
| Does a pausing menu over it still pause? | `MenuModeControllerTests.aPausingMenuOverAConversationPausesAndUnpauses` |
| Do the rows, selection and line reach the vanilla movie? | `DialogueMenuMovieBridgeTests`, `DialogueMenuRealDataTests.publishedConversationReachesTheMovie` |
| Does the vanilla movie still match the measured contract? | `DialogueMenuRealDataTests.vanillaMovieStillMatchesTheMeasuredContract`, `openskycli swf dialogue-menu` |
| Does the open menu draw? | `DialogueMenuRealDataTests.openMenuChangesRenderedPixels` |
| Do subtitles appear and clear? | `HUDMovieBridgeTests`, `DialogueMenuRealDataTests.hudSubtitleFieldTakesALineAndGivesItBack` |
