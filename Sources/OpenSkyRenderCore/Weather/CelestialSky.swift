// Where the sun, the moons, the stars, and the aurora are at one hour and day, and how
// strongly each shows. Pure: the clock, the climate, the weathers, and the GMSTs go in.
// The model and its sources: docs/engine/celestial-sky.md.

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public enum MoonPhase: Int, CaseIterable, Sendable {
    case full, threeWaning, halfWaning, oneWaning, new, oneWaxing, halfWaxing, threeWaxing

    /// The texture name part, as in `textures\sky\masser_three_wan.dds`.
    public var textureSuffix: String {
        switch self {
        case .full: "full"
        case .threeWaning: "three_wan"
        case .halfWaning: "half_wan"
        case .oneWaning: "one_wan"
        case .new: "new"
        case .oneWaxing: "one_wax"
        case .halfWaxing: "half_wax"
        case .threeWaxing: "three_wax"
        }
    }

    /// Each phase lasts the climate's phase length; a length of 0 holds the full moon.
    public static func at(daysPassed: Float, phaseLengthDays: Int) -> MoonPhase {
        guard phaseLengthDays > 0, daysPassed.isFinite else { return .full }
        let step = Int((daysPassed / Float(phaseLengthDays)).rounded(.down))
        let count = allCases.count
        return MoonPhase(rawValue: ((step % count) + count) % count) ?? .full
    }
}

nonisolated public enum Moon: String, CaseIterable, Sendable {
    case masser, secunda
}

nonisolated public struct MoonState: Equatable, Sendable {
    public let moon: Moon
    public let phase: MoonPhase
    /// Unit vector from the viewer toward the moon.
    public let direction: SIMD3<Float>
    /// Half the moon's width over its distance: the tangent of its angular radius.
    public let halfSize: Float
    public let alpha: Float

    /// Relative to `textures\`.
    public var texture: String {
        "sky\\\(moon.rawValue)_\(phase.textureSuffix).dds"
    }
}

nonisolated public struct AuroraState: Equatable, Sendable {
    /// The weather's aurora model, relative to `meshes\`.
    public let model: String
    public let alpha: Float
    /// Radians the model turns about the up axis: the sun's bearing from east for a
    /// weather that "Follows Sun Position", else 0.
    public var yaw: Float = 0
}

