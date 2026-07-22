// Weather runtime value types (M7.2.2): the time-of-day keyframe blend, the
// resolved sky/fog/ambient snapshot the renderer consumes, published wind, the
// decoded WTHR/CLMT/REGN index, and the region/climate selection rules. All
// pure value logic — the stateful transition machine lives in WeatherSystem.
//
// Selection follows xEdit REGN semantics (RDAT weather area priority + override
// flag) with the worldspace CLMT (WRLD CNAM) as fallback; see
// docs/engine/weather.md. Time-of-day windows come from CLMT TNAM timing.

import Foundation
import simd

/// Four time-of-day weights (sunrise/day/sunset/night) summing to 1, derived
/// from the current hour and the climate's sunrise/sunset windows. Applying the
/// same weights to any four keyframes (colors, fog, DALC) keeps every channel
/// in lockstep across the day.
nonisolated struct TimeOfDayWeights: Equatable {
    let sunrise: Float
    let day: Float
    let sunset: Float
    let night: Float

    /// Default windows (hours) when a climate has no TNAM timing: sunrise
    /// 05:00-07:00, sunset 17:00-19:00. Chosen as sane vanilla-like midpoints;
    /// real timing overrides them per climate.
    static let defaultSunrise: (begin: Float, end: Float) = (5, 7)
    static let defaultSunset: (begin: Float, end: Float) = (17, 19)

    init(sunrise: Float, day: Float, sunset: Float, night: Float) {
        self.sunrise = sunrise
        self.day = day
        self.sunset = sunset
        self.night = night
    }

    /// Piecewise blend across control points: night before sunrise, a smooth
    /// ramp peaking the sunrise keyframe at the sunrise midpoint, full day
    /// between the windows, a ramp peaking sunset at the sunset midpoint, and
    /// night after. Only ever two adjacent keyframes are non-zero.
    init(hour: Float, timing: Climate.Timing?) {
        let hour = TimeOfDayWeights.wrap(hour)
        let windows = TimeOfDayWeights.windows(timing: timing)
        let sunriseBegin = windows.sunriseBegin
        let sunriseEnd = windows.sunriseEnd
        let sunsetBegin = windows.sunsetBegin
        let sunsetEnd = windows.sunsetEnd
        let sunriseMid = (sunriseBegin + sunriseEnd) / 2
        let sunsetMid = (sunsetBegin + sunsetEnd) / 2

        if hour <= sunriseBegin || hour >= sunsetEnd {
            self.init(sunrise: 0, day: 0, sunset: 0, night: 1)
        } else if hour < sunriseMid {
            let time = TimeOfDayWeights.ramp(hour, sunriseBegin, sunriseMid)
            self.init(sunrise: time, day: 0, sunset: 0, night: 1 - time)
        } else if hour < sunriseEnd {
            let time = TimeOfDayWeights.ramp(hour, sunriseMid, sunriseEnd)
            self.init(sunrise: 1 - time, day: time, sunset: 0, night: 0)
        } else if hour <= sunsetBegin {
            self.init(sunrise: 0, day: 1, sunset: 0, night: 0)
        } else if hour < sunsetMid {
            let time = TimeOfDayWeights.ramp(hour, sunsetBegin, sunsetMid)
            self.init(sunrise: 0, day: 1 - time, sunset: time, night: 0)
        } else {
            let time = TimeOfDayWeights.ramp(hour, sunsetMid, sunsetEnd)
            self.init(sunrise: 0, day: 0, sunset: 1 - time, night: time)
        }
    }

    /// 0-1 daylight amount for the day/night-only fog pairs: full day counts 1,
    /// the twilight ramps count half, night counts 0.
    var daylight: Float {
        day + 0.5 * sunrise + 0.5 * sunset
    }

    func blend(
        _ sunriseValue: SIMD3<Float>,
        _ dayValue: SIMD3<Float>,
        _ sunsetValue: SIMD3<Float>,
        _ nightValue: SIMD3<Float>
    ) -> SIMD3<Float> {
        sunrise * sunriseValue + day * dayValue + sunset * sunsetValue + night * nightValue
    }

    func blend(
        _ sunriseValue: Float, _ dayValue: Float, _ sunsetValue: Float, _ nightValue: Float
    ) -> Float {
        sunrise * sunriseValue + day * dayValue + sunset * sunsetValue + night * nightValue
    }

    /// Sunrise/sunset window bounds in hours.
    private struct Windows {
        let sunriseBegin: Float
        let sunriseEnd: Float
        let sunsetBegin: Float
        let sunsetEnd: Float
    }

    private static let defaultWindows = Windows(
        sunriseBegin: defaultSunrise.begin, sunriseEnd: defaultSunrise.end,
        sunsetBegin: defaultSunset.begin, sunsetEnd: defaultSunset.end
    )

    private static func windows(timing: Climate.Timing?) -> Windows {
        guard let timing else { return defaultWindows }
        let sunriseBegin = Float(timing.sunriseBegin) / 60
        let sunriseEnd = Float(timing.sunriseEnd) / 60
        let sunsetBegin = Float(timing.sunsetBegin) / 60
        let sunsetEnd = Float(timing.sunsetEnd) / 60
        // Reject non-monotone timing (modder quirk) rather than divide by a
        // zero/negative window: fall back to the defaults.
        guard
            sunriseBegin < sunriseEnd, sunriseEnd < sunsetBegin, sunsetBegin < sunsetEnd,
            sunriseBegin >= 0, sunsetEnd <= 24
        else { return defaultWindows }
        return Windows(
            sunriseBegin: sunriseBegin, sunriseEnd: sunriseEnd,
            sunsetBegin: sunsetBegin, sunsetEnd: sunsetEnd
        )
    }

    /// Smoothstep across [lower, upper]; degenerate window -> 1 (fully arrived).
    private static func ramp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        guard upper > lower else { return 1 }
        let time = simd_clamp((value - lower) / (upper - lower), 0, 1)
        return time * time * (3 - 2 * time)
    }

    private static func wrap(_ hour: Float) -> Float {
        let modulo = hour.truncatingRemainder(dividingBy: 24)
        return modulo < 0 ? modulo + 24 : modulo
    }
}

