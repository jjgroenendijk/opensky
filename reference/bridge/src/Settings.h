// Reads and sets the game's INI and game settings by name, so a comparison can turn a
// game feature on or off and check that the value took.
#pragma once

#include <string>
#include <string_view>

namespace bridge {
/// `ini <name:section> [value]`: reads the setting, or sets it first when a value follows.
void ReadOrSetSetting(std::string_view arguments);

/// The `settings` member of the state: each setting an `ini` line named, with its value.
std::string SettingsState();
} // namespace bridge
