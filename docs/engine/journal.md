---
type: Subsystem
title: Quest journal
description: The Quests page of the vanilla quest_journal.swf driven from quest state - which
  quests and objectives show, the measured AS2 list contract, alias text, and the journal key.
tags: [engine, ui, menu, swf, quests, journal]
---

# Quest journal

The journal shows [quest state](/engine/runtime-state.md) on the Quests page of Skyrim's own
`Interface\quest_journal.swf`. The same movie is the [system menu](/engine/system-menu.md). That
page covers the movie's start-up. This page covers the Quests page and its data.

## What a row shows

The row model has an active list, a completed list, which of the two is shown, and a selected
row. "Nothing selected" is `-1`, the movie's own value, so the model and the list agree without
translation. The selection stops at the ends and does not wrap, like the vanilla title list,
whose `moveSelectionUp` and `moveSelectionDown` stop there.

Two record facts decide what shows:

- A quest is listed only when its `DNAM` type is not 0. Type 0 keeps a quest out of the journal
  ([quest records](/formats/quest-records.md)). Vanilla always runs many type-0 controller
  quests, so without this filter the page would be a list of script hosts.
- An objective shows only while one of its three display flags is set. `SetObjectiveDisplayed`
  controls exactly that. If several flags are set, failed wins over completed, and completed
  wins over displayed.

A quest can be on both lists. `CompleteQuest()` marks a quest complete but does not stop it.

The log entries are the `CNAM` text of every reached stage, in stage order, joined into the
description. When a stage has several `QSDT` entries, the first in file order is used. The
vanilla journal chooses by condition, but the page has no condition context.

### Which string table

Measured with `openskycli swf quest-journal --text`, which reads each field from all three
tables. On vanilla `Skyrim.esm`, exactly one table answers per field:

| Field | Table |
| --- | --- |
| Quest `FULL` | `.strings` |
| Objective `NNAM` | `.strings` |
| Stage `CNAM` journal text | `.dlstrings` |

This follows the general rule: short names in `.strings`, long text in `.dlstrings`
([strings](/formats/strings.md)). A plugin that is not localized has its text inline.

## The measured page contract

Measured with `openskycli swf action-run --movie quest_journal.swf`. Its `--dump`, `--dump-class`,
and `--dump-proto` options print a node's properties, a class's prototype, and a node's whole
prototype chain.

The page is `/QuestJournalFader/Menu_mc/QuestsFader/Page_mc`, class `QuestsPage`:

| Node | Class | Role |
| --- | --- | --- |
| `TitleList_mc/List_mc` | `QuestTitleList` | The quest rows |
| `objectiveList` | `ObjectiveScrollingList` | The chosen quest's objectives |
| `questTitleText` | edit text | The chosen quest's name |
| `questDescriptionText` | edit text | Its journal text |
| `questTitleEndpieces` | clip | Decoration, one frame label per quest type |
| `NoQuestsText` | edit text | Shown instead of a list when there are no quests |

`QuestJournalBase` defines `PAGE_QUEST = 0`, `PAGE_STATS = 1`, `PAGE_SYSTEM = 2`. OpenSky reads
the constant from the movie instead of using its own number.

Both lists share one list base. Its prototype chain holds the contract:

- `EntriesA` holds the rows. `entryList` is its accessor.
- `iSelectedIndex` holds the selection, `-1` for none.
- `InvalidateData()` rebuilds the visible entry clips from the rows, and resets the selection to
  `-1`. So the selection is written after the rebuild, never before.
- `ClearList()` hides extra entry clips. `InvalidateData` only touches as many clips as there are
  rows. So a list that becomes empty keeps showing the old quest's first line until `ClearList`
  hides it.

Row fields are the names the movie's own code uses, checked by driving them:

| Row | Fields |
| --- | --- |
| Quest title | `text`, `formID`, `instance`, `type`, `completed`, `active` |
| Objective | `text`, `instance`, `completed`, `failed`, `active` |

`text` is what the list base's `SetEntryText` draws. The System page's `SystemCategoriesList`
fills the same field in this movie, which confirms the name.

An objective entry clip stops on one of these frame labels: `Normal`, `NormalSelected`,
`Completed`, `CompletedSelected`, `Failed`, `FailedSelected`, `Active`, `ActiveSelected`,
`None`. With `openskycli swf quest-journal --objective-state completed` it moves from `Normal` to
`Completed`, and with `failed` to `Failed`. That confirms `completed` and `failed`. `Active`
marks the tracked objective. OpenSky does not track objectives, so it is always false.

