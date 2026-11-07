// What happens where an actor or a loose body meets water: a splash where it enters,
// a splash where an explosion goes off at the surface, and a knockdown in fast water.
// Values in, values out (docs/engine/impulses.md#water).

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

nonisolated public struct WaterImpactSettings: Equatable, Sendable {
    /// `sSplashParticles`: the model a splash shows.
    public var splashModel = "Effects\\waterSplash.nif"
    /// `sExplosionSplashParticles`: the model an explosion at the surface shows.
    public var explosionSplashModel = "Effects\\ExplosionSplash.nif"
    /// `fSplashSoundLight`, `...Medium`, `...Heavy`: the splash value each sound needs.
    public var splashSoundLight: Float = 5
    public var splashSoundMedium: Float = 20
    public var splashSoundHeavy: Float = 35
    /// `fSplashSoundVelocityMult`: the splash value per unit a second of vertical speed.
    public var splashVelocityMult: Float = 0.05
    /// `fSplashSoundOutMult`: a body leaving the water splashes this much.
    public var splashOutMult: Float = 0.5
    /// `fSplashSoundTimer`: seconds between two splashes anywhere.
    public var splashTimer: Float = 0.25
    /// `fSplashScale1` to `3`: the particle scale of a heavy, medium and light splash.
    public var splashScales: [Float] = [1, 0.75, 0.4]
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
            ("fSplashSoundVelocityMult", \.splashVelocityMult),
            ("fSplashSoundOutMult", \.splashOutMult),
            ("fSplashSoundTimer", \.splashTimer),
            ("fSplashScale1", \.splashScales[0]),
            ("fSplashScale2", \.splashScales[1]),
            ("fSplashScale3", \.splashScales[2]),
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

    /// The `SNDR` the splash plays.
    public var sound: String? {
        switch self {
        case .silent: nil
        case .light: "CWaterSmall"
        case .medium: "CWaterMedium"
        case .heavy: "CWaterLarge"
        }
    }
}

/// One splash to show and play.
nonisolated public struct SplashEvent: Equatable, Sendable {
    /// What went in, or nil for an explosion.
    public let source: ReferenceKey?
    /// On the water surface.
    public let position: SIMD3<Float>
    public let model: String
    public let weight: SplashWeight
    /// The particle scale.
    public var scale: Float = 1
}

