import Foundation
import OpenSkyCells
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptSkyBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptSkyBindingsHost: AnyObject {
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public final class ScriptSkyBindingsAdapter {
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptSkyBindingsHost

    public init(owner: ScriptWorldAdapter, game: any ScriptSkyBindingsHost) {
        self.owner = owner
        self.game = game
    }
}

extension ScriptSkyBindingsAdapter {
    /// `GetSkyMode` values (<https://ck.uesp.net/wiki/GetSkyMode_-_Weather>).
    private enum SkyMode {
        static let interior: Int32 = 1
        static let full: Int32 = 3
    }

    public func wireSky(bridge: PapyrusWorldStateBridge) {
        bridge.sessionNatives.towardSun = { [weak game] in
            guard
                let game, game.streamer?.isInterior != true,
                let session = game.gameSession, let renderer = game.renderer,
                let weather = session.weather,
                weather.timeOfDayWeights(hour: session.gameClock.hourOfDay).night < 1
            else { return nil }
            return renderer.frameInput.celestial?.sunDirection ?? -renderer.camera.sunDirection
        }
        bridge.sessionNatives.playerView = { [weak game] in
            guard let camera = game?.gameSession?.freeFlyCamera else { return nil }
            return PapyrusPlayerView(eye: camera.position, forward: camera.forward)
        }
        bridge.sessionNatives.skyMode = { [weak game] in
            game?.streamer?.isInterior == true ? SkyMode.interior : SkyMode.full
        }
    }

    public func changeFog(_ change: PapyrusFogChange, in cell: FormID) -> Bool {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let lighting = renderer.scene.lighting,
            case let .interior(loaded)? = game.streamer?.interiorScene?.location, loaded == cell
        else { return false }
        var fog = gameSession.interiorFogOverride.flatMap { $0.base == lighting ? $0 : nil }
            ?? InteriorFogOverride(base: lighting)
        switch change {
        case let .colours(near, far): fog.setColours(near: near, far: far)
        case let .planes(near, far): fog.setPlanes(near: near, far: far)
        case let .power(power): fog.setPower(power)
        }
        gameSession.interiorFogOverride = fog
        return true
    }
}

extension ScriptSkyBindingsAdapter: PapyrusWeatherControlling {
    private var weatherSystem: WeatherSystem? {
        owner.weather()
    }

    private var resolver: FormIDResolver? {
        game.scripts.bridge?.formIDResolver
    }

    public var currentWeather: ReferenceKey? {
        guard let id = weatherSystem?.currentWeatherID, let resolver else { return nil }
        return ReferenceKey.resolve(id, using: resolver)
    }

    public var outgoingWeather: ReferenceKey? {
        guard let id = weatherSystem?.outgoingWeatherID, let resolver else { return nil }
        return ReferenceKey.resolve(id, using: resolver)
    }

    public var transitionFraction: Float {
        weatherSystem?.transitionFraction ?? 1
    }

    public func setWeather(
        _ weather: ReferenceKey, held: Bool, instant: Bool, accelerated: Bool
    ) -> Bool {
        guard let system = weatherSystem, let id = weatherFormID(weather) else { return false }
        let transition: WeatherSystem.Transition =
            instant ? .instant : accelerated ? .accelerated : .timed
        if held {
            system.forceWeather(id, transition: transition)
        } else {
            system.startWeather(id, transition: transition)
        }
        return true
    }

    public func releaseWeather() {
        weatherSystem?.forceWeather(nil, transition: .timed)
    }

    public func candidateWeathers() -> [ReferenceKey] {
        guard let system = weatherSystem, let resolver else { return [] }
        return system.candidateWeathers().compactMap { ReferenceKey.resolve($0, using: resolver) }
    }

    public func classification(of weather: ReferenceKey) -> Int32? {
        guard
            let id = weatherFormID(weather),
            let record = weatherSystem?.store.weather(id)
        else { return nil }
        return switch record.data?.precipitation ?? .none {
        case .none: -1
        case .pleasant: 0
        case .cloudy: 1
        case .rainy: 2
        case .snow: 3
        }
    }

    /// The load-order FormID of a `WTHR`, or nil when the key names none.
    private func weatherFormID(_ key: ReferenceKey) -> FormID? {
        guard
            case let .plugin(plugin, objectID) = key,
            let id = resolver?.localFormID(of: ResolvedFormID(plugin: plugin, objectID: objectID)),
            weatherSystem?.store.weather(id) != nil
        else { return nil }
        return id
    }
}
