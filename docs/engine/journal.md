---
type: Subsystem
title: Quest journal
description: The Quests page of the vanilla quest_journal.swf driven from quest state - the
  measured AS2 list contract, the row model behind it, alias text substitution, the
  world-mode journal key, and the World > Quests & Journal sidebar surface.
tags: [engine, ui, menu, swf, quests, journal]
timestamp: 2026-08-03T00:00:00Z
---

# Quest journal

Milestone 13.5. The player-facing half of the quest system: what [quest
state](/engine/runtime-state.md) records is shown through the Quests page of Skyrim's own
`Interface\quest_journal.swf`, opened with a world-mode key and drivable end to end from
the sidebar.

This is not a movie bring-up. The same movie has been the in-game
[system menu](/engine/system-menu.md) since issue #231; its System page was driven then and
its Quests page was deferred, by name, in
[AS2 scope](/decisions/swf-as2-scope.md) as "the phase-4 contract that lands in the
milestone that owns its data". M13 owns it.

## Contents

- [Layers](#layers)
- [The row model](#the-row-model)
- [Measured Quests-page contract](#measured-quests-page-contract)
- [Alias text substitution](#alias-text-substitution)
- [Opening the journal](#opening-the-journal)
- [Verification](#verification)
- [The M13 gate](#the-m13-gate)
- [Limits / next](#limits--next)

## Layers

The subsystem is split so the row model works with no install, no renderer, and no movie.
Only the presentation layer needs any of those.

| Layer | File | Target |
|---|---|---|
| Row model (rows, selection, active/completed) | `opensky/Engine/UI/JournalMenuModel.swift` | app + CLI |
| Model builder over quest state | `opensky/Engine/UI/JournalMenuModelBuild.swift` | app + CLI |
| Alias text substitution | `opensky/Engine/UI/JournalAliasText.swift` | app + CLI |
| Measured movie contract | `opensky/Engine/UI/QuestJournalMovieBridge.swift` | app + CLI |
| List and text-field plumbing | `opensky/Engine/UI/QuestJournalMovieBridgeLists.swift` | app + CLI |
| Panel seam | `opensky/Engine/JournalControlProviding.swift` | app + CLI |
| Readout wording | `opensky/Engine/JournalReadout.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/App/GameViewControllerJournal.swift` and `...JournalSnapshot.swift` | app |
| Verification surface | `opensky/App/JournalPanelViewController.swift` and `opensky/App/Shell/Sections/Journal*.swift` | app |
| CLI probe | `openskycli/SWFQuestJournalCommand.swift` | CLI |

## The row model

`JournalMenuModel` is a `nonisolated struct`: an active list, a completed list, which of the
two is shown, and a row index whose nothing-selected value is `-1` — the movie's own
sentinel, so the model and the list agree without translation. Selection clamps and does
not wrap, matching the vanilla title list, whose `moveSelectionUp` and `moveSelectionDown`
stop at the ends.

Two record facts decide what a row says, and neither is a journal convention invented here:

- A quest is listed only when its DNAM type is not 0. Type 0 keeps a quest out of the
  journal entirely ([records](/formats/records.md)), which is why
  `QuestStore.journalQuests()` already filters it. Vanilla runs a large number of type-0
  controller quests at all times, so this filter is the difference between a usable page
  and a list of script hosts.
- An objective is shown only while one of its three display flags is set.
  `SetObjectiveDisplayed` exists to control exactly that; an untouched objective is not on
  the page. Where several flags are set, failed wins over completed, which wins over plain
  displayed.

A quest can be on both lists at once: `CompleteQuest()` flags completion and does not stop
the quest, which is what `QuestRuntimeState.completing()` records.

Log entries are the CNAM paragraph of every *reached* stage, in stage order, joined into the
page's description block. A stage carrying several QSDT entries is resolved by the file-order
default `Quest.Stage.primaryLogEntry`: the vanilla journal picks between them by condition,
and the page has no condition context to evaluate with.

### Which string table

Measured, not assumed. `openskycli swf quest-journal --text` resolves every field out of all
three tables and prints what each answered; on vanilla `Skyrim.esm` exactly one answers per
field:

| Field | Table |
|---|---|
| Quest `FULL` | `.strings` |
| Objective `NNAM` | `.strings` |
| Stage `CNAM` journal paragraph | `.dlstrings` |

That split follows the general rule [records](/formats/records.md) already states — short
names in `.strings`, long-form body text in `.dlstrings`. A plugin whose header does not say
localized carries its text inline and needs no table at all, which is the path
`JournalMenuModel.text` takes when no `LocalizedStrings` is supplied.

## Measured Quests-page contract

Everything below was measured with `openskycli swf action-run --movie quest_journal.swf`,
whose `--dump`, `--dump-class` and `--dump-proto` options print a node's own properties, a
registered class's prototype, and a node's whole prototype chain. Nothing is taken from
memory of the shipped game.

The page instance is `/QuestJournalFader/Menu_mc/QuestsFader/Page_mc`, class `QuestsPage`:

| Node | Class | Role |
|---|---|---|
| `TitleList_mc/List_mc` | `QuestTitleList` | the quest rows |
| `objectiveList` | `ObjectiveScrollingList` | the selected quest's objectives |
| `questTitleText` | edit text | the selected quest's name |
| `questDescriptionText` | edit text | its journal paragraphs |
| `questTitleEndpieces` | clip | decorative, one frame label per quest type |
| `NoQuestsText` | edit text | shown instead of a list when there is nothing |

`QuestJournalBase` publishes `PAGE_QUEST = 0`, `PAGE_STATS = 1`, `PAGE_SYSTEM = 2`; the
bridge reads that constant back rather than trusting its own number, and the acceptance test
asserts the two agree.

Both lists inherit one list base, whose prototype chain carries the contract:

- `EntriesA` holds the row array. `entryList` is its accessor property.
- `iSelectedIndex` holds the selection, `-1` for none.
- `InvalidateData()` rebuilds the visible entry clips from the array, and resets the
  selection to `-1` as it goes — so the selection is written *after* the rebuild, never
  before.
- `ClearList()` retires surplus entry clips. `InvalidateData` alone only touches as many
  clips as there are rows, so a list that ends up empty keeps showing the previous quest's
  first line until `ClearList` hides them. A cleared clip is hidden, not moved to a blank
  frame, which is why the frame readout below reports visible clips only.

Row fields are the names the movie's own action side carries, cross-checked by driving them:

| Row | Fields |
|---|---|
| Quest title | `text`, `formID`, `instance`, `type`, `completed`, `active` |
| Objective | `text`, `instance`, `completed`, `failed`, `active` |

`text` is what the list base's `SetEntryText` draws — the same field the System page's own
`SystemCategoriesList` fills for itself, which is how the name was confirmed inside this
movie rather than assumed across movies. `completed` and `failed` are confirmed by
behaviour: an objective entry clip stops on one of the frame labels `Normal`,
`NormalSelected`, `Completed`, `CompletedSelected`, `Failed`, `FailedSelected`, `Active`,
`ActiveSelected`, `None`, and `openskycli swf quest-journal --objective-state completed`
moves it from `Normal` to `Completed`, `--objective-state failed` to `Failed`. `Active`
marks the player's tracked objective, which OpenSky does not model, so it is published
false rather than guessed.

`questTitleEndpieces` carries one frame label per quest type — `Main`, `MagesGuild`,
`ThievesGuild`, `DarkBrotherhood`, `Companion`, `Favor`, `Daedric`, `Misc`, `CivilWar`,
`DLC01`, `DLC02` — so the type mapping is a rename rather than a number, and a type the
movie predates falls back to `Misc`.

### Coverage, honestly

The driven page reports **0 faults, 0 unimplemented opcodes and 0 unhandled invokes of 52**,
at 1052 display nodes and 506 draws. Bring-up changes 375,575 pixels over an empty frame,
publishing the quest changes 74,116 more, and switching to the System page and back changes
53,658.

81 distinct API names remain unresolved, none of which stops the page from carrying its
data. The ones that shape what the page looks like:

| Name | Hits | Effect |
|---|---|---|
| `_listeners` | 327 | CLIK event dispatch; nothing subscribes |
| `invalidationIntervalID` | 270 | deferred re-layout timer never armed |
| `textField` | 167 | entry clips cannot draw their own row text |
| `height`, `width` | 77 each | fields do not autosize, so long text can overlap |
| `statusIcon` | 32 | objective status icon is not drawn |

`textField` is the reason a published row is read back off `EntriesA` rather than off the
clip that should show it: the entry clips have no text field to fill. `height` and `width`
are why the description block and the objective list overlap on a long journal paragraph in
a captured frame — the fields keep their authored size instead of growing.

## Alias text substitution

Journal text is authored with placeholders naming one of the quest's own aliases, which the
engine replaces with the display name of whatever filled it (issue #183 fills them). The
syntax is measured: `openskycli swf quest-journal --text` prints resolved vanilla strings and
`<Alias=QuestNameLocation>` is one of them verbatim. The Creation Kit documents the same
family under [text replacement](https://ck.uesp.net/wiki/Text_Replacement):
`<Alias=AliasName>` is "the name of the object filling the alias". A dotted qualifier —
`<Alias.ShortName=…>` — selects which name of that object is wanted; OpenSky has one name
per reference, so the qualifier is parsed only so a tag carrying one is still recognized.

`QuestAliasNaming` scans rather than uses a regular expression, so an unterminated `<` costs
nothing. A tag that cannot be resolved survives **exactly as written**: a visible
`<Alias=Prisoner>` says "this fill is missing", where deleting it would leave a sentence with
a hole in it and nothing to point at.

The app names an alias through the loaded cell — alias reference key, resident reference
entry, that reference's `PlacedInteraction.name`. A fill outside the loaded area therefore
leaves its tag standing. The M13 target quest `MGRArniel01` carries no tags at all, so this
path is machinery for the corpus rather than for the gate.

## Opening the journal

`J` in world mode is the first key that opens a menu from gameplay. `GameMetalView` maps it
to `onJournalKey`, which the controller wires to the same `openJournal()` the sidebar's
`Open journal` button calls — an accelerator for a listed control, not a behaviour of its
own, which is what keeps it inside the [app-ui](/tools/app-ui.md) rule against unadvertised
keystrokes. `F`, `G` and `Esc` are unchanged.

Opening pushes the menu identifier `Journal` onto `MenuModeController`, which is what pauses
world simulation, then brings the movie up and switches it to `PAGE_QUEST`. The lifecycle
calls — `SetPlatform`, `InitExtensions`, `ShowMenu`, `CloseMenu` — belong to the movie as a
whole and stay with `SystemMenuMovieBridge`; only the page switch and the data are the
journal's. That also means the journal and the system menu cannot be open at once: they are
the same movie on the renderer's single SWF layer.

Input goes to the movie first, through the same batched renderer seam the system menu uses,
so the tab strip across the top still switches to Stats and System. Whatever the movie did
to the title list's `iSelectedIndex` is read back into the model and republished, which is
what makes the objectives and the description follow the highlighted quest. `Esc` closes.
With no movie loaded, Up and Down still move the model's own selection, so the panel works on
a session with no install.

## Verification

Sidebar path: `World > Quests & Journal`, sections `Quests`, `Quest Controls`, and `Page`.

| Control | Accessibility id |
|---|---|
| Quest picker | `JournalQuestControl` |
| Start / Stop | `JournalStartQuestControl`, `JournalStopQuestControl` |
| Stage field / Set stage | `JournalStageControl`, `JournalSetStageControl` |
| Objective field / Show / Hide | `JournalObjectiveControl`, `JournalShowObjectiveControl`, `JournalHideObjectiveControl` |
| Open / Close | `JournalOpenControl`, `JournalCloseControl` |
| Up / Down / Activate | `JournalUpControl`, `JournalDownControl`, `JournalActivateControl` |
| Show completed quests | `JournalShowCompletedControl` |
| Readouts | `JournalQuestsStatsLabel`, `JournalSelectionStatsLabel`, `JournalAliasStatsLabel`, `JournalControlsStatsLabel`, `JournalPageStatsLabel` |

The Quests readout lists every running or completed quest with its type, running state and
current stage, and states the per-objective display state of the selected one. The selection
readout shows that quest as the page would: its declared stages, the objectives on the page,
and the journal paragraphs of its reached stages. The alias readout is the `World > Scripts`
alias table for the same quest, rendered by the same `ScriptsReadout.questAliasText`, so the
two surfaces cannot describe one #183 fill table differently. The Page readout states the
menu stack, the rows and selection the page holds, the movie's own title field, the
objective entry frames, and the three bring-up tallies — the tallies are printed even at
zero, because "0 faults" is the gate passing and hiding it would look like a missing readout.

An open journal counts as the destination's override, so the sidebar dot shows a paused
world and Reset closes it. Starting or advancing a quest deliberately does not: that is
world state, not a panel setting, and "Reset all" must not undo it.

Nothing in the movie path throws out of a control action. A missing install, an undecodable
movie, or a `QuestError` from a dev control becomes an explanatory string in a readout.

Tests: `JournalMenuModelTests` (row set, row content, selection), `JournalAliasTextTests`
(tag syntax and the leave-as-written rule), `QuestJournalMovieBridgeTests` (the list contract
over a synthetic runtime), `JournalPanelTests` (control ids, readouts, provider round-trip),
`DestinationRegistryJournalTests` (registry order, pinned ids, override policy), plus
`JournalAcceptanceRealDataTests` — the env-gated gate against the user's install. It opens
the journal, asserts the target quest's title, objective and journal text on the movie's own
fields, checks the objective entry frame, switches to System and back, and asserts the
fault, opcode and invoke tallies. Its PNGs and report go to ignored `logs/`.

### Acceptance record

```text
Milestone: M13.5
Sidebar path: World > Quests & Journal > Page
Destination id: Destination-journal
Controls exercised: JournalQuestControl, JournalStartQuestControl, JournalSetStageControl,
  JournalShowObjectiveControl, JournalOpenControl, JournalCloseControl,
  JournalShowCompletedControl
Readout: JournalPageStatsLabel
Deterministic tests: JournalPanelTests, DestinationRegistryJournalTests,
  QuestJournalMovieBridgeTests, JournalMenuModelTests, JournalAcceptanceRealDataTests
Local A/B (optional, never committed): logs/journal-published.png
```

## The M13 gate

M13.5 proved the page. The milestone gate (issue #185) proves the loop that fills it: a
quest running, a real world event driving `SetStage` through script code, the stage fragment
executing and mutating `WorldStateStore`, the alias resolving, the page growing, and a
mid-quest save resuming into a fresh engine at the same stage.

Five suites, each answering a different question.

`M13AcceptanceTests` is the deterministic half, over one synthetic journal-visible quest
built in code (`M13AcceptanceChain`, `M13AcceptanceFixture`). It is the only place the whole
chain is real end to end, because a synthetic world can carry a lever the gate is allowed to
pull:

```text
CellStreamer raycast -> InteractionEvent -> PapyrusWorldStateBridge -> OnActivate
-> Quest.SetStage native -> QuestRuntime -> stage fragment
-> Quest.SetObjectiveDisplayed native -> QuestRuntime -> JournalMenuModel
```

The one place it enters below the app is the use-key press,
`CellStreamer.update(cameraPosition:interactionRay:activate:)` — the call the render loop
makes every frame — because everything above it is key handling and a draw callback. That is
the same entry point `M11ScriptedWorldChain` uses. The lever reaches its quest through an
automatic VMAD property, which is why the gate starts the quest *before* attaching the
lever's cell: an object property can only bind to a handle that already exists, and quests
come up at session wire-up while cells stream in afterwards. The run ends with a real
`OpenSkySaveStore` slot restored into a brand-new store, runtime and quest layer, asserting
snapshot equality including the generated-key allocator position.

`M13AcceptancePanelTests` runs the sidebar surface as one destination: the real
`AppSidebarModel`, the registry factory, every readout read back by accessibility id, the
quest transport, the page controls, and the override policy — an open journal is the
override, a running quest is not, and `Reset all` closes the page without undoing a single
quest mutation.

`M13AcceptanceRealDataTests` walks `MGRArniel01` end to end against the user's install and
pins the tallies. `M13AcceptanceRenderTests` renders the page before and after a stage
advance and asserts both the changed-pixel delta and that the advanced page is byte-identical
to a page walked straight to that stage. `M13AcceptanceBudgetTests` holds quest work to the
budgets that already exist: stage fragments go through the same per-tick FIFO every other
script event uses, so `PapyrusTickBudget` bounds them unchanged, and quest conditions execute
no bytecode at all.

### What the real quest run reports

Numbers from `make realtest`, 2026-08-03, against `Skyrim.esm`. The report goes to ignored
`logs/m13-acceptance.log` and carries counts and editor IDs only.

| Measure | Value |
|---|---|
| Quest | `MGRArniel01`, mages guild, 2 stages, 1 objective, 1 alias, 2 fragments |
| Declared conditions | 0 |
| Stages reached / current | 2 / 200, completed |
| Quest script instances / alias instances | 1 / 0 |
| Fragments queued | 2 |
| Aliases filled | 1 |
| Native calls / unimplemented | 1 / 0 |
| Faults | 1 (`typeMismatch`) |
| Binding skips | 5 (`unresolvedReference`) |
| Journal rows / objective rows / paragraphs | 1 / 1 / 2 |
| Changed pixels on the stage advance | 14,917 |

The one fault is worth stating plainly rather than rounding to zero. The real-data session
loads no cell, so the five object properties on the quest's fragment script resolve to no
live handle and keep their compiler defaults; calling a method on one of them is a call on
`None`, which faults at the first instruction of the second fragment. It is the absence of a
world, not a quest bug — the synthetic gate, which does attach a cell, faults zero times.

The stages of the real quest are set from outside rather than by a dialogue INFO. That is
this milestone's scope decision: `MGRArniel01` advances through dialogue, no quest on the
issue-#181 shortlist progresses without it, and a minimal INFO slice would be a dialogue
system wearing a quest gate's name. The synthetic half is what proves a *world event* can
drive the same path, and dialogue stays a later milestone.

### Acceptance record

```text
Milestone: M13
Sidebar path: World > Quests & Journal > Quests, > Quest Controls, > Page
Destination id: Destination-journal
Controls exercised: JournalQuestControl, JournalStartQuestControl, JournalStopQuestControl,
  JournalStageControl, JournalSetStageControl, JournalObjectiveControl,
  JournalShowObjectiveControl, JournalHideObjectiveControl, JournalOpenControl,
  JournalCloseControl, JournalUpControl, JournalDownControl, JournalActivateControl,
  JournalShowCompletedControl
Readout: JournalPageStatsLabel
Deterministic tests: M13AcceptanceTests, M13AcceptancePanelTests, M13AcceptanceBudgetTests,
  M13AcceptanceRealDataTests, M13AcceptanceRenderTests, JournalPanelTests,
  DestinationRegistryJournalTests
Local A/B (optional, never committed): logs/m13-journal-advanced.png
```

## Limits / next

- The Stats page keeps its current behaviour; its data is out of scope here.
- HUD compass and map quest markers are deferred. `HUDMovieBridge` already carries the
  marker cases, and nothing publishes quest targets into them.
- The page lists every running journal quest rather than splitting misc and side quests into
  the vanilla sub-categories. `QuestsPage` carries `bHasMiscQuests` and
  `IsViewingMiscObjectives` for that split; neither is driven.
- The tracked-objective `Active` frame is never selected, because no quest is tracked.
- The quest text of a quest the runtime does not track is not shown at all — the page is a
  view of runtime state, not of the plugin index.
- `itemcard.swf` and controller input are untouched.