/// One actor or body, as the splash test sees it this frame.
nonisolated public struct WaterSample: Equatable, Sendable {
    public let key: ReferenceKey
    public let position: SIMD3<Float>
    /// Kilograms, or nil for an actor, which always splashes heavy.
    public let mass: Float?
    /// The surface height here, or nil where there is no water.
    public let waterHeight: Float?
    /// Units a second upward.
    public let verticalSpeed: Float

    public init(
        key: ReferenceKey, position: SIMD3<Float>, mass: Float?, waterHeight: Float?,
        verticalSpeed: Float = 0
    ) {
        self.key = key
        self.position = position
        self.mass = mass
        self.waterHeight = waterHeight
        self.verticalSpeed = verticalSpeed
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
    /// The knockdown speeds are in Havok units per second.
    public static let havokScale = NIFCollisionModel.havokToEngineScale

    /// The splash a body makes: its mass plus `fSplashSoundVelocityMult` times its vertical
    /// speed, times `fSplashSoundOutMult` when it leaves. An actor splashes heavy.
    public static func weight(
        mass: Float?, verticalSpeed: Float = 0, leaving: Bool = false,
        settings: WaterImpactSettings
    ) -> SplashWeight {
        guard let mass else { return .heavy }
        var value = mass + settings.splashVelocityMult * abs(verticalSpeed)
        if leaving {
            value *= settings.splashOutMult
        }
        if value > settings.splashSoundHeavy {
            return .heavy
        }
        if value > settings.splashSoundMedium {
            return .medium
        }
        return value > settings.splashSoundLight ? .light : .silent
    }

    /// The particle scale of a splash of `weight`.
    public static func scale(of weight: SplashWeight, settings: WaterImpactSettings) -> Float {
        let scales = settings.splashScales
        return switch weight {
        case .heavy: scales.first ?? 1
        case .medium: scales.count > 1 ? scales[1] : 1
        case .light: scales.count > 2 ? scales[2] : 1
        case .silent: 1
        }
    }

    /// A splash for a blast under water: the surface above it is higher than its centre
    /// plus `fExplosionWaterRadiusRatio` of its radius. Scaled by radius over
    /// `fExplosionSplashRadius`.
    public static func explosionSplash(
        at center: SIMD3<Float>, radius: Float, waterHeight: Float?,
        settings: WaterImpactSettings
    ) -> SplashEvent? {
        guard
            let waterHeight,
            waterHeight > center.z + radius * settings.explosionWaterRadiusRatio
        else { return nil }
        var splash = SplashEvent(
            source: nil, position: SIMD3(center.x, center.y, waterHeight),
            model: settings.explosionSplashModel, weight: .heavy
        )
        splash.scale = settings.explosionSplashRadius > 0
            ? radius / settings.explosionSplashRadius : 1
        return splash
    }

    /// Whether flowing water of `flowSpeed`, in Havok units per second, knocks down
    /// an actor of RACE `size` (0 small, 1 normal, 2 large, 3 very large).
    public static func knocksDown(
        flowSpeed: Float, raceSize: Int, settings: WaterImpactSettings
    ) -> Bool {
        guard let strong = strongCurrent(raceSize: raceSize, settings: settings), flowSpeed.isFinite
        else { return false }
        return flowSpeed >= strong
    }

    /// `fWaterKnockdownVelocity` times the size factor, Havok units per second.
    public static func strongCurrent(raceSize: Int, settings: WaterImpactSettings) -> Float? {
        let factors = settings.knockdownSizeFactors
        guard !factors.isEmpty, settings.knockdownVelocity > 0 else { return nil }
        return settings.knockdownVelocity * factors[min(max(raceSize, 0), factors.count - 1)]
    }
}

/// Remembers who was under water last frame, so each crossing splashes once, and when
/// the last splash played, so splashes keep `fSplashSoundTimer` apart.
nonisolated public struct SplashTracker: Equatable, Sendable {
    private var underwater: Set<ReferenceKey> = []
    private var seen: Set<ReferenceKey> = []
    private var sinceSplash: Float = .infinity

    public init() {}

    /// The splashes of the samples that crossed the surface since the last call. A key
    /// seen for the first time never splashes: it may have loaded in the water.
    public mutating func update(
        _ samples: [WaterSample], deltaTime: Float = 0, settings: WaterImpactSettings
    ) -> [SplashEvent] {
        sinceSplash += max(deltaTime, 0)
        var events: [SplashEvent] = []
        var nowUnder: Set<ReferenceKey> = []
        for sample in samples {
            let under = sample.isUnderwater
            if under {
                nowUnder.insert(sample.key)
            }
            let wasUnder = underwater.contains(sample.key)
            guard
                under != wasUnder, seen.contains(sample.key), let height = sample.waterHeight,
                abs(sample.verticalSpeed) >= 0.001 || sample.mass == nil,
                sinceSplash >= settings.splashTimer
            else { continue }
            let weight = WaterImpacts.weight(
                mass: sample.mass, verticalSpeed: sample.verticalSpeed, leaving: !under,
                settings: settings
            )
            guard under || (sample.mass != nil && weight != .silent) else { continue }
            var event = SplashEvent(
                source: sample.key,
                position: SIMD3(sample.position.x, sample.position.y, height),
                model: settings.splashModel, weight: weight
            )
            event.scale = WaterImpacts.scale(of: weight, settings: settings)
            events.append(event)
            sinceSplash = 0
        }
        underwater = nowUnder
        seen = Set(samples.map(\.key))
        return events
    }
}
