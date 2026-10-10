// The shared provider fake's terrain-LOD, weather, water, and terrain behaviour. Split from
// `FakeWorldProviders.swift` for the same reason its AI and render-debug halves
// are: that class body is at the strict-lint size cap, and only stored state has
// to live there.

@testable import OpenSkyGameData

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

    // WaterControlProviding and TerrainShadingControlProviding

    var waterDepthEnabled: Bool {
        get { surfaces.waterDepthEnabled }
        set { surfaces.waterDepthEnabled = newValue }
    }

    var waterSurfaceCount: Int {
        get { surfaces.waterSurfaceCount }
        set { surfaces.waterSurfaceCount = newValue }
    }

    var terrainNormalMapsEnabled: Bool {
        get { surfaces.terrainNormalMapsEnabled }
        set { surfaces.terrainNormalMapsEnabled = newValue }
    }

    var terrainQuadrantCount: Int {
        get { surfaces.terrainQuadrantCount }
        set { surfaces.terrainQuadrantCount = newValue }
    }

    var terrainNormalMapCount: Int {
        get { surfaces.terrainNormalMapCount }
        set { surfaces.terrainNormalMapCount = newValue }
    }
}

/// Water depth and terrain shading switches and counts.
struct FakeSurfaceState {
    var waterDepthEnabled = true
    var waterSurfaceCount = 0
    var terrainNormalMapsEnabled = true
    var terrainQuadrantCount = 0
    var terrainNormalMapCount = 0
}
