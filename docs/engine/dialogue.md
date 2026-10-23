---
type: Subsystem
title: Dialogue runtime
description: Which topics a speaker offers and which response wins, the rejection trace,
  shared responses, said-state and reset times, what choosing a response does, result script
  fragments, and what is saved.
tags: [engine, dialogue, conditions, quests, papyrus, runtime-state]
---

# Dialogue runtime

The dialogue runtime decides which topics a speaker offers, which response wins inside each,
what choosing one does, and what a save keeps. The record side (`DIAL`, `INFO`, `VTYP`) is on
the [dialogue records](/formats/dialogue.md) page. The menu is on the
[dialogue menu](/engine/dialogue-menu.md) page. The camera and speaker focus are on the
[dialogue camera](/engine/dialogue-camera.md) page, and mouth movement on the
[lip sync](/engine/lip-sync.md) page.

The runtime sits beside the world state, not inside it, like the quest runtime. The world state
knows about keys, components, the change log, and snapshots, and nothing about records. The
runtime uses no AppKit and also builds into `OpenSkyCLI`.

## Selection rules

1. The owning quest must be running. A `DIAL` names its quest in `QNAM`. All 15,037 `DIAL`
   records in `Skyrim.esm` name one, so this is the main filter. A topic with no quest is always
   available.
2. Only category 0 is a player choice. The category byte in `DIAL` `DATA` says what a topic is
   for. Scene, combat, detection, and the others are spoken by the systems that own them.
   `Skyrim.esm` has 6,535 player topics and 7,426 scene topics.