/// Published wind for precipitation, grass, particles, and later audio. Vector
/// form keeps blends across transitions continuous through direction wrap.
nonisolated struct WindState: Equatable {
    /// Unit direction the wind blows toward, in the worldspace XY plane.
    let direction: SIMD2<Float>
    /// 0-1 wind speed (WTHR DATA Wind Speed).
    let speed: Float
    /// Degrees of meander around `direction` (WTHR DATA Wind Direction Range).
    let meanderRange: Float

    static let calm = WindState(direction: SIMD2(1, 0), speed: 0, meanderRange: 0)

    /// From a weather's DATA block; nil data -> calm. Direction degrees map to
    /// an XY unit vector (0 deg = +X, growing counter-clockwise).
    static func from(_ data: Weather.WeatherData?) -> WindState {
        guard let data else { return .calm }
        let radians = data.windDirection * Float.pi / 180
        return WindState(
            direction: SIMD2(cos(radians), sin(radians)),
            speed: simd_clamp(data.windSpeed, 0, 1),
            meanderRange: data.windDirectionRange
        )
    }

    /// Blends velocity vectors (dir * speed) so opposing winds cross through
    /// calm rather than snapping 180 degrees; renormalizes the result.
    static func blend(_ lhs: WindState, _ rhs: WindState, _ time: Float) -> WindState {
        let time = simd_clamp(time, 0, 1)
        let velocity = simd_mix(
            lhs.direction * lhs.speed,
            rhs.direction * rhs.speed,
            SIMD2(repeating: time)
        )
        let speed = simd_length(velocity)
        let direction = speed > 1e-5 ? velocity / speed
            : simd_normalize(simd_mix(lhs.direction, rhs.direction, SIMD2(repeating: time)))
        return WindState(
            direction: direction,
            speed: speed,
            meanderRange: lhs.meanderRange * (1 - time) + rhs.meanderRange * time
        )
    }
}