`questTitleEndpieces` has one frame label per quest type: `Main`, `MagesGuild`, `ThievesGuild`,
`DarkBrotherhood`, `Companion`, `Favor`, `Daedric`, `Misc`, `CivilWar`, `DLC01`, `DLC02`. So the
type maps by name. A type the movie does not know uses `Misc`.

### Coverage

The driven page has 0 faults, 0 unimplemented opcodes, and 0 unhandled invokes of 52, at 1052
display nodes. 81 API names stay unresolved. None stops the page from showing its data. These
change how it looks:

| Name | Hits | Effect |
| --- | --- | --- |
| `_listeners` | 327 | CLIK event dispatch. Nothing subscribes |
| `invalidationIntervalID` | 270 | The delayed re-layout timer never starts |
| `textField` | 167 | Entry clips cannot draw their own row text |
| `height`, `width` | 77 each | Fields do not grow with their text, so long text can overlap |
| `statusIcon` | 32 | The objective status icon is not drawn |

Because of `textField`, a row is read back from `EntriesA`, not from the clip. Because of
`height` and `width`, the description and the objective list overlap on a long journal text.

## Alias text

Journal text has placeholders that name one of the quest's aliases. The engine replaces each
with the name of whatever fills the alias. The form is measured: `<Alias=QuestNameLocation>`
appears verbatim in the resolved vanilla strings. The Creation Kit documents the same family
under [text replacement](https://ck.uesp.net/wiki/Text_Replacement): `<Alias=AliasName>` is
"the name of the object filling the alias".

A dotted qualifier, like `<Alias.ShortName=...>`, picks which name of the object to use. OpenSky
has one name per reference, so the qualifier is only parsed, so that such a tag is still found.

The text is scanned, not matched with a regular expression, so an unclosed `<` costs nothing. A
tag that cannot be resolved stays exactly as written. A visible `<Alias=Prisoner>` says "this
fill is missing". Deleting it would leave a sentence with a hole and nothing to point at.

The app names an alias through the loaded cells: the alias's reference, then that reference's
name. So a fill outside the loaded area keeps its tag.

## Opening the journal

`J` in world mode opens the journal. It is the same call as the Open journal button in the
sidebar, so it is a shortcut for a listed control ([main-app UI](/tools/app-ui.md)).

Opening pushes the menu `Journal`, which pauses the world, then starts the movie and switches to
`PAGE_QUEST`. The movie's life cycle calls (`SetPlatform`, `InitExtensions`, `ShowMenu`,
`CloseMenu`) belong to the whole movie and stay with the system menu. Only the page switch and
the data belong to the journal. The journal and the system menu cannot be open together, because
they are the same movie on the renderer's one SWF layer.

Input goes to the movie first, so the tabs across the top still switch to Stats and System. The
movie owns the selection: OpenSky reads the title list's `iSelectedIndex` back into the model and
publishes again, so the objectives and description follow the highlighted quest. `Esc` closes.
With no movie loaded, Up and Down still move the model's selection.

## How a stage reaches the page

The whole path from a world event to the page:

```text
use key -> interaction event -> Papyrus OnActivate
-> Quest.SetStage -> quest runtime -> stage fragment
-> Quest.SetObjectiveDisplayed -> quest runtime -> journal rows
```

Stage fragments run through the same per-tick queue as every other script event, so the Papyrus
tick budget limits them. Quest conditions run no bytecode.

A script object property can bind only to a handle that already exists. Quests start when the
session is set up, and cells stream in later. So a lever in a cell can reach its quest through an
automatic `VMAD` property, but only if the quest started first.

## Not done yet

- The Stats page has no data.
- Quest markers on the HUD compass and the map.
- Misc and side quests are not split into the vanilla groups. `QuestsPage` has
  `bHasMiscQuests` and `IsViewingMiscObjectives` for that. Neither is driven.
- The tracked objective's `Active` frame is never used.
- A quest the runtime does not track is not shown. The page shows runtime state, not the plugin.
- Vanilla quests move forward through dialogue. The page shows what the stage says, whatever
  set it.

## Controls

World > Quests & Journal has three sections:

- Quests: every running or completed quest with its type, state, and stage, and the display state
  of each objective of the chosen quest.
- Quest controls: choose a quest, start, stop, set a stage, show or hide an objective. The alias
  table is the same text as in World > Scripts, so the two cannot disagree.
- Page: open, close, up, down, activate, and show completed quests. The readout shows the menu
  stack, the rows and selection, the movie's title field, the objective frames, and the fault,
  opcode, and invoke counts, even at zero.

An open journal counts as a change on the destination, so Reset closes it. Starting or advancing
a quest does not count. That is world state, and Reset all must not undo it.

No control throws. A missing install, a movie that does not decode, or a quest error becomes a
message in a readout.
