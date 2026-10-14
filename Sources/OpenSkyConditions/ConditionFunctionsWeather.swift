// Weather condition functions. They read the weather the sky is moving toward,
// which the world fills from the weather runtime.
// See docs/engine/condition-functions.md#weather.

import Foundation
import OpenSkyFormatsESM

/// The current weather and its `DATA` classification.
nonisolated public struct WeatherConditionResolution: ConditionResolution, Sendable {
    public static let empty = WeatherConditionResolution(weather: nil, precipitation: .none)

    /// Load-order FormID; nil when no weather runs, such as indoors.
    public let weather: FormID?
    public let precipitation: Weather.Precipitation

    public init(weather: FormID?, precipitation: Weather.Precipitation) {
        self.weather = weather
        self.precipitation = precipitation
    }
}

nonisolated extension ConditionContext {
    public var weather: WeatherConditionResolution {
        get { self[resolution: WeatherConditionResolution.self] }
        set { self[resolution: WeatherConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installWeather(_ registry: inout ConditionFunctionRegistry) {
        // "this will return true as soon as the weather starts transitioning into the
        // specified weather" (<https://ck.uesp.net/wiki/GetIsCurrentWeather>).
        registry.register(ConditionFunction(
            index: 149, name: "GetIsCurrentWeather", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(149))
            }
            return Self.currentWeather(call).map { Self.isTrue($0.weather == parameter.asFormID) }
        })
        registry.register(ConditionFunction(index: 266, name: "IsPleasant") { call in
            Self.currentWeather(call).map { Self.isTrue($0.precipitation == .pleasant) }
        })
        registry.register(ConditionFunction(index: 62, name: "IsRaining") { call in
            Self.currentWeather(call).map { Self.isTrue($0.precipitation == .rainy) }
        })
        registry.register(ConditionFunction(index: 75, name: "IsSnowing") { call in
            Self.currentWeather(call).map { Self.isTrue($0.precipitation == .snow) }
        })
    }

    private static func currentWeather(
        _ call: ConditionCall
    ) -> Result<WeatherConditionResolution, ConditionFailure> {
        let weather = call.context.weather
        guard weather.weather != nil else { return .failure(.unavailableData(.weather)) }
        return .success(weather)
    }
}