3. File order is selection order. Inside a topic, the `INFO` records are checked in the order
   the type 7 child group lists them, and the first whose conditions pass wins. That is why the
   dialogue store keeps group order and does not sort. A passing response flagged Random starts a
   stack instead: "If the next Info is also Random, it's put on the stack. The stack keeps building
   until an Info that is not marked Random is found, or an info marked Random End is found. The
   final Info is then added to the stack, and one of the Infos is selected randomly"
   (<https://ck.uesp.net/wiki/Topic_Info>). Responses that fail their conditions do not join or
   close the stack.
4. Say-once is checked before the conditions, per speaker: "this Info can only be said once by any
   given Actor ... However, a different actor that qualifies may say it" (Topic Info). The said
   state records each speaker of a Say Once line. A count saved without speakers, by an older
   build, counts for every speaker.
5. The reset time is checked next. "Hours Until Reset: After this line is spoken, the speaker
   will not say it again until the specified time has elapsed."
   (<https://ck.uesp.net/wiki/Topic_Info>.) The wait belongs to the speaker, so another actor may
   say the line at once. A session with no clock does not hold a line back.
6. A forced speaker is checked with the conditions. `INFO` `ANAM` names the `NPC_` allowed to say
   the line. 223 of the 31,465 responses in `Skyrim.esm` have one. If the reference index has no
   record for the speaker, the check passes. It must not silence an actor for a reason that has
   nothing to do with the record.
7. Offered topics are sorted by `DIAL` `PNAM` priority, highest first. Ties go to the lower
   FormID. That tie-break is OpenSky's: the Creation Kit gives no order for equal priorities, and
   dictionary order would give the same world two different menus.

Each response is checked with the speaker as subject, the player as target, and the topic's
quest as the alias quest ([condition evaluation](/engine/conditions.md)).

Greetings use the same rules, but are found by `DIAL` `SNAM` subtype `HELO`, not by category,
because the player does not pick a greeting. `Skyrim.esm` has 297.

## Branches

A dialogue branch (`DLBR`) groups the topics of one conversation. The Creation Kit page
(<https://ck.uesp.net/wiki/Dialogue_Branch>) gives three flags: top-level (0x01), blocking
(0x02), and exclusive (0x04). The branch's starting topic (`SNAM`) is where the conversation
opens. OpenSky applies them like this:

1. A blocking branch whose quest runs and whose starting topic has a passing response for the
   speaker supplies the greeting. When that response links topics (a choice list), they are
   offered instead of the normal list. Without links, the starting topic is the only topic. When
   the response is a goodbye ("Force Goodbye"), the speaker says it and no menu opens. All other
   topics are rejected as blocked by that branch. When several answer, the branch of the quest with
   the highest priority wins, and ties go to the lower `DLBR` FormID. The tie-break is OpenSky's.
2. Otherwise, only the starting topics of top-level branches open a conversation. A topic that
   is not a branch entry is rejected as not a branch entry. Only a link (`TCLT`) from a chosen
   response reaches it.
3. When the speaker says a line of an exclusive branch, the speaker stays in that branch. The
   branch then acts as blocking for that speaker and goes before every other blocking branch.
   A line from any other branch takes the speaker out. An exclusive branch whose starting topic
   no longer passes is passed over, so the speaker is not stuck.
4. A topic that names no branch is offered. Every player topic in `Skyrim.esm` names one, so
   this only keeps plugins that leave `BNAM` out working.

`Skyrim.esm` has 3,061 branches: 2,116 top-level, 712 blocking, 203 with no flag, 16 blocking
and exclusive, 13 exclusive, and 1 top-level and exclusive.

Which branch a speaker is in is a world-state component, `dialogueBranch`, keyed by the
speaker. Only an exclusive branch is stored, and a save keeps it in the `DLBS` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

## The trace

A selection returns the offered topics, the topics that offered nothing, and the condition
tally. Each topic has one trace line per response, with the condition result and one of five
reasons:

| Reason | Meaning |
| --- | --- |
| `questNotRunning` | The topic's quest is not running, so no response was checked |
| `alreadySaid` | Say-once, and already used |
| `waitingForReset` | The speaker said it fewer game hours ago than its reset time |
| `conditionsFailed` | The conditions were false, or `ANAM` named another speaker |
| `notReached` | An earlier response in file order already won |
| `lostRandomPick` | It passed and joined a Random stack, and another response was picked |

Nothing stops early. Every topic is checked even after several have won. The question "why is
this line not offered?" needs exactly the topics a shortcut would skip.

## Shared responses

"Share Response Data From Info: Select a SharedInfo ID to acquire the response lines from that
Info." (<https://ck.uesp.net/wiki/Topic_Info>.) An `INFO` with a `DNAM` says the responses of the
`INFO` it names: their text, and their voice files, which are named after that target `INFO`
and its topic. Its own conditions, flags, result scripts, and topic links still apply. The
target can share again; the chain stops at a missing `INFO` or a loop. Said-state stays on the
`INFO` that was chosen, not on the target.

Observed in `Skyrim.esm`: 3,411 `INFO` records have a `DNAM`, and none has responses of its own.
Every target is in a miscellaneous-category topic with subtype `IDAT`, and none shares again.
Of the 3,901 voice file names built from the targets, 3,894 exist in the archives for at least
one voice type.

## Said-state

Said-state is a world state component, keyed by the `INFO` record's session-stable
`ReferenceKey`, the same way quest state is keyed by the `QUST`. It holds a said count and, for
a response with a reset time, the `GameDaysPassed` day each speaker last said it.

The count is per response, not per speaker. The Dialogue Views page above says a say-once line
is "never said again". The Topic Info page says instead that another actor may still say it.
OpenSky follows the first, because a Skyrim save stores one said flag per `INFO` change form,
not one per actor. Shared responses (`INFO` `DNAM`) can be reached from several speakers, so a
table per speaker would let each of them say the same "once" line.

Where the conversation is inside a branch is not stored. `Skyrim.esm` has zero `INFO` records with a
`PNAM` previous-info link, and 4,294 with `TCLT` topic links. So the next lines depend only on
the chosen response and said-state. There is no cursor to save.

## Choosing a response

Choosing does three things, in this order:

1. It writes said-state first, so a result script that selects again sees its own line as said.
2. It sends the result script fragments, begin before end.
3. It selects the follow-up topics from the response's `TCLT` links, with the same rules as the
   offered list.

Step 3 runs after the fragments are queued, not after they run. Script events go through one
queue on a later tick. So a dialogue branch that depends on a stage its own result just set sees
the world before the result. The quest page describes the same gap for `SetStage`.

The result also carries the goodbye flag ("this response ends the conversation") and a count of
fragments nothing ran. So a declared fragment that did not run shows as a number, not silence.

## Response flags after the line

Topic Info gives two more flags that act when a response ends:

- Invisible Continue: "When this Info is finished, the next Info will begin automatically; no
  player prompt will be displayed." The menu says the first passing linked response at once.
- Walk Away: "If the player backs out of this Info's Choice List, the Walk Away Topic will be
  spoken as dialogue ends." The topic is `INFO` `TWAT`. Walk Away Invisible in Menu keeps it off
  the choice list. The line is voiced and subtitled outside the menu after it closes.

## Favour lines

The Favors tab topics (category 4: `SHOW`, `AGRE`, `REFU`, `MREF`, `FEXT`) "play in response to
specific Follower Command events" (<https://ck.uesp.net/wiki/Favors_Tab>). The follower commands
themselves (`DialogueFollowerFollowTopic`, `DialogueFollowerWaitTopic`, the favour-state topic
"I need you to do something") are ordinary player topics of `DialogueFollower` in `Skyrim.esm`.
Their result scripts call `SetDoingFavor`. When that call changes an actor's favour state, the
actor says its `SHOW` line on entry and its `FEXT` line on exit. Command mode, where the player
points at a target and the follower agrees or refuses, does not exist yet, so `AGRE`, `REFU`, and
`MREF` are not said.

## Result scripts

A dialogue result is a Papyrus fragment, not a record field. The Creation Kit compiles the two
result boxes of a response into one script named `TIF_<editorID>_<formID>`. In shipped data it is
usually `TIF__<formID>`, with two underscores, because most `INFO` records have no editor ID. The
`VMAD` tail says which function belongs to which box ([VMAD](/formats/vmad.md)).

Dispatch follows quest stage fragments:

- The instance key is the `INFO` `ReferenceKey` plus the script name. An `INFO` is in no cell,
  like a `QUST`, so persistence, `OnInit`, and timers work unchanged.
- The script attaches when a response is chosen, not before. A vanilla load order has 7,661
  result scripts, and a session speaks only a few lines.
- Nothing retires the instance. A quest has `Stop`. A response has nothing like it.
- The generated script usually also appears in the response's main `VMAD` list, with its
  properties filled. That entry is used first, and the bare name is the fallback. It is what lets
  a fragment reach the quest it advances.

A result that sets a quest stage follows the path the Creation Kit wrote: the `TIF_` script calls
`SetStage` on a `Quest`, which is the native that calls the quest runtime. The dialogue layer
knows nothing about stages, so it inherits the stage rules.

## Condition functions

Three functions came from the measured demand list. Indices are stored numbers. The Creation Kit
adds 4096.

| Stored | Creation Kit | Name | Conditions in `Skyrim.esm` `INFO` records |
| --- | --- | --- | ---: |
| 426 | 4522 | `GetIsVoiceType` | 6,324 |
| 566 | 4662 | `GetIsAliasRef` | 5,320 |
| 249 | 4345 | `IsInDialogueWithPlayer` | 428 |

`GetIsVoiceType` reads an actor's `VTCK`. The parameter may also be a form list of voice types
([GetIsVoiceType](https://ck.uesp.net/wiki/GetIsVoiceType)); most quest dialogue conditions name
one. An actor with no resolved voice type fails with a reason, instead of a false "no match".
`IsInDialogueWithPlayer` reads who the player talks to. Nobody talking is a real 0. Every
condition context the session builds carries both facts: the voice type of each loaded actor
after template inheritance, and the speaker from the moment the conversation opens.
`GetIsAliasRef` compares the run-on reference with the filled alias table of the alias quest.

The faction functions that guard and vendor lines depend on are on the
[condition evaluation](/engine/conditions.md) page.

## Saving

Said-state is saved in its own `DLGS` chunk, not inside `RDLT`, and the speaker days in a
`DLGT` chunk beside it. A component kind inside `RDLT` is
versioned by the format version, so an older build would refuse the whole file instead of
loading the rest. A session where nobody spoke writes no chunk
([save chunks](/formats/opensky-save-actor-chunks.md)).

An entry is a key plus a `UInt32` count. The starting state is never written, and an entry that
decodes as 0 is dropped. So a loaded world compares equal to the saved one.

## Speech timers

Some lines an NPC says on its own, outside a conversation. Game settings from the install hold
them back. The CK wiki "Category:Settings" (<https://ck.uesp.net/wiki/Category:Settings>)
describes the first three; how the others apply is OpenSky's reading of their names.

| Setting | Install | Use |
| --- | --- | --- |
| `fGameplayVoiceFilePadding` | 0.5 s | "seconds of silence that Skyrim inserts between consecutive voice lines": added to every line's length. The wiki lists 0.25, the engine default; `Skyrim.esm` sets 0.5 |
| `fAIForceGreetingTimer` | 3 s | "Time until an NPC can initialize a force greeting again": a package's force greet waits this long per speaker |
| `fAIGreetingTimer` | 5 s | "Time until an NPC can greet again": one speaker's next hello (`HELO`) |
| `fAIExclusiveGreetingTimer` | 2.5 s | After any hello, no other NPC greets for this long |
| `fAIMinGreetingDistance` | 150 | A hello needs the player this close. Not in `Skyrim.esm`; the wiki value |
| `fCombatDialogueAttackMinElapsedTime`, `...Max...` | 5 s, 10 s | After an attack or hit line, the speaker's next one of that kind waits a seeded time in this window |
| `fCombatDialogueTauntMinElapsedTime`, `...Max...` | 10 s, 30 s | The same window for taunts (`TAUT`) |
| `fCombatSpeakAttackChance` | 0.01 | The chance an NPC's landed blow speaks an `ATCK` line |
| `fCombatSpeakHitChance` | 0.01 | The chance an NPC hit by a blow speaks a `HIT_` line |
| `fCombatSpeakHitThreshold` | 0.01 | A blow or arrow speaks a hit line only when its damage is at least this share of the target's maximum health. A spell hit carries no damage, so it always may |
| `fCombatSpeakTauntChance` | 0.01 | Read as a chance per 1/60 s, so a fighter taunts about once every 1.7 s of open window. Not in `Skyrim.esm`; the wiki value |
| `fIdleChatterCommentTimer`, `...Max` | 10 s, 20 s | After one NPC near the player says an idle line (`IDLE`), every NPC waits a seeded time in this window |
| `fCommentOnPlayerActionsTimer` | 20 s | After a comment on the player, no NPC comments on the same kind of act for this long |
| `fCommentOnPlayerKnockingThings` | 40 s | The same, for the player pushing a loose object (`KNOO`) |
| `fBumpReactionSmallWaitTimer` | 3 s | One speaker's next bump line (`ACAC`); the bump rule is in [bump reactions](/engine/bump-reactions.md) |
| `fSpeechDelay` | 0.1 s | A line said outside a conversation starts this long after it is chosen |
| `fDialogSpeechDelaySeconds`, `fSubtitleSpeechDelay` | 2 s, 8 s | A line with no voice file stays up for its reading time, kept inside this window |
| `fRandomSceneAgainMinTime`, `...MaxTime` | 10 s, 30 s | The wait before a scene flagged "Repeat while true" plays again ([scenes](/engine/scenes.md)) |

`fCombatSpeakTauntChance` and `fAIMinGreetingDistance` are the CK wiki table values; the
wiki's Scenes category also gives 150 units for the greeting distance
(<https://ck.uesp.net/wiki/Category:Scenes>).

A line is picked from the topics of its `DIAL` subtype, as the speaker's conditions allow. The clock
is the scene clock: game seconds over the timescale.

Who speaks:

- A hello comes from the nearest NPC that detects the player inside the greeting distance, is not
  fighting, not in a scene or the conversation, and whose package allows hellos (`PKDT` interrupt
  flag 0x01). It looks at the player.
- An idle line comes from a free NPC within 1000 units of the player, in a seeded order. The
  distance is OpenSky's; no setting names it. No hello and no idle line plays while the player is
  in a conversation.
- A taunt comes from any fighting NPC that is free, with no head turn.
- A comment on the player comes from the nearest free NPC within 1000 units that detects the
  player. The acts that start one: a shout (`PCSH`), a melee swing out of combat (`SWMW`), a bow
  shot out of combat (`FIWE`), and pushing a loose object (`KNOO`).

The ambient pass runs every 15 frames. A line chosen while the delay of `fSpeechDelay` runs is
queued; the queue is not saved.

## Not done yet

- Topics are scoped by branch, not by dialogue view (`DLVW`). Views are an editor layout, and no
  open source says the game reads them at run time.
- Scene topics are spoken only by the [scene runtime](/engine/scenes.md).
- A topic row shows the chosen `INFO`'s own prompt (`RNAM`), not the shared target's.

## Measured coverage

Selecting for Sybille Stentor, with only the quests that start enabled, and with branch scoping.
Delphine, who is named by more player-facing `INFO` conditions than any other NPC, is offered
nothing in that state: her quests' dialogue conditions name the Thalmor and Vigilant factions and
voice types she does not have. Most topics are rejected as not a branch entry without their
conditions being evaluated:

| Measure | Value |
| --- | ---: |
| Topics offered | 4 |
| Conditions evaluated | 5,371 |
| Conditions that could not be answered | 2,886 |

Every function the selection meets is registered. The unanswered conditions read seams the test
context does not supply, such as packages and scenes. The full table goes to
`.logs/dialogue-selection/<stamp>/`.

All 7,661 `INFO` fragment tails in the five masters decode, with 8,009 result script fragments,
no record failures, and no bytes left over.