/// Transition-blended precipitation contribution. WTHR DATA carries a
/// classification, not a separate density scalar, so a settled rain/snow
/// weather contributes 1 and the weather cross-fade supplies intensity.
nonisolated struct PrecipitationState: Equatable {
    let rainIntensity: Float
    let snowIntensity: Float

    static let none = PrecipitationState(rainIntensity: 0, snowIntensity: 0)

    init(rainIntensity: Float, snowIntensity: Float) {
        self.rainIntensity = simd_clamp(rainIntensity, 0, 1)
        self.snowIntensity = simd_clamp(snowIntensity, 0, 1)
    }

    init(_ classification: Weather.Precipitation) {
        switch classification {
        case .rainy:
            self.init(rainIntensity: 1, snowIntensity: 0)
        case .snow:
            self.init(rainIntensity: 0, snowIntensity: 1)
        case .none, .pleasant, .cloudy:
            self = .none
        }
    }

    var intensity: Float {
        max(rainIntensity, snowIntensity)
    }

    static func blend(
        _ lhs: PrecipitationState,
        _ rhs: PrecipitationState,
        _ time: Float
    ) -> PrecipitationState {
        let time = simd_clamp(time, 0, 1)
        return PrecipitationState(
            rainIntensity: lhs.rainIntensity * (1 - time) + rhs.rainIntensity * time,
            snowIntensity: lhs.snowIntensity * (1 - time) + rhs.snowIntensity * time
        )
    }
}

