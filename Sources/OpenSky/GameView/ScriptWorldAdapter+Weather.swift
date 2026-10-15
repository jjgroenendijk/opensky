// The sky a Papyrus script changes: `Weather.SetActive`, `ForceActive`, and their reads,
// over the renderer's `WeatherSystem`. Keys convert through the script load order.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld

extension ScriptWorldAdapter: PapyrusWeatherControlling {
    private var weatherSystem: WeatherSystem? {
        game.renderer?.weather
    }

    private var resolver: FormIDResolver? {
        game.scripts.bridge?.formIDResolver
    }

    var currentWeather: ReferenceKey? {
        guard let id = weatherSystem?.currentWeatherID, let resolver else { return nil }
        return ReferenceKey.resolve(id, using: resolver)
    }

    var outgoingWeather: ReferenceKey? {
        guard let id = weatherSystem?.outgoingWeatherID, let resolver else { return nil }
        return ReferenceKey.resolve(id, using: resolver)
    }

    var transitionFraction: Float {
        weatherSystem?.transitionFraction ?? 1
    }

    func setWeather(_ weather: ReferenceKey, held: Bool, instant: Bool) -> Bool {
        guard let system = weatherSystem, let id = weatherFormID(weather) else { return false }
        if held {
            system.forceWeather(id, transition: instant ? .instant : .timed)
        } else {
            system.startWeather(id, transition: instant ? .instant : .timed)
        }
        return true
    }

    func releaseWeather() {
        weatherSystem?.forceWeather(nil, transition: .timed)
    }

    func candidateWeathers() -> [ReferenceKey] {
        guard let system = weatherSystem, let resolver else { return [] }
        return system.candidateWeathers().compactMap { ReferenceKey.resolve($0, using: resolver) }
    }

    func classification(of weather: ReferenceKey) -> Int32? {
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
