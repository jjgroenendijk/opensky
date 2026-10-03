---
type: Subsystem
title: Dialogue runtime
description: Which topics a speaker offers and which response wins, the rejection trace,
  said-state, what choosing a response does, result script fragments, and what is saved.
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
   dialogue store keeps group order and does not sort.
4. Say-once is checked before the conditions. "Say Once: If checked, this info will only be said
   once. Once said, it will never be said again." (<https://ck.uesp.net/wiki/Dialogue_Views>,
   Response Data.)
5. A forced speaker is checked with the conditions. `INFO` `ANAM` names the `NPC_` allowed to say
   the line. 223 of the 31,465 responses in `Skyrim.esm` have one. If the reference index has no
   record for the speaker, the check passes. It must not silence an actor for a reason that has
   nothing to do with the record.
6. Offered topics are sorted by `DIAL` `PNAM` priority, highest first. Ties go to the lower
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
   speaker is the only topic offered, and it is also the greeting. All other topics are
   rejected as blocked by that branch. When several answer, the branch of the quest with the
   highest priority wins, and ties go to the lower `DLBR` FormID. The tie-break is OpenSky's.
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
tally. Each topic has one trace line per response, with the condition result and one of four
reasons:

| Reason | Meaning |
| --- | --- |
| `questNotRunning` | The topic's quest is not running, so no response was checked |
| `alreadySaid` | Say-once, and already used |
| `conditionsFailed` | The conditions were false, or `ANAM` named another speaker |
| `notReached` | An earlier response in file order already won |

Nothing stops early. Every topic is checked even after several have won. The question "why is
this line not offered?" needs exactly the topics a shortcut would skip.

## Said-state

Said-state is a world state component with one count, keyed by the `INFO` record's
session-stable `ReferenceKey`, the same way quest state is keyed by the `QUST`.

It is per response, not per speaker. The Creation Kit rule belongs to the response. Shared
responses (`INFO` `DNAM`) can be reached from several speakers, so a table per speaker would let
each of them say the same "once" line.

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

`GetIsVoiceType` reads an actor's `VTCK`. An actor with no resolved voice type fails with a
reason, instead of a false "no match". `IsInDialogueWithPlayer` reads who the player talks to.
Nobody talking is a real 0. `GetIsAliasRef` compares the run-on reference with the filled alias
table of the alias quest.

The faction functions that guard and vendor lines depend on are on the
[condition evaluation](/engine/conditions.md) page.

## Saving

Said-state is saved in its own `DLGS` chunk, not inside `RDLT`. A component kind inside `RDLT` is
versioned by the format version, so an older build would refuse the whole file instead of
loading the rest. A session where nobody spoke writes no chunk
([save chunks](/formats/opensky-save-actor-chunks.md)).

An entry is a key plus a `UInt32` count. The starting state is never written, and an entry that
decodes as 0 is dropped. So a loaded world compares equal to the saved one.

## Not done yet

- Topics are scoped by branch, not by dialogue view (`DLVW`). Views are an editor layout, and no
  open source says the game reads them at run time.
- Scene topics are spoken only by the [scene runtime](/engine/scenes.md).
- Shared responses (`INFO` `DNAM`) are not applied. They change what a line says, not whether it
  is offered.
- Reset times are decoded but not used. A repeatable line can repeat at once.

## Measured coverage

Selecting for Delphine (named by more player-facing `INFO` conditions than any other NPC in
`Skyrim.esm`), with only the quests that start enabled, and with branch scoping. Most topics are
rejected as not a branch entry without their conditions being evaluated:

| Measure | Value |
| --- | ---: |
| Topics offered | 4 |
| Topics rejected | 6,531 |
| Conditions evaluated | 6,101 |
| Conditions that could not be answered | 4,305 |

The functions most often still missing, by Creation Kit number: 4725 (411 conditions), 4702
(303), 4163 (61), 4351 (44), 4227 (25), 4180 (21). These are numbers, not names, because the
sweep counts what the plugin stores. Each gets its name when it is implemented from a cited
source. The full table goes to `logs/dialogue-selection/<stamp>/`.

All 7,661 `INFO` fragment tails in the five masters decode, with 8,009 result script fragments,
no record failures, and no bytes left over.
