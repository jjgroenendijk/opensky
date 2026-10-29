// What OpenSky reads to follow the game: place, view, hour, weather, and field of view.
#pragma once

#include <string>

namespace bridge {
/// The game's state as one JSON object. Runs on the game's main thread.
std::string Snapshot(const std::string &lastBatch);

/// Runs one batch line. `load <save>` loads through the save manager, so it works
/// at the main menu too; any other line runs as a console command.
void RunLine(const std::string &line);
} // namespace bridge
