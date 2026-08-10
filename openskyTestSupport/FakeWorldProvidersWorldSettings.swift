// The shared provider fake's terrain-LOD and weather behaviour. Split from
// `FakeWorldProviders.swift` for the same reason its AI and render-debug halves
// are: that class body is at the strict-lint size cap, and only stored state has
// to live there.

@testable import opensky

extension FakeWorldProviders {
    // TerrainLODControlProviding

    func applyTerrainLODConfiguration(_: TerrainLODConfiguration) -> Bool {
        terrainLODOverrideActive = true
        return true
    }

    func resetTerrainLODConfiguration() {
        terrainLODOverrideActive = false
    }

    // WeatherControlProviding

    func forceWeather(named name: String?) {
        weatherOverrideActive = name != nil
    }

    func forceWeather(_: WeatherPreset) {
        weatherOverrideActive = true
    }
}
