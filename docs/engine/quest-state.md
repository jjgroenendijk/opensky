---
type: Subsystem
title: Quest state
description: The runtime state of a quest - running and completed flags, reached stages and
  objectives with their cited rules, baselines, the mutation rules, and how reference and location
  aliases are filled, cleared, and read.
tags: [engine, quests, aliases, runtime-state, conditions, papyrus]
---

# Quest state

A quest is a `QUST` base record, not a placed reference. The [world state store](/engine/runtime-state.md)
does not mind: state is keyed by the record's `ReferenceKey`, as
[global variables](/engine/global-variables.md) are, so the journal, snapshot order, and save all
apply. Quest changes never belong to a cell, because a quest is in none. The records are on the
[quests](/formats/quest-records.md) page.

## The component

The quest component holds the running flag, the completed flag, the set of stages ever reached, and
a table of objective states (displayed, completed, failed). Its initializer enforces two rules, so
two stores with the same state snapshot and save the same way:

- Reached stages are sorted, with no duplicates.
- Objectives are sorted by index, one entry each, and never an entry with all three flags false.
  That is an objective nothing touched, and storing it would make two equal worlds compare unequal.

Like inventory, it is a full override. An untouched quest has no component, and the first change
copies its baseline in. Quest state is saved in the `QSTS` chunk.

## Rules

Every rule is from the Creation Kit wiki.

- The current stage is the highest reached, not the last set. `GetCurrentStageID` "obtains the
  highest completed stage in this quest". The `GetStage` condition shows the same: with stages 10,
  30, and 75 reached it returns 75 "even when stage 30 is completed after stage 75".
- A stage is done only if it was visited. After setting 0, 40, 20, and 60, `IsStageDone` "returns
  false for stages 10, 30 and 50 ... because these stages have not yet been visited". So reached
  stages are a set, not a high-water mark.
- Setting a stage already reached changes nothing. Setting a lower stage later leaves the current
  stage as it was, and makes the lower stage report done.
- Completing does not stop. `CompleteQuest()` "flags this quest as completed" and says nothing about
  running. A quest is usually stopped afterwards by a shut-down stage.
- The three objective flags are independent. `SetObjectiveDisplayed`, `SetObjectiveCompleted`, and
  `SetObjectiveFailed` each take their own Bool, and none clears another.

## Baselines

One thing comes from plugin data: a quest with the `DNAM` start game enabled flag reports running
without being touched, and stays clean while it does. The completed and failed bits in the same
field describe the quest's design, not a session, so a new game starts every quest not completed.

Vanilla's real start machinery is not modeled. Skyrim starts quests through story manager events
(the `QUST` `ENAM` event and the `SMEN`, `SMQN`, and `SMBN` node tree), through the seven-day
repopulation timer, and through dialogue. A quest that vanilla starts from an event stays dormant
here until something starts it. Quest scripts and stage fragments are on the
[Papyrus quest scripts](/engine/papyrus-quests.md) page.

## Changing a quest

| Operation | Effect | Refused when |
| --- | --- | --- |
| Start, stop | Moves the running flag only. Stopping keeps stages and the completed flag | Unknown quest |
| Complete | Sets completed, and leaves the quest running | Also: quest not running |
| Set stage | Records the stage. A start-up stage starts the quest, a shut-down stage stops it | Also: unknown stage, quest not running |
| Set objective displayed, completed, failed | Sets one flag | Also: unknown objective, quest not running |
| Reset | Drops the runtime state, so the quest derives from plugin data again | Never. Returns false if clean |

A refusal writes nothing. Each is a caller bug that a silent no-op would hide inside a quest that
never moves on.

OpenSky is stricter than vanilla in one place. Papyrus's `SetCurrentStageID` on a stopped quest
waits for it to start. Here, only a stage flagged start-up may move a stopped quest, and any other
stage is refused. Stage flags are plain record data, and a stage index may repeat within a `QUST`, so
the flags of every matching stage are combined.

Readers use a quest seam shaped like the global one: the session override wins, the baseline is next,
and no answer means the form ID names no quest. It can be built from the live store or from a
snapshot. Four `CTDA` functions read it ([conditions](/formats/conditions.md)). A quest parameter
naming no quest is a failure with its own tally bucket.

