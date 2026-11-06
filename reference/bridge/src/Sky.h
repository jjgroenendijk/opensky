// What OpenSky compares the sky and the music with: where the sun and moons stand, how
// the moons and cloud layers draw, the wind, and the playing music type.
#pragma once

#include <string>

namespace bridge {
/// The `sky` member of the state, or nothing outside a sky.
std::string SkyState();

/// The `music` member of the state: the playing type and the queue under it.
std::string MusicState();
} // namespace bridge
