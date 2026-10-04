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
- Load needs the character list and save list callbacks, which OpenSky does not send yet.
  Load and Credits return the movie to its main rows.
- The movie has `ConfirmNewGame` and `ConfirmContinue` callbacks, so the game can ask a
  question before New and Continue. OpenSky does not call them and starts at once.

## New game

A new game:

1. Clears the world state, the script instances, and the timers.
2. Sets the clock to the vanilla start time ([game clock](/engine/game-clock.md)).
3. Starts the quests the load order's `.seq` files list
   ([story manager](/engine/story-manager.md)).
4. Opens the race menu ([race menu](/engine/race-menu.md)).

In the game, the opening quest opens the race menu during the cart ride. OpenSky opens it
right away, because the cart scene does not play yet. The player stays at OpenSky's start
cell until a script moves them.

## Save list

Each save carries a `SUMM` chunk with the character name, level, race, location, and play
time, and a `THMB` chunk with a 192 by 108 picture of the frame
([save container](/formats/opensky-save.md)). The list reads only these chunks and skips
the rest by length, so a large save lists fast. Play time is real time, carried from the
save that was loaded.
