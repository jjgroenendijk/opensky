---
type: Subsystem
title: System menu
description: The pause menu - its toolkit-free selector, how it pauses the world through the
  menu stack, its two settings, and the vanilla quest_journal.swf movie behind it.
tags: [engine, ui, menu, swf, settings]
---

# System menu

The system menu is the pause menu: Resume, Settings, and Quit. It was the first real consumer of
[menu mode](/engine/menu-mode.md) input. It can also show itself through the vanilla
`Interface\quest_journal.swf` movie.

The menu works with no install, no renderer, and no movie. Only the movie layer needs them.

## Selector

The selector is a plain value: the rows, the highlighted row, the last result, and whether
Settings is shown. It knows nothing about the renderer, the movie, or AppKit.

Activating a row returns a result instead of doing the action, because two of the three actions
are not changes the selector can make:

| Row | Result | Who acts |
| --- | --- | --- |
| Resume | resume | The selector closes; the host closes the menu |
| Settings | show settings | The selector shows settings; the menu stays open |
| Quit | quit | The host quits the app |

Up and down wrap around, as the vanilla list does. A three-row list is hard to use without it.
Left and right are accepted and ignored, so they count as handled and do not reach the world.
Cancel means Resume, because the vanilla pause menu closes on the key that opened it.

## Pausing the world

Opening the menu pushes `SystemMenu` onto the menu stack, and makes the game view the input
consumer. That push is what pauses the world. The menu does not own the pause. It gets it by being
on the stack.

The menu has no key to open it, on purpose. In gameplay, Esc releases the mouse. Using Esc to open
the menu would clash with that, and the [app UI](/tools/app-ui.md) rules forbid features that only
a hidden key can reach. The menu opens from its panel. Once open, the normal menu keys drive it.
`J` opens the [quest journal](/engine/journal.md), as a shortcut for that panel's Open button.

## Settings

Neither setting is new state. Both use the systems that already own them, so the menu can never
disagree with them.

- Game data folder: shown, not changed here. It is found once through the
  [game data locator](/engine/game-data-locator.md) and cached, because finding it walks the disk
  and the panel refreshes twice a second. Change it in the Settings window (Cmd+,).
- Master volume: the same value as World > Audio > Output ([audio](/engine/audio.md)).

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
`$Main Menu` and `$Desktop`. The strings are still tokens, because translation is not connected
yet. The pages and transitions are the movie's own.

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

World > System Menu has a Menu section (Open, Resume, Up, Down, Activate, vanilla movie on and off)
and a Settings section (master volume). The readout shows the selection with a `>` marker, the open
menus, the pause state, the last row used, and the movie's draws, faults, and missing calls. An open
menu or an active movie marks the panel as changed, and Reset returns to gameplay.

## Not done yet

- The vanilla Settings panel shows and moves, but its values are not connected to engine data.
- Quit exits at once, with no question and no save.
- SWF text still shows `$TOKEN` names.
