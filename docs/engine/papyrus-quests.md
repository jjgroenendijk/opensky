---
type: Subsystem
title: Papyrus quest scripts
description: Quest script instances and their lifetime, the Quest natives, stage fragment dispatch,
  alias-typed properties and alias scripts, and where OpenSky differs from the documented latent
  behavior.
tags: [engine, papyrus, quests, aliases]
---

# Papyrus quest scripts

Quest state itself (running, stages, objectives, and alias fills) is on the
[quest state](/engine/quest-state.md) page. This page is the Papyrus side that reads and writes it.

## Instances

A quest is a base record, not a placed reference, so it never attaches or detaches with a cell. Its
instances are keyed by the `QUST` record's `ReferenceKey` plus the script name, and are persistent
and in no cell's attached set. Nothing a cell does reaches them, not even a world space change. The
key has the same shape as a reference's key, so saving, the fired `OnInit` set, and update timers
work unchanged.

A quest's scripts are its `VMAD` primary list plus the generated fragment script the `VMAD` tail
names (`QF_<editorID>_<formID>`). Shipped data usually lists that script in both places, and the two
collapse onto one instance. `OnInit` is queued for each new instance and fires once ever.
`OnCellAttach` and `OnLoad` are never queued, because neither means anything for an object in no
cell.

Which quests get instances is the quest state's answer. Running quests are attached at wire-up: the
start-game-enabled quests, or whatever a save recorded. `Start` and `Stop` keep the set current.
`Stop` is the only thing that retires a quest's instances, and it clears their fired `OnInit` marks,
so a later `Start` runs `OnInit` on fresh instances instead of resuming half a script.

## The Quest natives

`IsRunning`, `IsCompleted`, `GetCurrentStageID`, `IsStageDone`, `Start`, `Stop`, `CompleteQuest`,
`SetCurrentStageID`, `SetObjectiveDisplayed`, `SetObjectiveCompleted`, `SetObjectiveFailed`, and
`CompleteAllObjectives` are registered, plus `GetStage`, `GetStageDone`, and `SetStage`, the wrapper
names shipped `Quest.psc` declares around three of them. Each makes one call into the quest runtime,
so the stage and objective rules live in one place.

`CompleteAllObjectives` completes the objectives the quest has shown. An objective never shown has
no journal row, so leaving it out changes nothing the player sees.

A refused change becomes a native failure, and the call returns its declared default. For
`SetStage` that is false, which matches the documented "returns false and the stage is unchanged".

Absent on purpose, and left in the unimplemented tally: `Reset`, `IsObjectiveDisplayed`,
`IsObjectiveCompleted`, `IsStarting`, `IsStopping`, `GetAlias`, `GetAliasedRef`, and `SetActive`.
They need more alias support or a latent window OpenSky does not have.

A method call on an instance runs under the script that declares the function. So
`someQuest.SetStage(10)` reaches the `Quest` natives only when `Quest.pex` is loaded. That is why a
script loads with its ancestors ([lazy script library](/engine/papyrus-world.md#lazy-script-library)).

## Scene and story natives

`Scene.Start`, `Scene.ForceStart`, `Scene.Stop`, and `Scene.IsPlaying` call the
[scene runtime](/engine/scenes.md). `Keyword.SendStoryEvent` and `Keyword.SendStoryEventAndWait`
fire a `SCPT` event with the keyword and the call's location, actors, and values. Both return
true when the walk started a quest. Scene begin, end, and phase fragments queue on the scene's
fragment script like stage fragments.

## Stage fragments

The Creation Kit compiles each stage fragment into a numbered function on the generated script. The
`VMAD` tail's fragment table is the only record of which stage each function belongs to
([VMAD](/formats/vmad.md)). When a stage goes from not reached to reached, each matching function is
queued on the fragment script's instance through the ordinary queue. So the tick budget, one event
at a time per instance, and global order apply to fragments as to `OnActivate`.

Each fragment belongs to one log entry of its stage. A stage with several log entries runs only the
fragment of the first entry whose conditions pass, with the player as Subject. For example, `MQ101`
stage 0 has five entries keyed on one global's value; value 0 is the normal start, and the others
are debug starts. A session without a condition evaluator runs every entry's fragment. That choice is
an observation of `Skyrim.esm` data, not a documented rule.

When the log entry that runs has the Complete Quest flag (`QSDT` bit 0), setting the stage also
completes the quest. With no choice made, that is the stage's first entry.

All scripts on one quest are one object in the game. Here each script is its own instance, so a cast
from one to another, such as `self as MQ101QuestScript` in a fragment, finds the sibling instance on
the same form ([Papyrus VM](/engine/papyrus-vm.md)).

A fragment naming a script the quest has no instance of is counted as
`missingQuestFragmentInstance`. A function the script does not define is counted as
`undefinedEventFunction`. Neither is a fault.

## Aliases in scripts

A `VMAD` object property whose alias word is not -1 names an alias slot on the quest its form ID
identifies. It binds to the filled reference's live handle, like a direct property. A filled
reference with no scripts gets its opaque handle, so a marker alias is not `None`. The property holds
the reference itself, not an alias object. So `GetRef`, `GetReference`, `GetActorRef`, and
`GetActorReference` on `ReferenceAlias` return their receiver. An empty alias,
because the quest is not running or its fill type is not implemented, keeps the compiler default and
is counted as an unfilled quest alias. The world runtime holds the current alias answers, and the
session refreshes them after every fill or stop. So binding stays nonisolated and never calls back
into the main-actor session.

Alias script sections become instances when the quest attaches. Unlike other quest scripts they are
keyed by the filled reference, not by the quest. A `ReferenceAlias` script runs on the reference in
its alias, so this gives it the same `Self` and the same handle as the reference's own scripts. It
also stops two aliases with the same script name from sharing one instance. The runtime remembers
which quest owns which alias instances, so `Stop` retires exactly its own.

An empty alias gets no instance. An alias script section naming another quest is skipped, because
filling that alias needs the other quest's table. A save restores the fills with the world state,
and the session attaches running quests' scripts afterwards, so alias scripts come back bound to the
restored fills.

## Where OpenSky differs

- `SetStage` and `Start` are latent in the game: they wait for the quest to start and its fragments
  to finish. OpenSky writes the state, queues the fragments, and returns. The fragments run on a
  later tick. So a script that reads state right after sees the value before its fragment ran, and
  `IsRunning` is true at once after `Start`.
- A fragment runs only on the change into a stage. Setting a stage already reached runs nothing,
  because setting a stage is idempotent. The `QUST` allow-repeated-stages flag is decoded and not
  used: nothing open says what the game does with it, and a guess would run fragments twice.
- A shut-down stage stops the quest but does not retire its instances, so the fragment that stage
  queued still runs. Only `Stop` retires them.
- Quests start from the `.seq` start-game pass, from `Start`, from a start-up stage, or from the
  [story manager](/engine/story-manager.md).
