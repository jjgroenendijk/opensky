---
type: Subsystem
title: Title menu and new game
description: The title menu, what a new game resets and starts, and the save list it loads
  from.
tags: [engine, ui, menu, save]
---

# Title menu and new game

The title menu shows Continue, New, Load, and Quit over a paused world. Continue shows only
when a save exists and loads the newest one. Quit to Main Menu in the System menu returns
here. The launcher's Play button opens the game on this menu, as the original game does.
Developer mode opens in the world.

## The vanilla movie

The menu draws `interface\startmenu.swf`, the game's own main menu. OpenSky's engine rows
stay as the fallback when the movie does not load, and a sidebar control switches between
the two. These facts were measured on the install with `openskycli swf movie-probe` and
`swf action-list`:

- The menu clip is `/MenuHolder/Menu_mc`, with class `StartMenuObj`. Its row list is
  `MainListHolder/List_mc`. The list reacts to keys only while it has focus.
- The engine fills the rows by calling the `sendMenuProperties` callback with 14 values.
  Flag 0 shows Quit. Flag 1 shows Continue and enables Load. Value 2 is the version text.
  Flag 3 starts on the Press Start screen. Flag 9 skips the Bethesda.net login screen.
  The other flags show the DLC, Creations, Mods, Help, and console rows; OpenSky sends
  `false` for all of them.
- A chosen row calls the engine through `GameDelegate.call`: `CONTINUE`, `NEW`,
  `PopulateCharacterList` for Load, and `OpenCreditsMenu` for Credits. Quit first shows the
  movie's own confirm question, then calls `QuitToDesktop`.

Differences from the game:

- Behind the movie, the game draws the 3D logo `meshes\interface\logo\logo.nif` on black.
  OpenSky draws it through the loading screen's cover layer, so the world is hidden. The
  logo faces the camera with its +Y side, which was checked by eye in a capture. Any smoke
  or lighting effects of the original scene are not drawn.
- Credits returns the movie to its main rows. OpenSky has no credits roll.
- Delete in the Load list does nothing. Saves are deleted in the System menu.
- The movie has `ConfirmNewGame` and `ConfirmContinue` callbacks, so the game can ask a
  question before New and Continue. OpenSky does not call them and starts at once.

## New game

A new game:

1. Clears the world state, the script instances, and the timers.
2. Sets the clock to the vanilla start time ([game clock](/engine/game-clock.md)).
3. Starts the quests the load order's `.seq` files list
   ([story manager](/engine/story-manager.md)).
4. Starts `MQ101`, the opening quest, by its editor ID. Its record is not flagged to start
   with the game, and no `.seq` file or default object names it. [WARNING] How the game
   starts it is not confirmed; this is an observation of `Skyrim.esm`.
5. Runs the quest's start-up stage. Its fragment moves the player to the reference in its
   `PlayerStartMarker` alias, on the cart near Helgen, with `ObjectReference.MoveTo`. The
   fragment reads each alias with `GetRef` ([quests](/engine/papyrus-quests.md)).

The race menu then opens where `MQ101` calls `Game.ShowRaceMenu`
([race menu](/engine/race-menu.md)). In the game that call comes in Helgen, after the cart
scene. OpenSky does not play that scene yet, so a new game waits in the cart. The race menu
panel in the sidebar opens the menu by hand.

`MoveTo` moves only the player, without the offset and rotation arguments. A target outside
the loaded cells is looked up in the worldspace records of `Skyrim.esm`, off the main
actor, and its cell loads before the player is placed. The title menu panel can also start
a new game at a named cell; that test start opens the race menu at once.

The `MQ101` fragment calls were read with the PEX disassembler into
`.logs/probe-mq101/functions.txt`.

## Load list

Load opens two lists in the movie: the characters, then the saves of one character. The
calls were read with the action disassembler.

| Movie calls | Arguments | OpenSky answers |
| --- | --- | --- |
| `PopulateCharacterList` | list, batch size | Fills the list with `text`, `id`, `flags`, then calls `onFillCharacterListComplete(true)` |
| `CharacterSelected` | id, flags, saving, list, batch size | Fills the list with the saves, then calls `onSaveLoadBatchComplete(true, n, n)` |
| `PrepSaveGameScreenshot` | index | Paints the save's picture, then calls `ScreenshotReady` |
| `IsOKtoLoad` | index | Calls `ConfirmOKToLoad` |
| `LoadGame` | index | Loads the save |

- Characters are sorted by their newest save. A save with no readable name is under
  `Unknown`.
- A save row has `text`, `fileNum`, `id`, `name`, `raceName`, `level`, `playTime`,
  `dateString`, `corrupt`, `obsolete`, and `flags`.
- The picture is an `img://BGSSaveLoadHeader_Screenshot` image of 192 by 108 pixels
  ([SWF image slots](/engine/as2-display-runtime.md)). The save thumbnail is scaled to it by
  nearest pixel. A save without one shows grey.
- The menu opens after the save list is read, because the movie reads Continue and Load
  once when it starts.
- The movie advances once per frame at its own frame rate, at most 4 movie frames per
  frame. A CLIK row press and a state change need these frames.
- Key focus follows the movie state: the main rows in `Main`, and
  `SaveLoadPanel_mc/List_mc` in `CharacterSelection` and `SaveLoad`. The characters and
  the saves share that one list.
- After a fill the list has no selected row, and a key does not move it. OpenSky selects
  row 0, so Accept works at once.
- The answers run after the movie event that asked, on the main actor. A list the movie
  passed is read back from the runtime's last arguments of that call.

## Save list

Each save carries a `SUMM` chunk with the character name, level, race, location, and play
time, and a `THMB` chunk with a 192 by 108 picture of the frame
([save container](/formats/opensky-save.md)). The list reads only these chunks and skips
the rest by length, so a large save lists fast. Play time is real time, carried from the
save that was loaded.
