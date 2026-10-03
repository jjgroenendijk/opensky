---
type: Subsystem
title: Story manager
description: How game events walk the story-manager tree and start quests, the event data
  conditions read, and the start-game pass over the .seq files.
tags: [engine, quests, conditions, papyrus, runtime-state]
---

# Story manager

The story manager starts quests when something happens in the game, such as a kill or a
change of location. Each kind of event has a tree of nodes; the record layout is on the
[story manager records](/formats/story-manager.md) page. This page also covers the start-game
pass, which starts the quests listed in the [`.seq` files](/formats/seq.md).

Sources: the Creation Kit wiki, <https://ck.uesp.net/wiki/Story_Manager>, "SM Event Node",
"SM Branch Node", and "SM Quest Node", and xEdit `dev-4.1.6` `wbEventMemberEnum` for the event
data members.

## The walk

An event fires with its four-character code and its data. The walk visits the event nodes
for that code in tree order, and each node's children in sibling order:

1. A node whose conditions fail is skipped with its whole subtree.
2. An event or branch node tries its children in order until one consumes the event.
3. A quest node tries its quests. A quest starts when it is not running, its reset time has
   passed, and its own story-manager conditions (`QUST` after `NEXT`) pass. Starting fills the
   quest's aliases from the event data.
4. A quest node starts one quest, or up to its "number of quests to run" when flag 0x40000 is
   set. With flag 0x10000 (do all before repeating) the quests started least often go first.
5. A quest node that started a quest consumes the event, and the walk stops. With flag 0x20000
   (shares event) it does not, so the walk goes on to the next sibling.
6. Flag 0x01 (random) starts the children or quests at a random position and goes round. The
   position comes from the session's seeded random stream, so a seeded session repeats.

A quest node with a maximum of concurrent quests stops when that many of its quests run.

Conditions are checked with the player as subject and event member `R1` as target. OpenSky
chose these: the wiki does not say what Subject means for a story-manager node, and in the
vanilla trees the conditions that matter use the Event Data run-on.

## Event data

| Member | Meaning |
| --- | --- |
| `R1`, `R2` | Actor 1 and actor 2, references |
| `L1`, `L2` | Location 1 and location 2 |
| `K1` | Keyword |
| `F1` | Form |
| `O1` | Created object, a reference |
| `Q1` | Quest |
| `V1`, `V2` | Value 1 and value 2, numbers |

A condition with run-on type 7 (event data) runs on the reference member its parameter 3
names. `GetEventData` (576) compares a member with a form (`IsID`), reads a value, or tests
the keyword ([conditions](/engine/conditions.md)). Outside a walk, both fail as unresolved.

## Events OpenSky fires

| Code | When | Data |
| --- | --- | --- |
| `KILL` | An actor dies | `R1` killer, `R2` victim, `L1` victim's location, `V1` crime status 0, `V2` relationship rank 0 |
| `CLOC` | The player's location changes | `R1` player, `L1` old location, `L2` new location |
| `SCPT` | A script calls `Keyword.SendStoryEvent()` | `K1` the keyword, `L1`, `R1`, `R2`, `V1`, `V2` from the call |

The `KILL` member order comes from the order of the Creation Kit's "Kill Actor" event data
list: killer, victim, location, crime status, relationship rank. This mapping is inferred and
not confirmed by a cited source. OpenSky does not compute crime status or relationship rank.
`CLOC` is checked every 30 frames. Every other event can be fired from the sidebar, with the
player as `R1`.

`SendStoryEventAndWait()` returns at once with the result, because the walk is synchronous.

## Start-game pass

When a world loads, OpenSky reads the `.seq` file of each active plugin and starts every
listed quest that has no runtime state yet. A quest that a save already holds keeps its saved
state. Quests start first; then scripts attach once; then each quest runs its start-up stage
and starts its begin-on-start scenes. That order lets a start-up stage fragment see the other
start-game quests running.

The quest store indexes `Skyrim.esm` only, so the quests of the other plugins' lists are
reported as not in the quest store. On the install the pass starts the 330 quests of
`Skyrim.esm`.

## State and saving

The story manager keeps, per quest it started, the time of the last start and a count. The
reset time and "do all before repeating" read them. The world-state component is
`storyManager`, keyed by the `QUST`, and a save stores it in the `SMQS` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

## Observed on the install

`Skyrim.esm` has event nodes for 24 codes. Firing `ESJA` (escape jail) with the player as
`R1` starts `EscapeJailAchievementQuest` and `EscapeJailQuest`, with no condition failing.
`SKIL` starts `WISkillIncrease02`. The other events start nothing with only the player as
data, because their conditions ask for event data the sidebar does not give.

## Not done yet

- Only `KILL`, `CLOC`, and `SCPT` fire from play. Events such as `ADIA`, `LEVL`, `SKIL`, and
  `CRFT` fire only from the sidebar.
- `KILL` crime status and relationship rank are always 0.
- The quests of plugins other than `Skyrim.esm` do not start, because the quest store does not
  index them.
