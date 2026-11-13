// The per-frame weather advance, between the world simulation and the animation step,
// and the image space that follows the weather or the interior cell.

public import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWeather
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Where the session finds effect records (`IMGS`, `SPGD`), and the cell link an
/// interior names.
extension GameSession.WeatherSteps {
    /// The session's weather and its cloud layers. Without weather data the renderer
    /// keeps its procedural sky.
    public func attachWeather(from provider: WorldDataStores?) throws {
        session.weather = provider?.weatherSystem
        if let provider {
            session.sky.skySettings = SkySettings.resolve(store: provider.gameSettings)
        }
        session.weather?.transitionAcceleration = session.sky.skySettings.weatherTransAccel
        if let files = provider?.scriptFileSystem {
            session.renderer.skyClouds = try SkyClouds(
                fileSystem: files,
                device: session.renderer.device
            )
            session.renderer.skyCelestial = try SkyCelestial(
                fileSystem: files,
                device: session.renderer.device
            )
            session.renderer.recordTextures = try RecordTextures(
                fileSystem: files, device: session.renderer.device
            )
        }
    }

    /// The clouds and sky objects of an offscreen frame, loaded at once, with the
    /// sky settings of `loadOrder`.
    public func attachOffscreenSky(
        loadOrder: LoadOrderPlugins, fileSystem: any GameFileSource
    ) throws {
        session.sky.skySettings = SkySettings.resolve(store: GameSettingStore(
            plugins: loadOrder.plugins.map { ($0.name, $0.file) }
        ))
        let device = session.renderer.device
        session.renderer.skyClouds = try SkyClouds(
            fileSystem: fileSystem,
            device: device,
            immediate: true
        )
        session.renderer.skyCelestial = try SkyCelestial(
            fileSystem: fileSystem, device: device, immediate: true
        )
        session.renderer.recordTextures = try RecordTextures(
            fileSystem: fileSystem, device: device, immediate: true
        )
    }
}

extension GameSession.WeatherSteps {
    /// Advances weather and caches this frame's resolve; nil without a weather system.
    /// Fades and rerolls count game hours, so a fixed clock (offscreen, CLI) holds both.
    public func updateWeather(deltaTime: Float) {
        defer { updateImageSpace(deltaTime: deltaTime) }
        guard session.sky.weatherEnabled, let weather = session.weather else {
            session.sky.currentResolvedWeather = nil
            session.sky.celestialSky = nil
            session.renderer.regionEmittance = [:]
            return
        }
        weather.cloudSpeedMax = session.sky.skySettings.weatherCloudSpeedMax
        weather.update(
            hour: session.timeOfDay,
            elapsedGameHours: session.clockSteps.consumeElapsedGameHours()
        )
        session.renderer.regionEmittance = weather.regionEmittance(
            for: session.renderer.emittanceRegions, hour: session.timeOfDay
        )
        session.sky.currentResolvedWeather = weather.resolvedWeather?
            .applyingStormSkyDarkening()
        session.sky.celestialSky = session.sky.currentResolvedWeather == nil ? nil : weather
            .celestialSky(
                hour: session.timeOfDay,
                daysPassed: session.gameTime.clock.daysPassed,
                settings: session.sky.skySettings
            )
        if let links = session.sky.imageSpaceLinks {
            session.sky
                .precipitationTuning = PrecipitationTuning(record: weather
                    .precipitationParticles(
                        in: links.records,
                        plugin: links.weatherPlugin
                    ))
        }
        applyScriptParticles(deltaTime: deltaTime)
    }

    public func updateWeatherFromWallClock() {
        let delta = session.sky.weatherClock.advance(
            to: session.renderer.wallClock.now,
            paused: session.worldSimPaused
        )
        updateWeather(deltaTime: delta)
    }

    /// A script's `SPGD` replaces the weather's particle look while it shows, and adds
    /// its rain or snow to the weather's.
    private func applyScriptParticles(deltaTime: Float) {
        session.sky.scriptParticles.advance(deltaTime)
        guard let record = session.sky.scriptParticles.record else { return }
        session.sky.precipitationTuning = PrecipitationTuning(record: record)
        if var resolved = session.sky.currentResolvedWeather {
            resolved.precipitation = session.sky.scriptParticles.adding(to: resolved.precipitation)
            session.sky.currentResolvedWeather = resolved
        }
    }

    /// A load or a new game drops the fade and the particles a script left running.
    public func clearScriptScreenEffects() {
        session.imageSpace.screenFade = ScreenFade()
        session.sky.scriptParticles = ScriptParticleGeometry()
    }

    /// Ages the running modifiers and resolves the baseline from the interior cell or
    /// the weather blend (docs/rendering/image-space.md).
    public func updateImageSpace(deltaTime: Float) {
        session.imageSpace.modifiers.advance(deltaTime)
        session.imageSpace.screenFade.advance(deltaTime)
        guard let links = session.sky.imageSpaceLinks else {
            session.imageSpace.baseline = .none
            session.renderer.volumetricLight = .fallback
            return
        }
        session.renderer.volumetricLight = if
            links.interior == nil, session.sky.weatherEnabled,
            let weather = session.weather
        {
            weather.volumetricLight(
                hour: session.timeOfDay, records: links.records, plugin: links.weatherPlugin
            )
        } else {
            .fallback
        }
        let underwater = session.renderer.cameraWaterImageSpace
        let context: ImageSpaceContext = if let underwater {
            .underwater(imageSpace: underwater)
        } else if let interior = links.interior {
            .interior(cellImageSpace: interior.imageSpace)
        } else if session.sky.weatherEnabled, let weather = session.weather {
            weather.imageSpaceContext(hour: session.timeOfDay)
        } else {
            .none
        }
        let plugin = underwater == nil
            ? links.interior?.plugin ?? links.weatherPlugin
            : links.weatherPlugin
        session.imageSpace.baseline = BaselineImageSpaceResolver.resolve(context) {
            links.resolve($0, plugin: plugin)
        }
    }
}
