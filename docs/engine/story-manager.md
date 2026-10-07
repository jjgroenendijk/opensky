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

The data of each event comes from its Creation Kit wiki page, such as
<https://ck.uesp.net/wiki/Kill_Actor_Event>. The wiki lists the data in order, not by member.
OpenSky gives the references `R1` and `R2`, the locations `L1`, the forms `F1`, and the numbers
`V1` and `V2`, in the order of the list. The vanilla nodes and quests agree with this: the
`KILL` quests read `V1` and the `KILL` nodes read `V2`, the `AIPL` nodes test the owner in
`R2`, and the `CRFT` quests compare `O1` with item base forms. So the `KILL` mapping below is
confirmed by the data, not only by the list order.

An event that does not set `L1` gets the current location of its `R1`, or of the player
when it has no `R1`.

| Code | When | Data |
| --- | --- | --- |
| `KILL` | An actor dies | `R1` killer, `R2` victim, `L1` victim's location, `V1` crime status, `V2` victim's rank toward the killer |
| `CLOC` | The player's location changes | `R1` player, `L1` old location, `L2` new location |
| `SCPT` | A script calls `Keyword.SendStoryEvent()` | `K1` the keyword, `L1`, `R1`, `R2`, `V1`, `V2` from the call |
| `SKIL` | A player skill gains a level | `R1` player, `V1` the skill's actor-value index |
| `LEVL` | The player gains a level | `R1` player, `V1` the new level |
| `CRFT` | The player crafts an item | `R1` player, `R2` workbench, `O1` the created base object |
| `ASSU` | An assault is reported | `R1` attacker, `R2` victim |
| `ADCR` | A crime costs crime gold | `R1` criminal, `R2` victim, `F1` crime faction, `V1` gold, `V2` crime type |
| `ARRT` | The player accepts an arrest | `R1` guard, `R2` player, `V1` crime type, always 0 |
| `JAIL` | The arrest sends the player to jail | `R1` guard, `F1` crime faction, `V1` bounty |
| `LOCK` | The player picks a lock | `R1` player, `R2` the locked reference |
| `CAST` | The player casts a spell | `R1` player, `R2` aimed target, `F1` spell |
| `AIPL` | The player takes, steals, or buys an item | `R1` source container, `F1` item, `V1` acquire type |
| `REMP` | The player drops, stores, or sells an item | `R1` container, `F1` item, `V1` remove type |
| `CHRR` | A script changes a relationship rank | `R1`, `R2` the actors, `V1` old rank, `V2` new rank |

`KILL` crime status is 0 (not murder), 1 (murder), or 2 (murder that cost crime gold). A death
is murder when the player struck the victim first ([crime](/engine/crime.md)). The rank is the
victim's rank toward the killer, 0 when no relationship names the pair. The crime type is 0
steal, 1 pickpocket, 2 trespass, 3 assault, 4 murder, 5 escape from jail, 6 werewolf. The
acquire type is 1 steal, 2 buy, 4 pick up, 5 container, 6 dead body. The remove type is 4
dropped, 5 given (sold), 6 put in a container.

`SKIL` fires once when one use raises a skill by more than one level, as the wiki says.
`CLOC` is checked every 30 frames. Every event can also be fired from the sidebar, with the
player as `R1`.

`SendStoryEventAndWait()` returns at once with the result, because the walk is synchronous.

### Events that do not fire from play

These have vanilla nodes, but OpenSky has no system that does what they describe:

| Code | Event | Why it does not fire |
| --- | --- | --- |
| `ADIA` | Two actors start a conversation | No NPC-to-NPC conversation system |
| `AHEL` | An actor says hello to another | NPC greetings do not run |
| `AFAV` | The player receives a favor | No favor system |
| `BRIB`, `FLAT`, `INTM` | Bribe, persuade, intimidate | No speech-check dialogue |
| `DEAD` | An actor finds a dead body | Actors do not react to bodies |
| `ESJA` | The player escapes jail | Jail time passes at once, so there is no escape |
| `NVPE` | The player learns a word of power | No shout learning |

`PFIN`, `STIJ`, `INFC`, `CURE`, and `QSTR` exist in the event list, but `Skyrim.esm` has no
node for them, so firing them would start nothing.

## Start-game pass

When a world loads, OpenSky reads the `.seq` file of each active plugin and starts every
listed quest that has no runtime state yet. A quest that a save already holds keeps its saved
state. Quests start first; then scripts attach once; then each quest runs its start-up stage
and starts its begin-on-start scenes. That order lets a start-up stage fragment see the other
start-game quests running.

The quest store, the scene index, and the story-manager index read every active plugin. On
the install the pass starts 436 quests: 330 from `Skyrim.esm` and the rest from `Update.esm`,
the three DLC, and the two free Creation Club plugins.

## State and saving

The story manager keeps, per quest it started, the time of the last start and a count. The
reset time and "do all before repeating" read them. The world-state component is
`storyManager`, keyed by the `QUST`, and a save stores it in the `SMQS` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

## Observed on the install

`Skyrim.esm` has event nodes for 24 codes: `ADCR`, `ADIA`, `AFAV`, `AHEL`, `AIPL`, `ARRT`,
`ASSU`, `BRIB`, `CAST`, `CHRR`, `CLOC`, `CRFT`, `DEAD`, `ESJA`, `FLAT`, `INTM`, `JAIL`, `KILL`,
`LEVL`, `LOCK`, `NVPE`, `REMP`, `SCPT`, and `SKIL`. Firing `ESJA` (escape jail) with the
player as `R1` starts `EscapeJailAchievementQuest` and `EscapeJailQuest`, with no condition
failing. `SKIL` starts `WISkillIncrease02`. The other events start nothing with only the player as
data, because their conditions ask for event data the sidebar does not give.

## Not done yet

- The events in "Events that do not fire from play" above.
- `AIPL` and `REMP` name no owner in `R2`, and pickpocketing, eating, and items a script moves
  fire neither event.
- `ARRT` names no crime type, because the bounty does not record which crime it is for.
- A DLC quest's conditions and dialogue still read FormIDs as if they were `Skyrim.esm`
  numbers. Its aliases and script properties use the quest's own plugin. The `F1` form of an
  event uses the same numbering.