/// Fully time-of-day-blended snapshot of one weather (or a transition blend of
/// two), ready to feed FrameUniforms. Sky palette colors drive the sky shader;
/// fog + ambient + directional feed the exterior lit path.
nonisolated struct ResolvedWeather: Equatable {
    var skyUpper: SIMD3<Float>
    var skyLower: SIMD3<Float>
    var horizon: SIMD3<Float>
    var sun: SIMD3<Float>
    var sunGlare: SIMD3<Float>
    var stars: SIMD3<Float>
    var fogNearColor: SIMD3<Float>
    var fogFarColor: SIMD3<Float>
    var fogNearDistance: Float
    var fogFarDistance: Float
    var fogPower: Float
    var fogMaximum: Float
    var fogEnabled: Bool
    var sunlightColor: SIMD3<Float>
    var ambientColor: SIMD3<Float>
    var directionalAmbient: DirectionalAmbientColors
    var wind: WindState
    var precipitation: PrecipitationState

    /// Resolves one weather at `hour` under `timing`. Missing NAM0/FNAM/DALC
    /// fields resolve to zero/disabled rather than throwing (mod-quirk rule).
    static func resolve(
        _ weather: Weather, hour: Float, timing: Climate.Timing?
    ) -> ResolvedWeather {
        let weights = TimeOfDayWeights(hour: hour, timing: timing)
        func color(_ component: Weather.Component) -> SIMD3<Float> {
            guard let layer = weather.colors(for: component) else { return .zero }
            return weights.blend(layer.sunrise, layer.day, layer.sunset, layer.night)
        }
        let fog = Self.resolveFog(weather.fog, weights: weights)
        return ResolvedWeather(
            skyUpper: color(.skyUpper),
            skyLower: color(.skyLower),
            horizon: color(.horizon),
            sun: color(.sun),
            sunGlare: color(.sunGlare),
            stars: color(.stars),
            fogNearColor: color(.fogNear),
            fogFarColor: color(.fogFar),
            fogNearDistance: fog.near,
            fogFarDistance: fog.far,
            fogPower: fog.power,
            fogMaximum: fog.maximum,
            fogEnabled: fog.enabled,
            sunlightColor: color(.sunlight),
            ambientColor: color(.ambient),
            directionalAmbient: Self.resolveDirectional(
                weather.directionalAmbient,
                weights: weights
            ),
            wind: WindState.from(weather.data),
            precipitation: PrecipitationState(weather.data?.precipitation ?? .none)
        )
    }

    static func blend(
        _ lhs: ResolvedWeather, _ rhs: ResolvedWeather, _ time: Float
    ) -> ResolvedWeather {
        let time = simd_clamp(time, 0, 1)
        func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
            simd_mix(a, b, SIMD3(repeating: time))
        }
        func lerp(_ a: Float, _ b: Float) -> Float {
            a * (1 - time) + b * time
        }
        return ResolvedWeather(
            skyUpper: mix(lhs.skyUpper, rhs.skyUpper),
            skyLower: mix(lhs.skyLower, rhs.skyLower),
            horizon: mix(lhs.horizon, rhs.horizon),
            sun: mix(lhs.sun, rhs.sun),
            sunGlare: mix(lhs.sunGlare, rhs.sunGlare),
            stars: mix(lhs.stars, rhs.stars),
            fogNearColor: mix(lhs.fogNearColor, rhs.fogNearColor),
            fogFarColor: mix(lhs.fogFarColor, rhs.fogFarColor),
            fogNearDistance: lerp(lhs.fogNearDistance, rhs.fogNearDistance),
            fogFarDistance: lerp(lhs.fogFarDistance, rhs.fogFarDistance),
            fogPower: lerp(lhs.fogPower, rhs.fogPower),
            fogMaximum: lerp(lhs.fogMaximum, rhs.fogMaximum),
            fogEnabled: lhs.fogEnabled || rhs.fogEnabled,
            sunlightColor: mix(lhs.sunlightColor, rhs.sunlightColor),
            ambientColor: mix(lhs.ambientColor, rhs.ambientColor),
            directionalAmbient: Self.blendDirectional(
                lhs.directionalAmbient, rhs.directionalAmbient, time
            ),
            wind: WindState.blend(lhs.wind, rhs.wind, time),
            precipitation: PrecipitationState.blend(
                lhs.precipitation, rhs.precipitation, time
            )
        )
    }

    /// Extra storm attenuation over the authored WTHR palette. Kept in the
    /// renderer-facing snapshot so fog/lighting remain authored values.
    func applyingStormSkyDarkening(maximum: Float = 0.35) -> ResolvedWeather {
        var result = self
        let scale = 1 - simd_clamp(maximum, 0, 1) * precipitation.intensity
        result.skyUpper *= scale
        result.skyLower *= scale
        result.horizon *= scale
        result.sun *= scale
        result.sunGlare *= scale
        return result
    }

    /// Day/night-blended fog scalars.
    private struct FogScalars {
        let near: Float
        let far: Float
        let power: Float
        let maximum: Float
        let enabled: Bool
    }

    private static func resolveFog(
        _ fog: Weather.FogDistances?, weights: TimeOfDayWeights
    ) -> FogScalars {
        guard let fog
        else { return FogScalars(near: 0, far: 1, power: 1, maximum: 0, enabled: false) }
        let daylight = weights.daylight
        func mix(_ night: Float, _ day: Float) -> Float {
            night * (1 - daylight) + day * daylight
        }
        let near = mix(fog.nightNear, fog.dayNear)
        let far = mix(fog.nightFar, fog.dayFar)
        let power = max(0.01, mix(fog.nightPow ?? 1, fog.dayPow ?? 1))
        // FNAM max <= 0 means "no cap"; treat as fully opaque at the far plane.
        let rawMax = mix(fog.nightMax ?? 1, fog.dayMax ?? 1)
        let maximum = rawMax > 0 ? simd_clamp(rawMax, 0, 1) : 1
        return FogScalars(
            near: near,
            far: far,
            power: power,
            maximum: maximum,
            enabled: far > near && far > 0
        )
    }

    private static func resolveDirectional(
        _ keyframes: Weather.DirectionalAmbientKeyframes?,
        weights: TimeOfDayWeights
    ) -> DirectionalAmbientColors {
        guard let keyframes else { return .black }
        func axis(_ pick: (Weather.DirectionalAmbient) -> SIMD3<Float>) -> SIMD3<Float> {
            weights.blend(
                pick(keyframes.sunrise), pick(keyframes.day),
                pick(keyframes.sunset), pick(keyframes.night)
            )
        }
        return DirectionalAmbientColors(
            positiveX: axis { $0.colors.positiveX },
            negativeX: axis { $0.colors.negativeX },
            positiveY: axis { $0.colors.positiveY },
            negativeY: axis { $0.colors.negativeY },
            positiveZ: axis { $0.colors.positiveZ },
            negativeZ: axis { $0.colors.negativeZ }
        )
    }

    private static func blendDirectional(
        _ lhs: DirectionalAmbientColors,
        _ rhs: DirectionalAmbientColors,
        _ time: Float
    ) -> DirectionalAmbientColors {
        func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
            simd_mix(a, b, SIMD3(repeating: time))
        }
        return DirectionalAmbientColors(
            positiveX: mix(lhs.positiveX, rhs.positiveX),
            negativeX: mix(lhs.negativeX, rhs.negativeX),
            positiveY: mix(lhs.positiveY, rhs.positiveY),
            negativeY: mix(lhs.negativeY, rhs.negativeY),
            positiveZ: mix(lhs.positiveZ, rhs.positiveZ),
            negativeZ: mix(lhs.negativeZ, rhs.negativeZ)
        )
    }
}