## Aliases

A quest points at the world through aliases, not form IDs. A reference alias is a numbered slot on
the `QUST` record, and dialogue, packages, journal text, and the quest's scripts point at the slot.

The alias table is its own component, keyed like the quest. It is separate because the lifetimes
differ: stage and objective state survives a stop, and the alias table is cleared by one. Fills are
sorted by alias ID, one each. Reference fills and location fills are separate lists, because a
location is a base record, not a placed reference. Reference fills store a `ReferenceKey`, and
location fills a resolved form ID. Neither stores a raw form ID. Reference fills are saved in `QALS`
and location fills in `QLOC`.

## When aliases fill

The Creation Kit's alias page (<https://ck.uesp.net/wiki/Alias>): "the aliases are not actually
'filled' until the quest starts running". So starting fills, stopping clears, and reset clears. A
start-up stage fills too, because it starts the quest. Starting a quest that already has a table
changes nothing, so a second `Start` never moves an alias a script is holding.

The fill follows four rules from the same page:

- Order is the list order, not the fill type: "The list of aliases is an ordered list - when the
  quest starts, aliases are filled in order", and "dependencies can only be to aliases higher in the
  list".
- Optional decides whether an empty alias stops the start: "If unchecked, the quest will fail to
  start if it cannot fill this alias." The start then fails and writes nothing.
- Force Into Alias takes the last writer: "The last 'source' alias that is filled will be the one
  that determines the final value for the specified 'target' alias."
- One quest does not fill two aliases with the same reference: "Normally, the game will not fill two
  aliases on the same quest with the same reference". The flag that allows it is checked on the
  second alias.

## What does not fill yet

Specific Reference (`ALFR`) and Specific Location (`ALFL`) fill. From Event fills when the
[story manager](/engine/story-manager.md) starts the quest: `ALFD` names the event data member, and
a reference alias takes a reference member while a location alias takes a location member. A quest
started any other way has no event, so the alias is counted and left empty.

Unique Actor (`ALUA`) names an `NPC_` base. The reference comes from the `LCUN` lists of the
`LCTN` records, which pair each unique base with its placed actor. Those lists cover 2,741 of the
2,900 Unique Actor aliases in `Skyrim.esm`. They miss some actors, such as `Ralof` and `Hadvar`,
so a miss is counted and left empty and never fails the start, the same as an unimplemented
fill. Every other fill type is counted and left empty, and an unimplemented fill type never
fails a quest start. Refusing a start because OpenSky cannot run a Find Matching Reference
search would present an engine gap as game behavior. Only an implemented fill that finds
nothing (an `ALFR` or `ALFL` naming no record) fails a required alias.

The reuse rule refuses the fill, not the start. The page says the rule "is not required for all fill
types" and names one exception, so which types it covers is not documented. Failing the start would
refuse thirteen quests `Skyrim.esm` ships that way.

Also not done: condition-driven and `ALFA` plus `ALRT` location searches, "Reserves Reference" (a rule
across quests), and any check that a filled reference exists, is alive, enabled, or not destroyed.

`Skyrim.esm` has 12,891 aliases across 1,607 quests. 5,591 fill: 2,688 specific references,
162 direct locations, and 2,741 unique actors. No quest is blocked from starting. The largest
gaps are Location Alias Reference (2,036, 15.8%), From Event (1,771, 13.7%), and aliases with no
fill subrecord at all (1,678, 13.0%).

## Who reads aliases

An alias seam over the plugin index and the session's tables answers by alias number and by name,
from the live store or a snapshot. A script property and a quest alias run-on carry a number. A
`CIS1` or `CIS2` condition override carries a name.

- Conditions: run-on 5 (quest alias) takes its alias number from `CTDA` parameter 3 and its quest
  from the list's owner. A `CIS1` or `CIS2` name resolves for a filled alias and stays unresolved for
  an empty one ([condition evaluation](/engine/conditions.md)).
- Script properties: an alias-typed `VMAD` property binds to the filled reference. An empty one keeps
  the compiler default and is counted.
- Alias scripts: the alias script sections of the `QUST` `VMAD` start on the reference in their alias
  and end with the quest ([Papyrus quest scripts](/engine/papyrus-quests.md)).
