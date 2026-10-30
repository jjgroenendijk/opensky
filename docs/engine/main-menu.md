---
type: Subsystem
title: Title menu and new game
description: The title menu, what a new game resets and starts, and the save list it loads
  from.
tags: [engine, ui, menu, save]
---

# Title menu and new game

The title menu shows Continue, New, Load, and Quit. Continue shows only
when a save exists and loads the newest one. Quit to Main Menu in the System menu returns
here. The launcher's Play button opens the game on this menu, as the original game does.
Developer mode opens in the world.

## The vanilla movie

The menu draws `interface\startmenu.swf`, the game's own main menu. These facts were measured on the
install with `openskycli swf movie-probe` and `swf action-list`:

- The menu clip is `/MenuHolder/Menu_mc`, with class `StartMenuObj`. Its row list is
  `MainListHolder/List_mc`. The list reacts to keys only while it has focus.
- Each row clip (`Entry0` and up) has its own `onRollOver`, which selects the row, and
  `onPress`, which picks it. So the cursor goes to the movie as a stage point, and the
  movie's hit test finds the row ([AS2 input](/engine/as2-input.md)). The rows sit at the
  right edge of the 1280 x 720 stage.
- The engine fills the rows by calling the `sendMenuProperties` callback with 14 values.
  Flag 0 shows Quit. Flag 1 shows Continue and enables Load. Value 2 is the version text.
  Flag 3 starts on the Press Start screen. Flag 9 skips the Bethesda.net login screen.
  The other flags show the DLC, Creations, Mods, Help, and console rows; OpenSky sends
  `false` for all of them.
- A chosen row calls the engine through `GameDelegate.call`: `CONTINUE`, `NEW`,
  `PopulateCharacterList` for Load, and `OpenCreditsMenu` for Credits. Quit first shows the
  movie's own confirm question, then calls `QuitToDesktop`.

Differences from the game:

- Behind the movie, the game draws the 3D logo `meshes\interface\logo\logo.nif` on black,
  with smoke around it. The smoke is the model of the `INTMenuFogParticles` `STAT` in
  `Skyrim.esm`, `meshes\interface\intmenufogparticles.nif`: a particle system that
  emits `fxsteamthinanim.dds` cards from a mesh, plus that mesh. OpenSky draws both
  through the loading screen's cover layer, so the world is hidden. The cover's particle
  systems run on wall time, because the menu pauses the world. The logo faces the camera
  with its +Y side, which was checked by eye in a capture. [WARNING] How the game places
  the smoke is not confirmed. The smoke volume is about 850 units wide, so with the logo's
  transform the camera stands inside it and the screen turns a flat grey. OpenSky faces the
  smoke's +Y side to the camera too and puts that side at the logo, so the smoke drifts
  behind it.
- The game draws the logo in `MainMenuCell` (`Skyrim.esm` `CELL 0006F3EB`), the cell the
  `MMCL` default object names. The cell holds only a `COCMarker`. Its `XCLL` gives a dim
  blue ambient light, no directional light, and fog distances of 0, so there is no fog.
  OpenSky lights the logo and the smoke with this cell's light over its `LTMP` template, and
  clears the screen to black. Sources: UESP "Skyrim Mod:Mod File Format/DOBJ" and
  "Skyrim:Inaccessible Cells", and `openskycli cell --cell MainMenuCell --refs`.
- The smoke model's emitter mesh is not drawn in the game: all of its 538 vertices have
  alpha 0, and its shader sets `Vertex_Alpha`, so the palette lookup gives alpha 0. Only the
  particles show.
- Credits returns the movie to its main rows. OpenSky has no credits roll.
- Delete in the Load list does nothing. Saves are deleted in the System menu.
- The movie has `ConfirmNewGame` and `ConfirmContinue` callbacks, so the game can ask a
  question before New and Continue. OpenSky does not call them and starts at once.

## The held world

No world loads while the title menu is open. The player can pick a save in another
world, so a world loaded beforehand could be the wrong one. Opening the title menu holds
the cell streamer; the first move of the player releases it. That move is the opening
quest's `MoveTo` for New, the save's place for Load and Continue, or a launcher start. A
start picked before any cell loaded recentres the streamer on the move, so the launch cell
`Tamriel (6,-2)` never loads first.

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

The screen stays covered from the choice of New until the player stands at the marker, and
the player is then put back into walk mode. Until the quest's `MoveTo`, the cover is a dark
screen and not the loading menu, because the loading menu pauses the scripts that make the
move. If no move comes within 30 seconds of simulation time, the cover lifts and the world loads
where the player stands.

The same fragment then calls `Game.FadeOutGame` and `Game.ShowTitleSequenceMenu`, and
`MQ101QuestScript` plays `Sequence1` to `Sequence4` with `Game.StartTitleSequence` before
`Game.HideTitleSequenceMenu`. The CK wiki says a sequence is "a given animation in the title
menu". In the game, `interface\titles.swf` draws these titles over the cart ride. OpenSky does
not build that movie yet, so the calls change nothing: after the loading screen the cart shows
at once, with no titles.

The `MQ101` aliases that name unique actors fill from the location records ([quest
state](/engine/quest-state.md), "What does not fill yet").

The race menu then opens where `MQ101` calls `Game.ShowRaceMenu` ([race
menu](/engine/race-menu.md)). In the game that call comes in Helgen, after the cart scene. OpenSky
does not play that scene yet, so a new game waits beside the carts. The riders who live in other
cells, such as `Ulfric` and `Lokir`, stay there, because `MoveTo` moves a reference only inside the
loaded cells. `debug quest MQ101 75` in the [agent control](/tools/agent-control.md) runs the stage
that opens the race menu.

`MoveTo` on the player ignores the offset and rotation arguments. A target outside the loaded cells
is looked up in the worldspace records of `Skyrim.esm`, off the main actor, and its cell loads
before the player is placed.

`MoveTo` on any other reference needs that reference and its target in the loaded cells. It
stores the target's position plus the offsets, and the target's rotation unless
`abMatchRotation` is false, as a transform change. The reference stays in the cell that owns
its record, so it draws at the new place only while that cell is loaded.

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

## Credits

Credits on the title menu plays `Interface\creditsmenu.swf` on the title menu's layer. The
movie makes `_root.CodeObj` itself and calls three functions on it, which the engine adds:

| Function | What OpenSky does |
| --- | --- |
| `requestCredits(field)` | Writes the text of `Interface\credits.txt` into `field`, without HTML tags |
| `getScrollSpeed()` | Returns 1 movie pixel per frame. The game's own speed is not in the data |
| `closeMenu()` | Gives the layer back to the title movie |

The engine then calls `onCodeObjectInit`, and the movie starts to scroll. Escape also ends
the credits. The facts were measured with `openskycli swf movie-probe`.
