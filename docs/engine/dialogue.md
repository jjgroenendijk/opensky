---
type: Subsystem
title: Dialogue runtime
description: Topic selection, state, camera and speaker focus, plus audio-clock lip-sync
  playback that drives actor-local FaceGen TRI expressions.
tags: [engine, dialogue, conditions, quests, papyrus, runtime-state, voice, lip-sync]
timestamp: 2026-08-11T00:00:00Z
---

# Dialogue runtime

The dialogue runtime decides which topics a speaker offers, which response wins inside each,
what choosing one does, and what survives a save. Its visible layers frame and focus the
speaker, play the selected voice, and drive that actor's mouth from the embedded lip track.
The record side — DIAL, INFO and VTYP bytes — is
[dialogue records](/formats/dialogue.md); the shared condition machinery is
[conditions](/formats/conditions.md); the quest state a topic is gated on is
[runtime reference identity and world state](/engine/runtime-state.md).

## Contents

* Where selection lives
* Selection rules and their sources
* The trace, and why it is kept
* Said-state as a world-state component
* Choosing a response
* Result scripts: the INFO VMAD tail
* Condition functions dialogue demanded
* Save and load
* Dialogue camera
* Speaker focus
* Dialogue-camera verification surface
* Lip-sync playback
* Lip-sync verification surface
* M17 milestone verification surface
* What this version does not do
* Measurements

## Where selection lives

| Type | File | Holds |
| --- | --- | --- |
| `DialogueRuntime` | `opensky/Engine/Dialogue/DialogueRuntime.swift` | selection over `WorldStateStore`, `DialogueStore` and `QuestStore` |
| `DialogueRuntime.choose` | `opensky/Engine/Dialogue/DialogueRuntimeChoice.swift` | applying a chosen response |
| `DialogueSelection` and friends | `opensky/Engine/Dialogue/DialogueSelection.swift` | the answer plus the per-response trace |
| `DialogueRuntimeState` | `opensky/Engine/Dialogue/DialogueStateComponent.swift` | one INFO's said-state |
| `DialogueResolution` | `opensky/Engine/Dialogue/DialogueResolution.swift` | the condition seam for voice type and the open conversation |

`DialogueRuntime` is a `@MainActor struct` beside the store rather than methods on it,
following `QuestRuntime`: the store knows about keys, components, journalling and snapshots
and deliberately knows nothing about records. It is AppKit-free and compiles into
`openskycli`.

## Selection rules and their sources

1. **The owning quest must be running.** A DIAL names its quest in QNAM, and all 15,037
   DIAL records in `Skyrim.esm` name one, so this is the primary filter rather than an edge
   case. A topic naming no quest is always available.
2. **Only category 0 is a player choice.** DIAL DATA's category byte says what a topic is
   for; scene, combat, detection and the rest are spoken by the machinery that owns them.
   `Skyrim.esm` has 6,535 player topics against 7,426 scene topics.
3. **File order is selection order.** Inside a topic the INFO records are evaluated in the
   order the type-7 child group lists them and the first whose conditions pass wins. That is
   why `DialogueStore` preserves group order rather than sorting.
