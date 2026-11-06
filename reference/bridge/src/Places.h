// Moves the player to a named map marker, so a check can reach any place without its
// coordinates, and reports that marker's type and flags.
#pragma once

#include <string>
#include <string_view>

namespace bridge {
/// `marker <name>`: moves the player to the map marker with that name, any case.
void GoToMarker(std::string_view name);

/// The `marker` member of the state: the marker the last `marker` line found, or nothing.
std::string MarkerState();
} // namespace bridge
