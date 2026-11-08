import Foundation
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

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

    public init(
        source: ReferenceKey?,
        position: SIMD3<Float>,
        model: String,
        weight: SplashWeight,
        scale: Float = 1
    ) {
        self.source = source
        self.position = position
        self.model = model
        self.weight = weight
        self.scale = scale
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

    /// How strong a ripple the splash leaves on the water surface, 0 to 1.
    public var rippleStrength: Float {
        self == .heavy ? 1 : 0.6
    }
}

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
}
