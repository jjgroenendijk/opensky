// The GMSTs that place and fade the sun, the moons, the stars, and the aurora.
// Fallbacks are the values the Creation Kit settings list gives
// (https://ck.uesp.net/wiki/Category:Settings). See docs/engine/celestial-sky.md.

import Foundation
import OpenSkyGameData

nonisolated public struct SkySettings: Equatable, Sendable {
    /// Sun path in sky units: east-west reach and midday height, and offset north.
    public var sunXExtreme: Float = 400
    public var sunYExtreme: Float = 40
    /// The light source's fixed height, negated.
    public var sunZExtreme: Float = -150
    /// East-west reach of the light's source; smaller than `sunXExtreme`, so light stays steeper.
    public var sunDirXExtreme: Float = 200
    public var sunMinimumGlareScale: Float = 0.25
    /// Game hours the sun disc takes to fade in and out, centred on the horizon hours.
    public var sunAlphaTransTime: Float = 0.5
    public var masser = MoonSettings(size: 90, fadeStart: 35, fadeEnd: 20, speed: 0.25, zOffset: 35)
    public var secunda = MoonSettings(
        size: 40, fadeStart: 35, fadeEnd: 20, speed: 0.3, zOffset: 50
    )
    public var starsRotateDays: Float = 1.0027
    public var starsRotateAxis = SIMD3<Float>(-0.09, 0.35, 1)
    /// Hours: the aurora fades in from `fadeInStart` to `fadeIn`, and out from
    /// `fadeOutStart` to `fadeOut`.
    public var auroraFadeInStart: Float = 19
    public var auroraFadeIn: Float = 20
    public var auroraFadeOutStart: Float = 5
    public var auroraFadeOut: Float = 6
    /// How many times faster an accelerated weather change runs.
    public var weatherTransAccel: Float = 16

    public static let vanilla = SkySettings()

    public init() {}

    /// Reads each setting the store holds; a missing or broken one keeps its fallback.
    public static func resolve(store: GameSettingStore) -> SkySettings {
        var settings = SkySettings()
        func read(_ editorID: String, _ keyPath: WritableKeyPath<SkySettings, Float>) {
            if let value = store.number(editorID) {
                settings[keyPath: keyPath] = value
            }
        }
        read("fSunXExtreme", \.sunXExtreme)
        read("fSunYExtreme", \.sunYExtreme)
        read("fSunZExtreme", \.sunZExtreme)
        read("fSunDirXExtreme", \.sunDirXExtreme)
        read("fSunMinimumGlareScale", \.sunMinimumGlareScale)
        read("fSunAlphaTransTime", \.sunAlphaTransTime)
        read("iMasserSize", \.masser.size)
        read("fMasserAngleFadeStart", \.masser.fadeStart)
        read("fMasserAngleFadeEnd", \.masser.fadeEnd)
        read("fMasserSpeed", \.masser.speed)
        read("fMasserZOffset", \.masser.zOffset)
        read("iSecundaSize", \.secunda.size)
        read("fSecundaAngleFadeStart", \.secunda.fadeStart)
        read("fSecundaAngleFadeEnd", \.secunda.fadeEnd)
        read("fSecundaSpeed", \.secunda.speed)
        read("fSecundaZOffset", \.secunda.zOffset)
        read("fStarsRotateDays", \.starsRotateDays)
        read("fStarsRotateXAxis", \.starsRotateAxis.x)
        read("fStarsRotateYAxis", \.starsRotateAxis.y)
        read("fStarsRotateZAxis", \.starsRotateAxis.z)
        read("fAuroraFadeInStart", \.auroraFadeInStart)
        // The game spells these two "Autora".
        read("fAutoraFadeIn", \.auroraFadeIn)
        read("fAuroraFadeOutStart", \.auroraFadeOutStart)
        read("fAutoraFadeOut", \.auroraFadeOut)
        read("fWeatherTransAccel", \.weatherTransAccel)
        return settings
    }
}

nonisolated public struct MoonSettings: Equatable, Sendable {
    /// Width of the moon in sky units, on the same scale as the sun path.
    public var size: Float
    /// Degrees of height along the moon's path: it starts to fade at `fadeStart` and is
    /// gone at `fadeEnd`.
    public var fadeStart: Float
    public var fadeEnd: Float
    /// Times 60: degrees along its path the moon moves per game hour.
    public var speed: Float
    /// Degrees the moon's path tilts toward the east.
    public var zOffset: Float

    public init(size: Float, fadeStart: Float, fadeEnd: Float, speed: Float, zOffset: Float) {
        self.size = size
        self.fadeStart = fadeStart
        self.fadeEnd = fadeEnd
        self.speed = speed
        self.zOffset = zOffset
    }
}
