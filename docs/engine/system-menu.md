---
type: Subsystem
title: System menu
description: The pause menu - its toolkit-free selector, how it pauses the world through the
  menu stack, its two settings, and the vanilla quest_journal.swf movie behind it.
tags: [engine, ui, menu, swf, settings]
---

# System menu

The system menu is the pause menu: Resume, Quicksave, Save, Load, Installed Content, Settings,
Controls, Help, and Quit, the rows of the vanilla System page. It was the first real consumer of
[menu mode](/engine/menu-mode.md) input. It can also show itself through the vanilla
`Interface\quest_journal.swf` movie.

The menu works with no install, no renderer, and no movie. Only the movie layer needs them.

## Selector

The selector is a plain value: the rows, the highlighted row, the last result, and the open
page. It knows nothing about the renderer, the movie, or AppKit.

Activating a row returns a result instead of doing the action:

| Row | Result | Who acts |
| --- | --- | --- |
| Resume | resume | The selector closes; the host closes the menu |
| Quicksave | quicksave | The host writes the `Quicksave` slot; the menu stays open |
| Every other row | show page | The page model takes the keys |

Each page is its own model: the Settings page steps the [player settings](/engine/settings.md),
the Save and Load pages list saves newest first and ask before an overwrite or a delete, the
Controls page waits for the next key and rebinds it ([control map](/formats/controlmap.md)),
Help and Installed Content list topics and show the text of one, and Quit asks Main Menu,
Desktop, or Cancel, with Cancel selected. Main Menu opens the [title menu](/engine/main-menu.md).
Cancel on a page returns to the row list.

Up and down wrap around, as the vanilla list does.
Left and right are accepted and ignored, so they count as handled and do not reach the world.
Cancel means Resume, because the vanilla pause menu closes on the key that opened it.

## Pausing the world

Opening the menu pushes `SystemMenu` onto the menu stack, and makes the game view the input
consumer. That push is what pauses the world. The menu does not own the pause. It gets it by being
on the stack.

The control map's Pause key, Esc, opens the menu. While the mouse is captured, the first Esc
releases it instead. Opening it may write a pause autosave. `J` opens the [quest
journal](/engine/journal.md).

## Settings

- Game data folder: shown, not changed here. Change it in the Settings window (Cmd+,).
- Master volume: the value in the player settings store, which the audio engine follows.

## The vanilla movie

`startmenu.swf` is the title screen, not the pause menu. Its rows are Continue, New, Load,
Creations, Mods, Credits, Quit, and Help, and it has no `$SETTINGS` string. It is still useful for
testing the [ActionScript runtime](/engine/as2-runtime.md).

The pause menu is `quest_journal.swf`. Its `QuestJournalBase` has three pages: Quests, General
Stats, and System. The [quest journal](/engine/journal.md) drives the Quests page with the same
movie and setup, so the two menus cannot be open at once. The System page is `PageArray[2]`, and
the movie builds its own rows:

`$QUICKSAVE`, `$SAVE`, `$LOAD`, `$INSTALLED CONTENT`, `$SETTINGS`, `$CONTROLS`, `$HELP`, `$QUIT`.

Settings opens the movie's own panel with `$Gameplay`, `$Display`, and `$Audio`. Quit shows
`$Main Menu` and `$Desktop`. The game resolves each token through the
[translation map](/formats/translation-strings.md). The pages and transitions are the movie's own.

Start-up order:

1. Before `start()`, install the handlers the movie calls out to: trace, sound, feature queries,
   and player info.
2. Call `SetPlatform(0)`, `InitExtensions`, `ShowMenu`, and `SwitchPageToFront(2, true)`.
3. The game normally sets `TopmostPage`, `iCurrentTab`, and focus through tab buttons backed by
   game data. OpenSky sets the System page and index directly, calls the page's `startPage`, and
   focuses its list. The tab group's `onTabChange` is what calls `startPage` in the game, and
   `startPage` adds the list's `itemPress` listener. Without it, accept on a row does nothing.

The other two pages fade to `hide`. System stops at its `forceFade` label.

Menu events become Flash key down and key up events. Cancel becomes Tab, not Escape:
`SystemPage.handleInput` goes back a page on `NavigationCode.TAB` and ignores `ESCAPE`, as the
vanilla inventory menus do. The Settings row opens
`SystemPage.SETTINGS_CATEGORY_STATE` by its named constant, through `StartState(aiState)`. No state
number is written into OpenSky. The movie's `CloseMenu` call closes the engine menu. If the movie
is missing or refuses the input, the engine selector handles it.