4. **Say-once is checked before the conditions.** "Say Once: If checked, this info will only
   be said once. Once said, it will never be said again."
   (<https://ck.uesp.net/wiki/Dialogue_Views>, Response Data.)
5. **A forced speaker wins over the conditions.** INFO ANAM names an NPC_ allowed to say the
   line; 223 of `Skyrim.esm`'s 31,465 responses carry one. A speaker the reference index
   holds no record for cannot be compared, so the gate passes rather than silencing an actor
   for a reason that has nothing to do with the record.
6. **Offered topics are ordered by DIAL PNAM priority, descending.** Ties fall to ascending
   FormID. The tie-break is OpenSky's: the Creation Kit documents no order between equal
   priorities, and a dictionary order would make the same world produce two different menus.

Each response is evaluated with `subject` set to the speaker's `ReferenceKey`, `target` set
to the player, and `aliasQuest` set to the topic's owning quest — the scope
`ConditionContext.aliasQuest` has anticipated since issue #251.

Greetings use the same machinery, selected by DIAL SNAM subtype `HELO` rather than by
category, because a greeting is not a topic the player picks. `Skyrim.esm` carries 297 of
them.

## The trace, and why it is kept

`DialogueSelection` returns the offered topics, the topics that were considered and offered
nothing, and the `ConditionTally` from the whole pass. Each topic carries one
`DialogueInfoTrace` per response, with the `ConditionOutcome` that decided it and one of
four rejection reasons:

| Reason | Means |
| --- | --- |
| `questNotRunning` | the topic's owning quest is not running, so no response was evaluated |
| `alreadySaid` | say-once, and already spent |
| `conditionsFailed` | the condition list evaluated false, or ANAM named another speaker |
| `notReached` | an earlier response in file order already won |

Nothing short-circuits: every topic is evaluated even once several have won, because
"why is this line not on offer" is the question item 17.8's acceptance panel has to answer,
and a short-circuit would leave exactly that case unexplained.

## Said-state as a world-state component

`DialogueRuntimeState` holds one `saidCount` and is keyed by the INFO record's session-stable
`ReferenceKey`, exactly as `QuestRuntimeState` is keyed by a QUST's. `DialogueStore` resolves
those keys through the plugin's master list, which is why it now takes a plugin name.

Said-state is per response and not per speaker. The documented rule is a property of the
response — "this info will only be said again" is not scoped to a listener — and shared
responses (INFO DNAM) are reachable from several speakers, so a per-speaker table would let
the same line be said once by each of them.

Branch progression is **not** stored. The vanilla sweep found zero INFO records in
`Skyrim.esm` carrying a PNAM previous-info link and 4,294 carrying TCLT topic links, so the
flow from one line to the next is a pure function of the chosen response plus said-state:
there is no cursor to persist.

## Choosing a response

`choose(_:speaker:)` does three things in this order, and the order is the point.

1. **Said-state is written first**, so a result script that re-enters selection sees the line
   it is running as already said.
2. **The result fragments are dispatched**, begin before end.
3. **The follow-up topics are selected** from the response's TCLT links, filtered by the same
   rules the offered list uses.

Step 3 runs after the fragments are *enqueued*, not after they have run: script events go
through the one FIFO on a later tick. A dialogue tree that branches on a stage its own result
just set therefore sees the pre-result world. That is the same deviation
`PapyrusWorldStateBridgeQuests.swift` already documents for `SetStage`, restated here because
this is where it would be noticed.

The returned `DialogueChoice` also carries the goodbye flag — the documented "this response
ends the conversation" bit — and an `unrunFragmentCount`, so a result script that declared a
fragment nothing ran is a number rather than a silence.

## Result scripts: the INFO VMAD tail

A dialogue result is a Papyrus fragment, not a record field. The Creation Kit compiles the
two result boxes of a response into one generated script named `TIF_<editorID>_<formID>` —
in shipped data usually `TIF__<formID>` with two underscores, because most INFO records carry
no editor ID — and the VMAD tail says which function belongs to which box. Layout and the
vanilla evidence: [Papyrus attachment data](/formats/vmad.md).

Dispatch mirrors quest stage fragments (`PapyrusWorldDialogue.swift`):

* The instance key is the INFO's `ReferenceKey` plus the script name. An INFO is in no cell,
  exactly like a QUST, so `PSCR` persistence, `firedOnInit` and the timer registry apply
  unchanged.
* The script attaches lazily, when a response is chosen. A vanilla load order carries 7,661
  result scripts and a session speaks a handful of lines.
* Nothing retires the instance. A quest has `Stop`; a response has no counterpart.
* The generated script normally also appears in the response's *primary* VMAD list with its
  properties filled in, so that entry is preferred and the bare name is the fallback. That is
  what lets a fragment reach the quest it advances.

A quest-stage result therefore reaches `QuestRuntime.setStage` along the route the Creation
Kit authored: the TIF_ script calls `SetStage` on a `Quest`, which is the M13 native, which
is `PapyrusWorldStateBridge`, which is `QuestRuntime`. Nothing in the dialogue layer knows
what a stage is, so item 13.2's stage rules are inherited rather than restated.

## Condition functions dialogue demanded

Three functions came off the measured demand list rather than off a guess
(`ConditionFunctionsDialogue.swift`). Indices are the raw stored numbers; the Creation Kit
spells each 4096 higher.

| stored | Creation Kit | name | conditions in `Skyrim.esm` INFOs |
| --- | --- | --- | ---: |
| 426 | 4522 | `GetIsVoiceType` | 6,324 |
| 566 | 4662 | `GetIsAliasRef` | 5,320 |
| 249 | 4345 | `IsInDialogueWithPlayer` | 428 |

`GetIsVoiceType` and `IsInDialogueWithPlayer` read `DialogueResolution`, a seam shaped like
the quest and actor ones: an actor's VTCK, and who the player is currently talking to. An
actor this session resolved no voice type for is a reason-tagged `unavailableDialogue`
failure rather than a convincing mismatch; an empty conversation is a real 0, because
"nobody is talking to the player" is a fact an empty seam states correctly.

`GetIsAliasRef` needed no new seam at all — it compares the run-on reference against the
filled alias table issue #183 already built, scoped by the context's `aliasQuest`.

Everything else on the demand list belongs to another subsystem — factions, inventory,
locations, keywords, Papyrus quest variables — and is honest work for the milestone that owns
it. The counts are below.

## Save and load

Said-state travels in its own additive `DLGS` chunk, split out of `RDLT` for the reason every
other gameplay chunk is: a component kind inside `RDLT` is versioned by `formatVersion`, so
an older build would refuse the whole file instead of loading the rest of the world. A
session in which nobody spoke writes no chunk at all. Layout:
[OpenSky save container](/formats/opensky-save.md).

An entry is one key plus one `UInt32` count. The untouched baseline is never written, and an
entry whose count decodes as zero is dropped rather than stored, so a restored world compares
equal to the world that was saved.

## Dialogue camera

Issue #427 adds the camera half of a conversation: while the menu is open the view frames the
speaker's head, and on Leave it hands the player's own view straight back.

**It is an override, not a camera mode.** `CameraMovementMode` is what the player chose to
look through and `G` cycles it; a conversation is something that happens to them. So the
dialogue camera writes `Renderer.freeFlyCamera` on top of whichever mode is live and remembers
what was there, and `movementMode` is never touched.

| Type | File | Holds |
| --- | --- | --- |
| `DialogueCamera` | `opensky/Engine/World/DialogueCamera.swift` | the framing math and the last resolved pose |
| `CameraCollisionProbe` | `opensky/Engine/World/CameraCollisionProbe.swift` | the pull-in, shared with `ThirdPersonCamera` |
| `RendererDialogueCameraState` | `opensky/Engine/Rendering/RendererDialogueCamera.swift` | the focus, the math, and the player pose being stood in for |
| `DialogueCameraBridgeState` | `opensky/App/GameViewControllerDialogueCamera.swift` | the force toggle, the target selector, and who is being held |

The swap is undone at the top of every input frame, before anything simulates, and re-applied
at the bottom of it. That ordering is the whole trick: `WalkController` integrates the player's
facing out of this same pose and the body is placed from its yaw, so a frame that simulated
against the dialogue pose would turn the player round to face themselves. Between frames the
dialogue pose is what stands, which is what the passes read and also what the audio listener
reads — a conversation is heard from where it is watched.

### Where the framing comes from

Nothing in the readable install frames a conversation, and that is a probe result rather than
an omission. `openskycli gmst list --prefix f` over the shipped `Skyrim.esm` declares no
`fDialogueCamera*`, no `fOverShoulder*`, and no camera framing setting of any kind. The only
dialogue-adjacent distances it carries are `fAIInDialogueModeWithPlayerDistance` (500) and
`fAIInDialogueModewithPlayerTimer` (60), which decide when an actor considers itself in
conversation rather than where a camera stands, and the `fAIHeadTrackDialogue*` family, which
is head tracking and out of scope. The rest lives in the retail executable, which OpenSky does
not read. So the framing is derived from the same two measurable things
[third person](/engine/walk-mode.md) derives from — the player capsule and the projected field
of view — and the one taste number is not re-decided: the fill fraction is
`ThirdPersonCamera.framingFillFraction`, so the engine makes that call exactly once.

| Quantity | Value | Where it comes from |
| --- | --- | --- |
| Target | The speaker's `NPC Head [Head]` bone | The posed rig, sampled per frame; the capsule's eye height when an actor resolved no rig |
| Framed span | 96 units | The head centred, reaching down to the capsule's midpoint and as far above the head as that is below it |
| Framing distance | ~126 units | `(span / 2 / fill) / tan(fov / 2)` at a 65-degree vertical fov |
| Shoulder offset | 24 units | One capsule radius, on the same side third person offsets to |
| Clearance behind the player | 24 units | `ThirdPersonCamera.minimumDistance`, so the lens clears the player's own silhouette |
| Field of view | 65 degrees | The shared world angle, whatever mode the conversation interrupted |

The shot: the camera stands on the side of the speaker the player is standing on, one shoulder
off the sightline so the framing is three-quarter rather than flat head-on, in the horizontal
plane through the *player's* eye — so a taller speaker is looked up at instead of the shot
being levelled out. Its distance from the speaker is the framing distance, or the player's own
distance plus the clearance when the player is standing further away than that. That second
clause is what keeps the player's body in the frame rather than behind the lens: walk right up
and the shot is tight, start the conversation from across the room and the camera sits at the
player's shoulder instead of hovering between the two of them.

The pull-in is `CameraCollisionProbe`, the same sweep third person zooms with, through the same
`CapsuleWorldCollider` seam the character controller collides with. It may never push the eye
closer than one capsule radius to the target, which is the point at which it would be inside
the speaker's head.

## Speaker focus

Entering a conversation stops the speaker, turns it to face the player and holds its package;
leaving hands all three back. Everything goes through the authority that already owns the
thing being changed, so nothing here can disagree with what the AI does on the next frame.

| What | Through | On release |
| --- | --- | --- |
| Walking | `CellStreamer.stopActor`, which parks the mover where it stands | Nothing — a resumed package asks for its own movement |
| Facing | `CellStreamer.faceActor`, an `NPCFacingHold` in the movement runtime | `releaseActorFacing`, leaving the actor on the bearing it reached |
| Package | `ActorPackageRuntime.setSuspended(_:actor:)` | `resumePackage`, which lifts the latch and force-re-selects |

`NPCFacingHold` turns the whole actor on the spot at `NPCMovementRuntime.maximumYawSpeed`, the
rate a mover corners at, and publishes a still drive every frame so the animation layer holds
the idle clip. It is not counted against the mover cap: a turn runs no path, no collision sweep
and no repath, so the CPU budget that cap protects does not apply to it. Starting a walk during
a hold takes the hold away and starting a hold takes the mover away, because one yaw has one
owner. Head tracking, eye contact and look-at IK are out of scope — nothing above the neck is
aimed at anything.

Suspension is a latch, not a saved procedure. An actor that spent a conversation standing still
has had the world move on around it, so what it needs on release is the package the schedule
names *now* — which is exactly `forceReevaluate`, the same reasoning
[combat's own resume](/engine/combat.md) follows.

The focus is republished every frame rather than latched on entry, because the speaker's head
is a bone of a running animation and the player can walk around a speaker mid-conversation. A
framing computed once at entry would be stale by the second sentence.

## Dialogue-camera verification surface

```text
Milestone: M17.4
Sidebar path: World > Dialogue & Voice > Dialogue Camera
Destination id: Destination-dialogueVoice
Controls exercised: DialogueCameraForceControl, DialogueCameraTargetControl,
  DialogueCameraOverlayControl
Readout: DialogueCameraStatsLabel, DialogueCameraSpeakerStatsLabel
Deterministic tests: DialogueCameraSectionTests, DialogueCameraTests,
  NPCMovementRuntimeTests, PackageRuntimeTests, DestinationRegistryTests,
  DialogueCameraRenderRealDataTests (env-gated, make realtest)
Local A/B (optional, never committed): logs/dialogue-camera-engaged.png
```

The force toggle is what makes the camera checkable without a conversation: a conversation
needs an actor with something to say standing within the interaction ray's reach, and the
framing has to be checkable against any actor in the cell. A conversation outranks the toggle
while it is open, so forcing the camera and then talking to somebody else cannot leave the view
pointed at the wrong actor mid-sentence.

The gizmo registers with the M16 [world-overlay registry](/engine/navigation.md) as
`dialogue-camera`: a yellow cross on the pivot, a cyan line from the player's eye to it, and a
magenta line along the camera's own axis. Drawn from the last resolved pose rather than from a
second resolve, so it cannot disagree with the frame it is drawn over.

## Lip-sync playback

Every resident actor with FaceGen expression bindings carries one `LipSyncPlayback` beside
its `FaceMorphPlayback`. Starting a `.fuz` voice line decodes its optional
[`.lip` payload](/formats/lip.md), selects the open conversation's speaker or the actor under
the crosshair, and starts that actor-local playback. Missing lip data, a missing selected
actor or malformed input is logged and surfaced in the Audio panel; it never stops the audio.

The audio source is authoritative. `WorldAudioEngine` publishes elapsed source time through
a lock-protected `VoicePlaybackClock`, and the render animation samples that snapshot at
30 Hz before mapping positional slots to named TRI targets. If the source stops publishing,
the line switches once to the render-animation clock anchored at the original line start. It
does not jump back to audio time if a late source reading appears, avoiding a visible mouth
snap in the middle of a sentence.

`FaceMorphPlayback` keeps manual debug weights and lip weights separately, then sums and
clamps them when it updates actor-local morph buffers. Turning lip sync off clears only the
lip layer. A normal line finish holds no final mouth pose: the last weights decay linearly to
bind pose over 0.15 seconds. Starting another line replaces the previous session.

The mapping layer is intentionally observable because the file stores positional slots, not
names. `LipSyncSnapshot` publishes the actor, line, clock mode, track time, live mapped
weights, active unmapped slots and release state. The Voice section's toggle and
`LipSyncStatsLabel` expose exactly that state.

## Lip-sync verification surface

```text
Item: M17.7
Sidebar path: World > Dialogue & Voice > Voice
Destination id: Destination-dialogueVoice
Controls exercised: AudioVoiceFileControl, AudioVoicePlayControl,
  LipSyncEnabledControl
Readout: AudioVoiceStatsLabel, LipSyncStatsLabel
Deterministic tests: LIPFileTests, LipVisemeMappingTests,
  LipSyncPlaybackTests, AudioVoicePanelTests, DestinationRegistryTests,
  LipSyncRealDataTests and LipSyncRenderRealDataTests
  (the last two are env-gated; make realtest)
Local A/B (never committed): logs/test-fast/latest/lip-*-off.png and
  logs/test-fast/latest/lip-*-on.png
```

## M17 milestone verification surface

The four sections the sub-issues built were each mounted beside their nearest neighbour —
the conversation and the face under `World > HUD & Interaction` because that is where the
crosshair is, the voice line under `World > Audio` because that is where the submixes are.
A conversation is one loop across all four, so the M17.8 gate assembled them into one
destination in the order a conversation uses them. Each section is standalone, so the move
was a registry edit and changed no control identifier.

```text
Milestone: M17.8 (the M17 gate)
Sidebar path: World > Dialogue & Voice > Dialogue, > Dialogue Camera, > Voice,
  > Face Morphs
Destination id: Destination-dialogueVoice
Controls exercised: DialogueOpenControl, DialogueLeaveControl,
  DialogueUpControl, DialogueDownControl, DialogueChooseControl,
  DialogueCameraForceControl, DialogueCameraTargetControl,
  DialogueCameraOverlayControl, AudioVoiceFilterControl,
  AudioVoiceFilterApplyControl, AudioVoiceFileControl, AudioVoicePlayControl,
  LipSyncEnabledControl, FaceMorphTargetControl, MorphWeightControl,
  FaceMorphResetControl
Readout: DialogueTopicsStatsLabel, DialogueConditionsStatsLabel,
  DialogueMovieStatsLabel, DialogueCameraStatsLabel,
  DialogueCameraSpeakerStatsLabel, AudioVoiceStatsLabel, VoiceSourceStatsLabel,
  LipSyncStatsLabel, FaceMorphStatsLabel
Deterministic tests: M17AcceptanceTests, M17AcceptancePanelTests,
  M17AcceptanceBudgetTests, DestinationRegistryTests, AppSidebarModelTests,
  OpenSkyUITests/testDialogueVoiceControlsAndReadouts,
  M17AcceptanceRealDataTests (env-gated, make realtest),
  M17AcceptanceRenderTests (env-gated and device-gated, make realtest)
Local A/B (optional, never committed): logs/test-fast/latest/m17-lip-*-off.png
  and m17-lip-*-on.png, logs/.../m17-conversation-none.png,
  m17-conversation-camera.png, m17-conversation-menu.png
```

The destination's override policy: an open conversation, a forced camera, a scrubbed morph
weight and lip sync switched off all light the sidebar dot, and "Reset all" puts each back.
Said-state and quest stages a conversation produced are deliberately not undone — those are
the milestone's point, not a knob left in a non-default position.

`VoiceSourceStatsLabel` is the one readout the gate added: the voice submix as
`WorldAudioEngine.statsSnapshot()` reports it, narrowed to voice, so a line that is playing
shows its distance and its playback clock and a silent one says so.

## What this version does not do

Stated rather than left to be discovered:

* **Topic scoping to dialogue views.** Selection offers every player-facing topic whose quest
  runs and whose responses pass. The original engine additionally scopes topics to the
  speaker's active dialogue views, so its menu is much shorter. Against the vanilla master
  this shows up plainly: the pinned speaker is offered 54 topics here where the game would
  show a handful. An obvious-looking fix — dropping every topic that is the target of some
  TCLT link — was measured and rejected: it cuts the list to 7 but also removes genuine
  top-level topics that happen to be link targets elsewhere.
* **Scenes.** SCEN playback is not implemented, and the M17 gate closed without it: the
  gate is satisfied by a conversation, and 7,426 of `Skyrim.esm`'s DIAL records belong to
  that separate machinery. It is deferred rather than dropped and carries a milestone of its
  own past M17.
* **Shared responses.** INFO DNAM replaces another record's *response data*, so it changes
  what a chosen line says rather than whether it is offered. It belongs to the text layer.
* **Reset intervals.** `TopicInfo.resetHours` is decoded and not consulted; a repeatable line
  is repeatable immediately.
* **Subtitles and scene playback.** Recorded voice, camera, speaker focus and mouth motion are
  connected; subtitle presentation and SCEN choreography remain separate work.

## Measurements

From the env-gated suites on 2026-08-09, against the shipped masters. The M17 gate re-ran
the selection half on 2026-08-12 and got the same numbers, so the table below is current.

`DialogueRuntimeRealDataTests` selects for one concrete speaker — Delphine, named by more
player-facing INFO conditions than any other NPC in `Skyrim.esm` — with quest state at the
plugin baseline, so exactly the start-game-enabled quests run:

| measure | value |
| --- | ---: |
| topics offered | 54 |
| topics considered and rejected | 6,481 |
| conditions evaluated | 11,622 |
| conditions that could not be answered | 7,837 |
| selection wall-clock | 0.08 s |

The heaviest functions still unimplemented across that selection, by Creation Kit number:
4167 with 1,103 conditions, 4725 with 761, 4702 with 356, 4143 with 201, 4169 with 79 and
4163 with 76. These are indices, not names: the sweep measures what the plugin stores, and
each becomes a name when a function is implemented against a cited source. The full table is
written to the gitignored run directory `logs/dialogue-selection/<stamp>/`.

`DialogueRealDataTests` now decodes every INFO fragment tail that it used to skip: 7,661
tails across the five masters, carrying 8,009 result-script fragments, with zero record
failures and zero bytes left over.

`M17AcceptanceRealDataTests` walks the same speaker's list to the first offer it can follow
all the way through — a winning response with a line on disk, under a quest with a stage to
set — and reports what it walked past. On 2026-08-12 that was
`mq00_mqdelphineconcordat_00024359_4.fuz`, 3.85 seconds declared, 661 lip keys, 15 unmapped
viseme slots, reached after three earlier runs of the same response were skipped: two hold
non-finite curve values and one uses a key tuple width the decoder does not support. That is
the honest state of lip decoding on this install — the corpus-wide tally is in
[.lip lip-sync tracks](/formats/lip.md) — and it is why the gate walks candidates instead of
pinning one file.

`M17AcceptanceRenderTests` measured the mouth region on 2026-08-12: 717, 740 and 748 changed
pixels for lip sync off versus on at 0.30 s, 0.37 s and 0.50 s of one line, 725 changed
pixels between the first and last of those times, and each pair repeated to zero changed
pixels. Over one exterior cell the dialogue camera moved 131,344 pixels and the vanilla
`dialoguemenu.swf` drew 17,572 over it.
