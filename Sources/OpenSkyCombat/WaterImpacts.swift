// What happens where an actor or a loose body meets water: a splash where it enters,
// a splash where an explosion goes off at the surface, and a knockdown in fast water.
// Values in, values out (docs/engine/impulses.md#water).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

nonisolated public struct WaterImpactSettings: Equatable, Sendable {
    /// `sSplashParticles`: the model a splash shows.
    public var splashModel = "Effects\\waterSplash.nif"
    /// `sExplosionSplashParticles`: the model an explosion at the surface shows.
    public var explosionSplashModel = "Effects\\ExplosionSplash.nif"
    /// `fSplashSoundLight`, `...Medium`, `...Heavy`: kilograms a body needs for each sound.
    public var splashSoundLight: Float = 5
    public var splashSoundMedium: Float = 20
    public var splashSoundHeavy: Float = 35
    /// `fExplosionSplashRadius`: a blast this close to the surface splashes.
    public var explosionSplashRadius: Float = 250
    /// `fExplosionWaterRadiusRatio`: what a blast under water keeps of its radius.
    public var explosionWaterRadiusRatio: Float = 0.1
    /// `fWaterKnockdownVelocity`: the flow speed that knocks a normal actor down, times
    /// the size factor.
    public var knockdownVelocity: Float = 5
    /// `fWaterKnockdownSizeSmall`, `...Normal`, `...Large`, `...VeryLarge`, by RACE size.
    public var knockdownSizeFactors: [Float] = [0.6, 0.75, 1.25, 1.5]

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore, text: GameTextResolver) -> Self {
        var settings = vanilla
        store.read("sSplashParticles", into: &settings, \.splashModel, text: text)
        store.read("sExplosionSplashParticles", into: &settings, \.explosionSplashModel, text: text)
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fSplashSoundLight", \.splashSoundLight),
            ("fSplashSoundMedium", \.splashSoundMedium),
            ("fSplashSoundHeavy", \.splashSoundHeavy),
            ("fExplosionSplashRadius", \.explosionSplashRadius),
            ("fExplosionWaterRadiusRatio", \.explosionWaterRadiusRatio),
            ("fWaterKnockdownVelocity", \.knockdownVelocity),
            ("fWaterKnockdownSizeSmall", \.knockdownSizeFactors[0]),
            ("fWaterKnockdownSizeNormal", \.knockdownSizeFactors[1]),
            ("fWaterKnockdownSizeLarge", \.knockdownSizeFactors[2]),
            ("fWaterKnockdownSizeVeryLarge", \.knockdownSizeFactors[3])
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        return settings
    }
}

/// How loud a splash is.
nonisolated public enum SplashWeight: String, Equatable, Sendable {
    /// Too light for any splash sound; the model still shows.
    case silent
    case light, medium, heavy
}

/// One splash to show and play.
nonisolated public struct SplashEvent: Equatable, Sendable {
    /// What went in, or nil for an explosion.
    public let source: ReferenceKey?
    /// On the water surface.
    public let position: SIMD3<Float>
    public let model: String
    public let weight: SplashWeight
}

/// One actor or body, as the splash test sees it this frame.
nonisolated public struct WaterSample: Equatable, Sendable {
    public let key: ReferenceKey
    public let position: SIMD3<Float>
    /// Kilograms, or nil for an actor, which always splashes heavy.
    public let mass: Float?
    /// The surface height here, or nil where there is no water.
    public let waterHeight: Float?

    public init(key: ReferenceKey, position: SIMD3<Float>, mass: Float?, waterHeight: Float?) {
        self.key = key
        self.position = position
        self.mass = mass
        self.waterHeight = waterHeight
    }

    var isUnderwater: Bool {
        waterHeight.map { position.z < $0 } ?? false
    }

    /// In the water and less than `wadingDepth` below its surface, so it stirs it.
    var isWading: Bool {
        waterHeight.map { position.z < $0 && position.z > $0 - Self.wadingDepth } ?? false
    }

    /// Feet deeper than this swim under the surface; OpenSky's value.
    static let wadingDepth: Float = 150
}

nonisolated public enum WaterImpacts {
    public static func weight(mass: Float?, settings: WaterImpactSettings) -> SplashWeight {
        guard let mass else { return .heavy }
        if mass >= settings.splashSoundHeavy {
            return .heavy
        }
        if mass >= settings.splashSoundMedium {
            return .medium
        }
        return mass >= settings.splashSoundLight ? .light : .silent
    }

    /// A splash for an explosion within `fExplosionSplashRadius` of the surface.
    public static func explosionSplash(
        at center: SIMD3<Float>, waterHeight: Float?, settings: WaterImpactSettings
    ) -> SplashEvent? {
        guard
            let waterHeight, abs(center.z - waterHeight) <= settings.explosionSplashRadius
        else { return nil }
        return SplashEvent(
            source: nil, position: SIMD3(center.x, center.y, waterHeight),
            model: settings.explosionSplashModel, weight: .heavy
        )
    }

    /// The radius a blast reaches with: shrunk by `fExplosionWaterRadiusRatio` under water.
    public static func explosionRadius(
        _ radius: Float, at center: SIMD3<Float>, waterHeight: Float?,
        settings: WaterImpactSettings
    ) -> Float {
        guard let waterHeight, center.z < waterHeight else { return radius }
        return radius * max(settings.explosionWaterRadiusRatio, 0)
    }

    /// Whether flowing water of `flowSpeed` knocks down an actor of RACE `size`
    /// (0 small, 1 normal, 2 large, 3 very large).
    public static func knocksDown(
        flowSpeed: Float, raceSize: Int, settings: WaterImpactSettings
    ) -> Bool {
        let factors = settings.knockdownSizeFactors
        guard !factors.isEmpty, flowSpeed.isFinite, settings.knockdownVelocity > 0
        else { return false }
        let factor = factors[min(max(raceSize, 0), factors.count - 1)]
        return flowSpeed >= settings.knockdownVelocity * factor
    }
}

/// Remembers who was under water last frame, so each entry splashes once.
nonisolated public struct SplashTracker: Equatable, Sendable {
    private var underwater: Set<ReferenceKey> = []
    private var seen: Set<ReferenceKey> = []

    public init() {}

    /// The splashes of the samples that went under since the last call. A key seen for
    /// the first time never splashes: it may have loaded in the water.
    public mutating func update(
        _ samples: [WaterSample], settings: WaterImpactSettings
    ) -> [SplashEvent] {
        var events: [SplashEvent] = []
        var nowUnder: Set<ReferenceKey> = []
        for sample in samples {
            let under = sample.isUnderwater
            if under {
                nowUnder.insert(sample.key)
            }
            guard
                under, seen.contains(sample.key), !underwater.contains(sample.key),
                let height = sample.waterHeight
            else { continue }
            events.append(SplashEvent(
                source: sample.key,
                position: SIMD3(sample.position.x, sample.position.y, height),
                model: settings.splashModel,
                weight: WaterImpacts.weight(mass: sample.mass, settings: settings)
            ))
        }
        underwater = nowUnder
        seen = Set(samples.map(\.key))
        return events
    }
}
