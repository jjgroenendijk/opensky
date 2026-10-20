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

In the game a quest's scripts exist whether the quest runs or not, so any script can read a
stopped quest's properties. Source: the Creation Kit wiki page "OnInit", which says a quest script
initializes when the game first loads. OpenSky attaches a stopped quest's scripts when a script
first casts the quest to one of its script types. Hearthfire's adoption script reads the
`HousePurchase` quest this way before the player owns a house.

## The Quest natives

`IsRunning`, `IsCompleted`, `GetCurrentStageID`, `IsStageDone`, `Start`, `Stop`, `CompleteQuest`,
`SetCurrentStageID`, `SetObjectiveDisplayed`, `SetObjectiveCompleted`, `SetObjectiveFailed`,
`IsObjectiveDisplayed`, `IsObjectiveCompleted`, `IsObjectiveFailed`, `CompleteAllObjectives`,
`FailAllObjectives`, and `IsStopped` are registered, plus `GetStage`, `GetStageDone`, and
`SetStage`, the wrapper names shipped `Quest.psc` declares around three of them. Each makes one call
into the quest runtime, so the stage and objective rules live in one place.

`CompleteAllObjectives` completes the objectives the quest has shown. An objective never shown has
no journal row, so leaving it out changes nothing the player sees. `FailAllObjectives` fails every
shown objective, completed ones too: "This will also flag completed objectives as failed"
([FailAllObjectives - Quest](https://ck.uesp.net/wiki/FailAllObjectives_-_Quest)).

`IsStopped` is true whenever the quest is not running, because a stop finishes at once in OpenSky.

A refused change becomes a native failure, and the call returns its declared default. For
`SetStage` that is false, which matches the documented "returns false and the stage is unchanged".

Absent on purpose, and left in the unimplemented tally: `Reset`, `IsStarting`, `IsStopping`,
`GetAlias`, and `GetAliasedRef`. They need more alias support or a latent window OpenSky does not
have. `SetActive` and `IsActive` keep a flag in the
[script state](/engine/papyrus-script-state.md); no journal reads it yet.

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

Each fragment belongs to one log entry (item) of its stage. "The script fragments will be run for
all entries where the conditions pass" ([Quest Stages Tab](https://ck.uesp.net/wiki/Quest_Stages_Tab)),
with the player as Subject. For example, `MQ101` stage 0 has five entries keyed on one global's
value; value 0 is the normal start, and the others are debug starts, so one passes. A session
without a condition evaluator runs the items with no conditions, or the first one. The same items
write the log entry and apply Complete Quest and Fail Quest ([quest state](/engine/quest-state.md#stage-items)).

All scripts on one quest are one object in the game. Here each script is its own instance, so a cast
from one to another, such as `self as MQ101QuestScript` in a fragment, finds the sibling instance on
the same form ([Papyrus VM](/engine/papyrus-vm.md)).

A fragment naming a script the quest has no instance of is counted as
`missingQuestFragmentInstance`. A function the script does not define is counted as
`undefinedEventFunction`. Neither is a fault.

## Aliases in scripts

A `VMAD` object property whose alias word is not -1 names an alias slot on the quest its form ID
identifies. It binds to an alias slot handle: one handle per quest and alias ID, filled or not.
The binding still counts an empty alias as an unfilled quest alias, for the readout.

A slot handle stands for the alias, and a call on it goes one of three ways:

- The declared type is the alias script, for example `myAliasScript Property Helper`. The call
  reaches that script's instance on the filled reference.
- The declared type is `ReferenceAlias` or `LocationAlias`. The call reaches the alias natives.
- The call needs a reference, for example `Helper.GetRef().Disable()`. The slot resolves to the
  reference that fills it now. An empty slot resolves to nothing, and the native fails.

`GetRef` and `GetReference` on a slot return the filled reference, or `None` when the alias is
empty. `ForceRefTo(ObjectReference)` and `Clear()` change one alias through the quest runtime.
Then the alias scripts on the old reference retire, and the quest attaches fresh ones on the new
reference. `LocationAlias.GetLocation`, `ForceLocationTo`, and `Clear` work on location aliases. A
quest the load order does not define, or an alias ID the quest does not define, is refused.

Inside an alias script, `Self` is the alias script's own handle. The alias natives accept it too,
so an alias script can call `Clear()` on itself.

The world runtime holds the current alias answers, and the session refreshes them after every
fill, force, or stop. So binding stays nonisolated and never calls back into the main-actor
session.

Alias script sections become instances when the quest attaches. Unlike other quest scripts they are
keyed by the filled reference, not by the quest. A `ReferenceAlias` script runs on the reference in
its alias, so this gives it the same `Self` and the same handle as the reference's own scripts. It
also stops two aliases with the same script name from sharing one instance. The runtime remembers
which quest owns which alias instances, so `Stop` retires exactly its own.

An empty alias gets no instance. An alias script section naming another quest is skipped, because
filling that alias needs the other quest's table. A save restores the fills with the world state,
and the session attaches running quests' scripts afterwards, so alias scripts come back bound to the
restored fills.

A quest's scripts load in the background, so an alias script can attach after its reference's
cell loaded. Such an alias script gets the `OnCellLoad` of each cell that loaded after its quest
started, once. A start-game quest counts as started before every cell. A cell that was already
loaded when the quest started sends nothing, as in the game. New Game starts `MQ101`, then the
opening cells load, and the cart horses wait for this event before the opening can move on.

## Where OpenSky differs

- `SetStage` and `Start` are latent in the game: they wait for the quest to start and its fragments
  to finish. OpenSky writes the state, queues the fragments, and returns. `Start` sets the start-up
  stage before it returns, so the stage and its objectives are there at once
  ([Start - Quest](https://ck.uesp.net/wiki/Start_-_Quest)). The fragments run on a later tick, so
  a script that reads state right after sees the value before its fragment ran.
- A fragment runs only on the change into a stage. Setting a stage already reached runs nothing,
  because setting a stage is idempotent. The `QUST` allow-repeated-stages flag is decoded and not
  used: nothing open says what the game does with it, and a guess would run fragments twice.
- A shut-down stage stops the quest but does not retire its instances, so the fragment that stage
  queued still runs. Only `Stop` retires them.
- Quests start from the `.seq` start-game pass, from `Start`, from a start-up stage, or from the
  [story manager](/engine/story-manager.md).
