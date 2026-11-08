public import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyWorldInterface

/// What the world adapters use of `WorldRenderControls`.
public protocol WorldRenderControlsPort: AnyObject {
    var frameStatsSnapshot: FrameStatsSnapshot { get }
    var renderPerformanceSnapshot: RenderPerformanceSnapshot? { get }
    var selectableWeatherNames: [String] { get }
    var terrainLODBrightness: TerrainLODBrightness? { get }
    func forceWeather(named name: String?, transition: WeatherTransition)
}

/// The default arguments a protocol requirement cannot carry.
extension WorldRenderControlsPort {}
