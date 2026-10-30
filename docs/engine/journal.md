---
type: Subsystem
title: Quest journal
description: The Quests and Stats pages of the vanilla quest_journal.swf driven from quest
  state - which quests and objectives show, tracked quests, the misc row, the measured AS2
  contract, the misc stats, alias text, and the journal key.
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

A quest can be on both lists. `CompleteQuest()` marks a quest complete but does not stop it. A
quest a Fail Quest stage item failed leaves the active list and is listed with the completed ones,
marked failed ([quest state](/engine/quest-state.md#stage-items)).

Running misc quests (type 6) share one row at the end of the active list, as in the game. Its
objectives are the open objectives of all of them, and each keeps its own quest. The row has
the shape the movie's own `onQuestsDataComplete` builds: text `$MISCELLANEOUS`, FormID 0, and
type 0. Completed misc quests stay separate rows on the completed list; OpenSky did not confirm
how the game lists them.

### Tracked quests

A tracked quest is "active" in the movie's words. Its targets show on the HUD compass and on
the [map](/engine/world-map.md#quest-targets), and its open objectives use the `Active` frame.
A journal quest is tracked when it first shows an objective, as a new quest is in the game. The
player can untrack it, and it then stays untracked. Tracking is saved in the `QTRK` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

The description is the newest log entry only: "Only the most recent log entry is displayed"
([Quest Stages Tab](https://ck.uesp.net/wiki/Quest_Stages_Tab)). It is the `CNAM` text of the
items that passed when the last stage was set, one paragraph each. The quest state stores which
items they were, so the page needs no condition context. A state with no stored entry, such as
one from an imported save, shows the highest reached stage that has text.

### Which string table

Measured with `openskycli menu quest-journal --text`, which reads each field from all three
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
| Objective | `text`, `formID`, `instance`, `completed`, `failed`, `active`, `questTargetID` |

`text` is what the list base's `SetEntryText` draws. The System page's `SystemCategoriesList`
fills the same field in this movie, which confirms the name.

An objective entry clip stops on one of these frame labels: `Normal`, `NormalSelected`,
`Completed`, `CompletedSelected`, `Failed`, `FailedSelected`, `Active`, `ActiveSelected`,
`None`. With `openskycli menu quest-journal --objective-state completed` it moves from `Normal` to
`Completed`, and with `failed` to `Failed`. That confirms `completed` and `failed`. `active`
marks an open objective of a tracked quest.

`questTitleEndpieces` has one frame label per quest type. The movie's `onQuestHighlight` picks
the label from its own table, indexed by the row's `type`, which is the QUST `DNAM` type:

| Type | Frame |
| --- | --- |
| 0 none, 8 side quest | `Misc` |
| 1 main | `Main` |
| 2, 3, 4, 5 | `MagesGuild`, `ThievesGuild`, `DarkBrotherhood`, `Companion` |
| 6 miscellaneous | `Favor` |
| 7 daedric | `Daedric` |
| 9 civil war | `CivilWar` |
| 10, 11 | `DLC01`, `DLC02` |

A type the movie does not know uses `Misc`.

The page also has two flags and two calls to the engine, read with `openskycli swf
action-list --movie quest_journal.swf`:

- `bHasMiscQuests` says a misc row ends the list. `bAllowShowOnMap` enables the "Show on map"
  button. OpenSky sets both when it publishes the rows.
- `ToggleQuestActiveStatus(formID, instance)` asks to flip tracking of the selected quest. The
  answer is the new state, which the movie writes into the row's `active`.
- "Show on map" closes the menu and calls `ShowTargetOnMap(questTargetID)` with the selected
  objective's `questTargetID`. A row without that field offers no button. OpenSky sets it on
  open objectives that declare a `QSTA` target: the quest FormID times 65536 plus the
  objective index, which an AS2 number holds exactly. The map then opens on that target.

### Coverage

The driven page has 0 faults, 0 unimplemented opcodes, and 0 unhandled invokes of 52, at 1052
display nodes. None of the unresolved names stops the page from showing its data. Without
`statusIcon`, the objective status icon is not drawn.

`_listeners`, `invalidationIntervalID`, `textField`, `width`, and `height` are not gaps. The page
reads them before it sets them, or tests them against `null`, and Flash answers `undefined` too
([AS2 input](/engine/as2-input.md)). A row is read back from `EntriesA`, not from the clip. On a long
journal text the description and the objective list overlap; the cause is not known yet.

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

`J` in world mode opens the journal.

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

## Stats page

The Stats page is `/QuestJournalFader/Menu_mc/StatsFader/Page_mc`. On load it builds six
categories: General, Quest, Combat, Magic, Crafting, and Crime. When the page first opens and
its `bUpdated` is false, it calls `updateStats` with the callback `PopulateStatsList`. That
function reads its arguments in fours: the stat name without its `$`, the value, the category
index, and one value it does not read. It appends, so OpenSky calls it once per open, right
after the movie starts, and sets `bUpdated` so the page does not ask again.

The stats are the misc stats `Game.QueryStat` reads. The names come from the Creation Kit page
<https://ck.uesp.net/wiki/QueryStat_-_Game>, which lists 104 of them. The page does not give
categories. The list runs in the six groups' order, so OpenSky splits it there: General ends at
"Mauls", Quest at "Questlines Completed", Combat at "Bunnies Slaughtered", Magic at "Souls
Trapped", Crafting at "Wings Plucked", and Crime holds the rest. The page leaves out the
"Favorite" stats, which are text, and the ten per-hold bounties. Both are OpenSky's reading.

The stats are saved in the `MSTS` chunk. OpenSky counts these:

| Stat | Counted when |
| --- | --- |
| Quests Completed, and the quest type's own stat | A journal quest is completed the first time |
| Misc Objectives Completed | An objective of a misc quest is completed the first time |
| Locations Discovered | A map marker is discovered |
| Bribes, Intimidations, Persuasions | The player wins a speech check |

`Game.IncrementStat` and `Game.QueryStat` change and read any of them. The quest type's stat is
the one its name gives: main quests count "Main Quests Completed", Dawnguard quests (type 10)
"Dawnguard Quests Completed", and so on. Every other stat stays 0 until a script counts it.

## HUD notices

When a quest starts, completes, or fails, the HUD shows its title over `sHUDStarted`,
`sHUDCompleted`, or `sHUDFailed` through the movie's `ShowNotification` call. Started plays
`UIQuestNew`, and completed plays `UIQuestComplete`. A new objective shows as one line with
`UIObjectiveNew`. A load shows nothing for the quests the save already had. Which change shows
which text is OpenSky's reading. `openskycli game state hud` lists the shown notices.

Journal text fills `<Alias=Name>` tags and the pronoun subtags of the Creation Kit wiki
[Text Replacement](https://ck.uesp.net/wiki/Text_Replacement): `Pronoun`, `PronounObj`,
`PronounPos`, `PronounPosObj`, `PronounRef`, and `PronounInt`, each from its `sPronoun` setting.
A `Cap` suffix capitalises the word. `<Alias=Player>` works without a `Player` alias.

## Not done yet

- A quest the runtime does not track is not shown. The page shows runtime state, not the plugin.
- Vanilla quests move forward through dialogue. The page shows what the stage says, whatever
  set it.
- The Stats page counts only the stats in the table above.
