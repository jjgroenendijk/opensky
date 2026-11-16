// Reaches into an open menu's movie, so a comparison can click the game's own interface and
// read what the click changed. Mouse keys typed through Wine do not reach the game.
#pragma once

#include <string>
#include <string_view>

namespace bridge {
/// `menu<action> <menu>|<x>|<y>` at a stage point, through the movie's own hit test: `menumove`
/// moves the cursor, `menudown` and `menuup` press and release the left button, `menuclick`
/// does all three at once, and `menuhit` only tests the point. Scaleform picks the target under
/// the cursor once per frame, so a real click sends the three in separate batches.
void ClickMenu(std::string_view arguments, std::string_view action);

/// `menuvar <menu>|<path>`: reads one ActionScript value of the movie for the state.
void ReadMenuVariable(std::string_view arguments);

/// `playbink <file>[|<interruptible>|<mute sound>|<mute music>|<letterbox>]`: calls the script
/// function `Game.PlayBink`; each flag is 0 or 1 and defaults as the script does.
void PlayBink(std::string_view arguments);

/// `menuopen <menu>` and `menuclose <menu>` show or hide a menu through the interface's message
/// queue, as the game's own key for that menu does.
void OpenMenu(std::string_view menu, bool open);

/// `menucall <menu>|<path>|<argument>...`: calls an ActionScript function of the movie. A
/// number, `true`, or `false` passes as that type, anything else as text.
void CallMenu(std::string_view arguments);

/// `automove on|off` holds or ends Auto-Move, so the player walks with no key pressed.
void SetAutoMove(bool on);

/// Runs a `menuopen`, `menuclose`, `menucall`, or `automove` line; false for any other line.
bool RunMenuLine(std::string_view line);

/// The `menuValues` member of the state: each value a `menuvar` line read, the last click and
/// call, the open menus, and Auto-Move.
std::string MenuState();
} // namespace bridge
