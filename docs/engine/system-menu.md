---
type: Subsystem
title: System menu
description: The pause menu - its toolkit-free selector, how it pauses the world through the
  menu stack, its two settings, and the vanilla quest_journal.swf movie behind it.
tags: [engine, ui, menu, swf, settings]
---

# System menu

The system menu is the pause menu: Resume, Quicksave, Save, Load, Settings, Controls, and Quit,
the rows of the vanilla System page. It was the first real consumer of
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
| Save, Load, Settings, Controls, Quit | show page | The page model takes the keys |

Each page is its own model: the Settings page steps the [player settings](/engine/settings.md),
the Save and Load pages list saves newest first and ask before an overwrite or a delete, the
Controls page waits for the next key and rebinds it ([control map](/formats/controlmap.md)),
and Quit asks Main Menu, Desktop, or Cancel, with Cancel selected. Main Menu opens the
[title menu](/engine/main-menu.md). Cancel on a page returns to the row list.

Up and down wrap around, as the vanilla list does.
Left and right are accepted and ignored, so they count as handled and do not reach the world.
Cancel means Resume, because the vanilla pause menu closes on the key that opened it.

## Pausing the world

Opening the menu pushes `SystemMenu` onto the menu stack, and makes the game view the input
consumer. That push is what pauses the world. The menu does not own the pause. It gets it by being
on the stack.

The control map's Pause key, Esc, opens the menu. While the mouse is captured, the first Esc
releases it instead. The menu also opens from its panel, so no feature needs a hidden key.
Opening it may write a pause autosave. `J` opens the [quest journal](/engine/journal.md).

## Settings

The sidebar settings use the systems that already own them, so the menu can never disagree
with them.

- Game data folder: shown, not changed here. It is found once through the
  [game data locator](/engine/game-data-locator.md) and cached, because finding it walks the disk
  and the panel refreshes twice a second. Change it in the Settings window (Cmd+,).
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
   game data. OpenSky sets the System page and index directly, and focuses its list.

The other two pages fade to `hide`. System stops at its `forceFade` label.

Menu events become Flash key down and key up events. The Settings row opens
`SystemPage.SETTINGS_CATEGORY_STATE` by its named constant, through `StartState(aiState)`. No state
number is written into OpenSky. The movie's `CloseMenu` call closes the engine menu. If the movie
is missing or refuses the input, the engine selector handles it.

Input must go through the renderer's SWF update batch. That batch rebuilds the draw commands before
it returns. Sending input to the runtime directly changes the movie's selection without redrawing.

The renderer has one SWF layer. The system menu takes it from the HUD while the movie is up, and
gives it back on Resume. The movie is off by default. The engine selector is the main surface, and
the movie is an extra on top.

No movie problem throws out of a control. A missing install, a movie that does not decode, or a
call the runtime cannot answer becomes a message in the panel readout.

## Controls

World > System Menu has a Menu section (Open, Resume, Up, Down, Activate, vanilla movie on and off),
a Page section (Left, Right, Back, Delete Save, and the page rows), and a Settings section
(master volume). The readout shows the selection with a `>` marker, the open
menus, the pause state, the last row used, and the movie's draws, faults, and missing calls. An open
menu or an active movie marks the panel as changed, and Reset returns to gameplay.

## Not done yet

- The movie mirrors the System page rows; the sub-pages are drawn by the engine readout, not by
  the movie's own Save, Load, and Controls lists.
