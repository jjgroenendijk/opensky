// The per-frame weather advance, between the world simulation and the animation step,
// and the image space that follows the weather or the interior cell.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWeather

/// Where the session finds effect records (`IMGS`, `SPGD`), and the cell link an
/// interior names.
extension GameSession {
    /// The session's weather and its cloud layers. Without weather data the renderer
    /// keeps its procedural sky.
    public func attachWeather(from provider: WorldDataStores?) throws {
        weather = provider?.weatherSystem
        if let files = provider?.scriptFileSystem {
            renderer.skyClouds = try SkyClouds(fileSystem: files, device: renderer.device)
        }
    }
}

nonisolated public struct ImageSpaceLinks: Sendable {
    public let records: EffectRecordStore
    /// The plugin the weather store's `IMSP` links are spelled in.
    public let weatherPlugin: String
    /// The interior's `XCIM` link and its plugin; nil outdoors.
    public var interior: InteriorImageSpace?

    public init(records: EffectRecordStore, weatherPlugin: String) {
        self.records = records
        self.weatherPlugin = weatherPlugin
    }

    public func resolve(_ id: FormID, plugin: String) -> ResolvedImageSpace? {
        records.imageSpaces.resolve(id, fromPlugin: plugin).map {
            ResolvedImageSpace(key: ReferenceKey(resolved: $0.id), record: $0.record)
        }
    }
}

nonisolated public struct InteriorImageSpace: Equatable, Sendable {
    public let imageSpace: FormID?
    public let plugin: String

    public init(imageSpace: FormID?, plugin: String) {
        self.imageSpace = imageSpace
        self.plugin = plugin
    }
}

extension GameSession {
    /// Advances weather and caches this frame's resolve; nil without a weather system.
    /// Fades and rerolls count game hours, so a fixed clock (offscreen, CLI) holds both.
    public func updateWeather(deltaTime: Float) {
        defer { updateImageSpace(deltaTime: deltaTime) }
        guard weatherEnabled, let weather else {
            currentResolvedWeather = nil
            return
        }
        weather.update(hour: timeOfDay, elapsedGameHours: consumeElapsedGameHours())
        currentResolvedWeather = weather.resolvedWeather?.applyingStormSkyDarkening()
        if let links = imageSpaceLinks {
            precipitationTuning = PrecipitationTuning(record: weather.precipitationParticles(
                in: links.records, plugin: links.weatherPlugin
            ))
        }
    }

    public func updateWeatherFromWallClock() {
        let delta = weatherClock.advance(to: renderer.wallClock.now, paused: worldSimPaused)
        updateWeather(deltaTime: delta)
    }

    /// Ages the running modifiers and resolves the baseline from the interior cell or
    /// the weather blend (docs/rendering/image-space.md).
    public func updateImageSpace(deltaTime: Float) {
        imageSpace.modifiers.advance(deltaTime)
        guard let links = imageSpaceLinks else {
            imageSpace.baseline = .none
            return
        }
        let context: ImageSpaceContext = if let interior = links.interior {
            .interior(cellImageSpace: interior.imageSpace)
        } else if weatherEnabled, let weather {
            weather.imageSpaceContext(hour: timeOfDay)
        } else {
            .none
        }
        let plugin = links.interior?.plugin ?? links.weatherPlugin
        imageSpace.baseline = BaselineImageSpaceResolver.resolve(context) {
            links.resolve($0, plugin: plugin)
        }
    }
}