nonisolated public struct CelestialSky: Equatable, Sendable {
    /// Unit vector from the viewer toward the sun disc.
    public var sunDirection: SIMD3<Float>
    /// Unit direction the sun or moon light travels, toward the ground.
    public var lightDirection: SIMD3<Float>
    /// 0 while the sun is down; fades by `fSunAlphaTransTime` at the horizon.
    public var sunAlpha: Float
    public var glareScale: Float
    public var starsAxis: SIMD3<Float>
    /// Radians the stars have turned about `starsAxis`.
    public var starsAngle: Float
    public var moons: [MoonState]
    public var auroras: [AuroraState]
    /// Relative to `textures\`.
    public var sunTexture: String?
    public var glareTexture: String?
    /// Relative to `meshes\`.
    public var nightSkyModel: String?

    /// Hides the stars behind a moon, relative to `textures\`.
    public static let moonShadowTexture = "sky\\moonshadow.dds"

    /// The light never comes from lower than this, so shadows stay finite at the horizon.
    public static let minimumLightElevation: Float = 10 * .pi / 180

    public static func resolve(
        hour: Float,
        daysPassed: Float,
        climate: Climate?,
        weathers: [(weather: Weather, weight: Float)],
        settings: SkySettings
    ) -> CelestialSky {
        let hour = wrapHour(hour)
        let path = SunPath(hour: hour, timing: climate?.timing, settings: settings)
        let sun = simd_normalize(path.position(reach: settings.sunXExtreme))
        let glare = weathers.reduce(Float(0)) { $0 + ($1.weather.data?.sunGlare ?? 0) * $1.weight }
        let rotation = settings.starsRotateDays > 0 ? daysPassed / settings.starsRotateDays : 0
        let axisLength = simd_length(settings.starsRotateAxis)
        return CelestialSky(
            sunDirection: sun,
            lightDirection: -lightSource(path.position(reach: settings.sunDirXExtreme)),
            sunAlpha: path.discAlpha(fadeHours: settings.sunAlphaTransTime),
            glareScale: max(settings.sunMinimumGlareScale, glare),
            starsAxis: axisLength > 1e-6 ? settings.starsRotateAxis / axisLength : SIMD3(0, 0, 1),
            // Negative turn: a star on the east horizon climbs, as the sun does.
            starsAngle: -2 * .pi * (rotation - rotation.rounded(.down)),
            moons: moons(path: path, sun: sun, climate: climate, days: daysPassed, settings),
            auroras: auroras(
                weathers, hour: hour, sunBearing: atan2(sun.y, sun.x), settings: settings
            ),
            sunTexture: climate?.sunTexture,
            glareTexture: climate?.glareTexture,
            nightSkyModel: climate?.nightSkyModel
        )
    }

    /// The sun by day; by night the same path mirrored above the horizon, so the
    /// light moves without a jump at sunset and sunrise.
    static func lightSource(_ position: SIMD3<Float>) -> SIMD3<Float> {
        var source = simd_normalize(SIMD3(position.x, position.y, abs(position.z)))
        let horizontal = simd_length(SIMD2(source.x, source.y))
        if source.z < sin(minimumLightElevation), horizontal > 1e-6 {
            let scale = cos(minimumLightElevation) / horizontal
            source = SIMD3(source.x * scale, source.y * scale, sin(minimumLightElevation))
        }
        return source
    }

    private static func moons(
        path: SunPath, sun: SIMD3<Float>, climate: Climate?, days: Float, _ settings: SkySettings
    ) -> [MoonState] {
        guard let timing = climate?.timing else { return [] }
        let phase = MoonPhase.at(daysPassed: days, phaseLengthDays: timing.phaseLengthDays)
        let present: [(Moon, MoonSettings)] = [
            timing.masser ? (.masser, settings.masser) : nil,
            timing.secunda ? (.secunda, settings.secunda) : nil
        ].compactMap(\.self)
        let distance = max(abs(settings.sunXExtreme), 1)
        return present.map { moon, tuning in
            let direction = moonDirection(sunAngle: path.angle, tuning: tuning)
            let fromSun = acos(simd_clamp(simd_dot(direction, sun), -1, 1)) * 180 / .pi
            let span = tuning.fadeStart - tuning.fadeEnd
            let sunFade = span > 0 ? simd_clamp((fromSun - tuning.fadeEnd) / span, 0, 1)
                : (fromSun > tuning.fadeEnd ? 1 : 0)
            return MoonState(
                moon: moon, phase: phase, direction: direction,
                halfSize: tuning.size * 0.5 / distance,
                alpha: sunFade * smoothstep(-0.05, 0.05, direction.z)
            )
        }
    }

    /// Opposite the sun on its circle, trailing by `speed` half turns, on a path
    /// tilted south by `zOffset` degrees.
    static func moonDirection(sunAngle: Float, tuning: MoonSettings) -> SIMD3<Float> {
        let angle = sunAngle + .pi - tuning.speed * .pi
        let tilt = tuning.zOffset * .pi / 180
        let up = sin(angle)
        return simd_normalize(SIMD3(cos(angle), -up * sin(tilt), up * cos(tilt)))
    }

    private static func auroras(
        _ weathers: [(weather: Weather, weight: Float)], hour: Float, sunBearing: Float,
        settings: SkySettings
    ) -> [AuroraState] {
        let night = auroraFade(hour: hour, settings: settings)
        var alphas: [String: Float] = [:]
        var yaws: [String: Float] = [:]
        var order: [String] = []
        for (weather, weight) in weathers {
            guard let model = weather.sky.auroraModel?.path, !model.isEmpty else { continue }
            let flags = weather.data?.flags ?? 0
            // DATA flag 0x10, "Always Visible", keeps the aurora up by day too.
            let fade = flags & 0x10 != 0 ? 1 : night
            if alphas[model] == nil {
                order.append(model)
            }
            alphas[model, default: 0] += weight * fade
            // DATA flag 0x20, "Follows Sun Position".
            if flags & 0x20 != 0 {
                yaws[model] = sunBearing
            }
        }
        return order.compactMap { model in
            let alpha = min(alphas[model] ?? 0, 1)
            guard alpha > 0.001 else { return nil }
            return AuroraState(model: model, alpha: alpha, yaw: yaws[model] ?? 0)
        }
    }

    /// 0 by day, 1 by night, with linear fades in the evening and the morning.
    public static func auroraFade(hour: Float, settings: SkySettings) -> Float {
        let hour = wrapHour(hour)
        if let time = progress(hour, settings.auroraFadeInStart, settings.auroraFadeIn) {
            return time
        }
        if let time = progress(hour, settings.auroraFadeOutStart, settings.auroraFadeOut) {
            return 1 - time
        }
        return progress(hour, settings.auroraFadeIn, settings.auroraFadeOutStart) == nil ? 0 : 1
    }

    /// How far `hour` is through [start, end), wrapping at midnight; nil outside it.
    static func progress(_ hour: Float, _ start: Float, _ end: Float) -> Float? {
        let length = wrapHour(end - start)
        guard length > 0 else { return nil }
        let into = wrapHour(hour - start)
        return into < length ? into / length : nil
    }

    static func wrapHour(_ hour: Float) -> Float {
        guard hour.isFinite else { return 0 }
        let wrapped = hour.truncatingRemainder(dividingBy: 24)
        return wrapped < 0 ? wrapped + 24 : wrapped
    }

    private static func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let time = simd_clamp((value - lower) / (upper - lower), 0, 1)
        return time * time * (3 - 2 * time)
    }
}

/// The sun's circle: east (+X) at the sunrise midpoint, highest at midday, west at the
/// sunset midpoint, and down to `fSunZExtreme` at midnight.
nonisolated struct SunPath {
    let hour: Float
    let rise: Float
    let set: Float
    let settings: SkySettings

    init(hour: Float, timing: Climate.Timing?, settings: SkySettings) {
        self.hour = hour
        (rise, set) = TimeOfDayWeights.horizonHours(timing: timing)
        self.settings = settings
    }

    var isDay: Bool {
        hour >= rise && hour <= set
    }

    /// 0 at sunrise, pi at sunset, 2 pi at the next sunrise.
    var angle: Float {
        if isDay {
            return .pi * (hour - rise) / (set - rise)
        }
        let night = CelestialSky.wrapHour(hour - set) / (24 - (set - rise))
        return .pi * (1 + night)
    }

    func position(reach: Float) -> SIMD3<Float> {
        let angle = angle
        let height = isDay ? reach * sin(angle) : -settings.sunZExtreme * sin(angle)
        return SIMD3(reach * cos(angle), -settings.sunYExtreme, height)
    }

    func discAlpha(fadeHours: Float) -> Float {
        guard isDay else { return 0 }
        guard fadeHours > 0 else { return 1 }
        return simd_clamp(min(hour - rise, set - hour) / fadeHours, 0, 1)
    }
}