Input must go through the renderer's SWF update batch. That batch rebuilds the draw commands before
it returns. Sending input to the runtime directly changes the movie's selection without redrawing.

The renderer has one SWF layer. The system menu takes it from the HUD while the movie is up, and
gives it back on Resume. The movie is on by default, so play mode shows the menu as the game does.

No movie problem throws out of a control.

## The movie's own pages

With the movie up, the Save, Load, Controls, and Quit pages are the movie's own. Each row press
calls the engine, and the engine answers with data, as the game does. Calls measured with
`openskycli menu system` and read from the movie's `SystemPage` class:

| Movie calls | Engine answer |
| --- | --- |
| `SAVE` or `LOAD` with the list and a batch size | Fills the `SaveLoadPanel` list, newest first, then `onSaveLoadBatchComplete`. Saving adds a `[NEW SAVE]` row at the top |
| `SaveGame`, `LoadGame`, `DeleteSave` with a row | Writes, loads, or deletes that save. When saving, row 0 is a new save |
| `ShowScreenshot` | Puts the save's `THMB` picture in the movie's image slot, then `ScreenshotReady` |
| `RequestInputMappings` with the list | One entry per remappable gameplay event: its text, its key art, the key code, and a sort index |
| `StartRemapMode` with an event | The engine waits for the next key, rebinds it, and calls `FinishRemapMode(true)`; a reserved key gives `false` |
| `ResetControlsToDefaults` | Restores the default bindings and fills the list again |
| `QuitToMainMenu`, `QuitToDesktop` | Opens the title menu, or quits |

A mapping entry's key art is the key's name in `interface\controls\pc\keyboard_english.txt`, such as
`L-Ctrl` or `Mouse1` ([control map](/formats/controlmap.md), "Key names"). The movie draws the
button with that name. The X key deletes a save and T lists the characters, as in the movie's own
key handler.

The save and load pages, their questions, and the progress line read string settings:
`sMenuDisplayNewSave` names the new-save row, `sSaveOverSaveGame` and `sDeleteSaveGame` ask before
overwriting or deleting, and `sQuickSaving`, `sSaveSuccessful`, `sLoading`, `sDeleteSuccessful`, and
`sSaveFailed` fill the progress line. A save's detail line uses `sMenuDisplayLevelString`, and its
location uses `sDefaultCellName` for an exterior cell and `sMenuDisplayUnknownLocationString` when
there is no cell. Without game data, the pages keep OpenSky's English words.

The Settings page stays the engine's, because its values are the
[player settings](/engine/settings.md).

## Help and Installed Content

The movie builds both rows itself. `SystemPage.onCategoryButtonPress` maps a row to a case of
its switch, so the row index is not the case number. Without the `$CREATIONS` row
(`SetShowMod(false)`), every row from `MOD_MANAGER_BUTTON_INDEX` (4) on moves up one case.
`$INSTALLED CONTENT` is row 3 and `$HELP` is row 6.

| Row | Movie calls | Then |
| --- | --- | --- |
| Installed Content | `PopulateCreationClubTopics([entryList])` | Sorts the list, then `CREATIONS_LIST_STATE` (11) if it has rows |
| Help | `PopulateHelpTopics([entryList])` | Sorts the list, then `HELP_LIST_STATE` (13) if it has rows |
| A topic | `RequestCreationClubText` or `RequestHelpText([entry.index, titleField, textField])` | `CREATIONS_TEXT_STATE` (12) or `HELP_TEXT_STATE` (14) |

The movie checks the list length right after the populate call, so the engine fills the list
inside the call, not after the event as it does for the save calls. Each entry has `text` and
`index`; the movie hands `index` back when a topic is pressed. The engine writes the title and
the text into the two fields it passes. The text field is a component, so the engine writes
its `textField`. The movie then turns each `[Event]` tag into key art: its `CreateButtonArt` calls
`GetButtonFromUserEvent` with the controlmap user event, and the engine answers with the bound
key's name. Without that answer the movie faults before it shows the text.

Help lists the `HelpManualPC` form list, which the `HMPC` default object names
([UESP DOBJ](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOBJ)). Each entry is a
`MESG`: its `FULL` is the title and its `DESC` the text.

Installed Content lists the active plugins with their author, description, and masters from
the `TES4` header. The game shows the names of Creations here instead. A Creation plugin has
no such name in its header, so the game takes it from data outside the plugin files.

## Not done yet

- `PrepSaveGameScreenshot` is answered without a fresh picture of the current frame.
