// Where the sun, the moons, the stars, and the aurora are at one hour and day, and how
// strongly each shows. Pure: the clock, the climate, the weathers, and the GMSTs go in.
// The model and its sources: docs/engine/celestial-sky.md.

import Foundation
public import OpenSkyFormatsESM
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
    /// The weathers' `DATA` Sun Glare, 0 to 1, without the glare sprite's floor.
    public var weatherGlare: Float
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
        at time: (hour: Float, daysPassed: Float),
        climate: Climate?,
        weathers: [(weather: Weather, weight: Float)],
        settings: SkySettings
    ) -> CelestialSky {
        let daysPassed = time.daysPassed
        let hour = wrapHour(time.hour)
        let path = SunPath(hour: hour, timing: climate?.timing, settings: settings)
        let sun = simd_normalize(path.disc)
        let glare = weathers.reduce(Float(0)) { $0 + ($1.weather.data?.sunGlare ?? 0) * $1.weight }
        let rotation = settings.starsRotateDays > 0 ? daysPassed / settings.starsRotateDays : 0
        let axisLength = simd_length(settings.starsRotateAxis)
        return CelestialSky(
            sunDirection: sun,
            lightDirection: -lightSource(path.lightSource),
            sunAlpha: path.discAlpha,
            glareScale: max(settings.sunMinimumGlareScale, glare),
            weatherGlare: glare,
            starsAxis: axisLength > 1e-6 ? settings.starsRotateAxis / axisLength : SIMD3(0, 0, 1),
            // Negative turn: a star on the east horizon climbs, as the sun does.
            starsAngle: -2 * .pi * (rotation - rotation.rounded(.down)),
            moons: moons(climate: climate, days: daysPassed, settings),
            auroras: auroras(
                weathers, hour: hour, sunBearing: atan2(sun.y, sun.x), settings: settings
            ),
            sunTexture: climate?.sunTexture,
            glareTexture: climate?.glareTexture,
            nightSkyModel: climate?.nightSkyModel
        )
    }

    /// Kept above the horizon and above the lowest elevation, for settings that would
    /// put the light below it.
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
        climate: Climate?, days: Float, _ settings: SkySettings
    ) -> [MoonState] {
        guard let timing = climate?.timing else { return [] }
        let present: [(Moon, MoonSettings)] = [
            timing.masser ? (.masser, settings.masser) : nil,
            timing.secunda ? (.secunda, settings.secunda) : nil
        ].compactMap(\.self)
        let distance = max(abs(settings.sunXExtreme), 1)
        return present.map { moon, tuning in
            let angle = moonPathAngle(daysPassed: days, tuning: tuning)
            let phaseDays = moonPhaseDays(daysPassed: days, pathAngle: angle, tuning: tuning)
            return MoonState(
                moon: moon,
                phase: MoonPhase.at(daysPassed: phaseDays, phaseLengthDays: timing.phaseLengthDays),
                direction: moonDirection(pathAngle: angle, tuning: tuning),
                halfSize: tuning.size * 0.5 / distance,
                alpha: moonFade(pathAngle: angle, tuning: tuning)
            )
        }
    }

    /// Radians along the moon's path from where it rises: `speed` times 60 degrees per game
    /// hour, at the top at midnight of day 0 (observed, docs/engine/celestial-sky.md#moons).
    static func moonPathAngle(daysPassed: Float, tuning: MoonSettings) -> Float {
        let degrees = Double(tuning.speed) * 1440 * Double(daysPassed) + 90
        return Float(degrees.truncatingRemainder(dividingBy: 360) * .pi / 180)
    }

    /// A moon changes phase only while it is hidden, so one in its visible arc keeps the
    /// phase of the moment it rose past its fade end.
    static func moonPhaseDays(daysPassed: Float, pathAngle: Float, tuning: MoonSettings) -> Float {
        let degrees = pathAngle * 180 / .pi
        guard tuning.speed > 0, degrees > tuning.fadeEnd, degrees < 180 - tuning.fadeEnd else {
            return daysPassed
        }
        return daysPassed - (degrees - tuning.fadeEnd) / (tuning.speed * 1440)
    }

    /// A circle tilted east by `zOffset` degrees: it rises north of east, is highest in
    /// the east, and sets south of east.
    static func moonDirection(pathAngle: Float, tuning: MoonSettings) -> SIMD3<Float> {
        let tilt = tuning.zOffset * .pi / 180
        return SIMD3(sin(tilt), cos(tilt) * cos(pathAngle), cos(tilt) * sin(pathAngle))
    }

    /// 0 below the fade end and 1 above the fade start, by the moon's height along its
    /// path, not by its elevation.
    static func moonFade(pathAngle: Float, tuning: MoonSettings) -> Float {
        let height = asin(simd_clamp(sin(pathAngle), -1, 1)) * 180 / .pi
        let span = tuning.fadeStart - tuning.fadeEnd
        guard span > 0 else { return height > tuning.fadeEnd ? 1 : 0 }
        return simd_clamp((height - tuning.fadeEnd) / span, 0, 1)
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
}

/// The sun's path: a triangle from the east horizon (+X) up to `fSunXExtreme` overhead
/// and down to the west, `fSunYExtreme` north. By night it runs back east unseen.
/// See docs/engine/celestial-sky.md#the-sun-path.
nonisolated struct SunPath {
    let hour: Float
    /// Where the disc starts and ends its day run: the horizon hours widened by half the fade.
    let start: Float
    let end: Float
    let fadeHours: Float
    let settings: SkySettings

    init(hour: Float, timing: Climate.Timing?, settings: SkySettings) {
        self.hour = hour
        let (rise, set) = TimeOfDayWeights.horizonHours(timing: timing)
        fadeHours = max(settings.sunAlphaTransTime, 0)
        start = rise - fadeHours / 2
        end = set + fadeHours / 2
        self.settings = settings
    }

    var isDay: Bool {
        hour > start && hour < end
    }

    /// 1 in the east, 0 overhead, -1 in the west; by night it runs from -1 back to 1.
    var progress: Float {
        let day = end - start
        guard day > 0, day < 24 else { return 1 }
        if isDay {
            return 1 - 2 * (hour - start) / day
        }
        return 2 * CelestialSky.wrapHour(hour - end) / (24 - day) - 1
    }

    var disc: SIMD3<Float> {
        let east = settings.sunXExtreme * progress
        return SIMD3(east, settings.sunYExtreme, abs(settings.sunXExtreme) - abs(east))
    }

    /// Where the light comes from: the disc's east-west place scaled by `fSunDirXExtreme`,
    /// at the fixed height `-fSunZExtreme`, so the light stays steep.
    var lightSource: SIMD3<Float> {
        let scale = settings.sunXExtreme != 0 ? settings.sunDirXExtreme / settings.sunXExtreme : 0
        return SIMD3(disc.x * scale, settings.sunYExtreme * scale, -settings.sunZExtreme)
    }

    var discAlpha: Float {
        guard isDay else { return 0 }
        guard fadeHours > 0 else { return 1 }
        return simd_clamp(min(hour - start, end - hour) / fadeHours, 0, 1)
    }
}
