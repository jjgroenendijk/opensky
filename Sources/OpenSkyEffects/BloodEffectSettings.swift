// The game settings of blood: the splatters a hit puts on the screen, the blood a
// weapon keeps after a hit, and the default blood models and decal. The wiki gives
// values but no rules, so each use is OpenSky's reading
// (docs/rendering/visual-effects.md#blood).

import Foundation
import OpenSkyGameData

nonisolated public struct BloodEffectSettings: Equatable, Sendable {
    /// `fBloodSplatterCountBase`: splatters every hit places.
    public var countBase: Float = 2
    /// `fBloodSplatterCountDamageBase`: damage above this adds splatters.
    public var countDamageBase: Float = 0
    /// `fBloodSplatterCountDamageMult`: splatters per point of that damage.
    public var countDamageMult: Float = 0.1
    /// `fBloodSplatterCountRandomMargin`: the count varies by up to this, up or down.
    public var countRandomMargin: Float = 1
    /// `iBloodSplatterMaxCount`: at most this many show at once.
    public var maxCount = 25
    /// `fBloodSplatterDuration`, in seconds.
    public var duration: Float = 20
    /// `fBloodSplatterFadeStart`: the share of the duration before the fade starts.
    public var fadeStart: Float = 0.4
    /// `fBloodSplatterMinSize`, `...MaxSize`: the share of the screen height.
    public var minSize: Float = 0.12
    public var maxSize: Float = 0.18
    /// `fBloodSplatterMinOpacity`, `...MaxOpacity`.
    public var minOpacity: Float = 0.5
    public var maxOpacity: Float = 1
    /// `fBloodSplatterMinOpacity2`, `...MaxOpacity2`: the fainter range.
    public var minOpacity2: Float = 0.3
    public var maxOpacity2: Float = 0.6
    /// `fBloodSplatterOpacityChance`: the chance a splatter takes the fainter range.
    public var opacityChance: Float = 0.3
    /// `fBloodSplatterFlareSize`: the flare's share of the screen height.
    public var flareSize: Float = 0.065
    /// `fBloodSplatterFlareMult`: the flare's opacity, times its splatter's.
    public var flareMult: Float = 0.95
    /// `fBloodSplatterFlareOffsetScale`: the flare's offset, in splatter sizes.
    public var flareOffsetScale: Float = 0.45
    /// `fWeaponBloodLifetime`: seconds the weapon blood stays full.
    public var weaponBloodLifetime: Float = 10
    /// `fWeaponBloodFadeDuration`: seconds it then takes to fade.
    public var weaponBloodFadeDuration: Float = 60
    /// `fWeaponBloodFalloffThreshold`: below this strength the blood is gone.
    public var weaponBloodFalloffThreshold: Float = 0.07
    /// `sBloodSplatterColor01OPTFilename`, `...Alpha01OPT...`, `sBloodSplatterFlare01Filename`.
    public var splatterColorTexture = "Textures\\Blood\\ScreenBloodColor01OPT.dds"
    public var splatterAlphaTexture = "Textures\\Blood\\ScreenBloodAlpha01OPT.dds"
    public var flareTexture = "Textures\\Blood\\FXBloodFlare.dds"
    /// `sBloodParticleDefault` and `sBloodParticleMeleeDefault`: empty in `Skyrim.esm`.
    public var particleModel = ""
    public var meleeParticleModel = ""
    /// `sBloodTextureDefault`: the decal under a hit with no impact data.
    public var decalTexture = "Blood\\DecalsBloodSplatterBlend01.dds"
    /// `sDismemberParticleDefault`: the cut's model when the race has none. Empty in
    /// `Skyrim.esm`.
    public var dismemberParticleModel = ""

    public static let vanilla = Self()

    public init() {}

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        let numbers: [(String, WritableKeyPath<Self, Float>)] = [
            ("fBloodSplatterCountBase", \.countBase),
            ("fBloodSplatterCountDamageBase", \.countDamageBase),
            ("fBloodSplatterCountDamageMult", \.countDamageMult),
            ("fBloodSplatterCountRandomMargin", \.countRandomMargin),
            ("fBloodSplatterDuration", \.duration),
            ("fBloodSplatterFadeStart", \.fadeStart),
            ("fBloodSplatterMinSize", \.minSize),
            ("fBloodSplatterMaxSize", \.maxSize),
            ("fBloodSplatterMinOpacity", \.minOpacity),
            ("fBloodSplatterMaxOpacity", \.maxOpacity),
            ("fBloodSplatterMinOpacity2", \.minOpacity2),
            ("fBloodSplatterMaxOpacity2", \.maxOpacity2),
            ("fBloodSplatterOpacityChance", \.opacityChance),
            ("fBloodSplatterFlareSize", \.flareSize),
            ("fBloodSplatterFlareMult", \.flareMult),
            ("fBloodSplatterFlareOffsetScale", \.flareOffsetScale),
            ("fWeaponBloodLifetime", \.weaponBloodLifetime),
            ("fWeaponBloodFadeDuration", \.weaponBloodFadeDuration),
            ("fWeaponBloodFalloffThreshold", \.weaponBloodFalloffThreshold)
        ]
        for (editorID, keyPath) in numbers {
            store.read(editorID, into: &settings, keyPath)
        }
        store.read("iBloodSplatterMaxCount", into: &settings, \.maxCount)
        let strings: [(String, WritableKeyPath<Self, String>)] = [
            ("sBloodSplatterColor01OPTFilename", \.splatterColorTexture),
            ("sBloodSplatterAlpha01OPTFilename", \.splatterAlphaTexture),
            ("sBloodSplatterFlare01Filename", \.flareTexture),
            ("sBloodParticleDefault", \.particleModel),
            ("sBloodParticleMeleeDefault", \.meleeParticleModel),
            ("sBloodTextureDefault", \.decalTexture),
            ("sDismemberParticleDefault", \.dismemberParticleModel)
        ]
        for (editorID, keyPath) in strings {
            store.read(editorID, into: &settings, keyPath, text: text)
        }
        return settings
    }

    /// The Effects readout's settings line.
    public var readout: String {
        String(
            format: "Blood settings: up to %d splatters · %.0f s, fading after %.0f%% · "
                + "size %.2f-%.2f · weapon blood %.0f s + %.0f s fade",
            maxCount, duration, fadeStart * 100, minSize, maxSize,
            weaponBloodLifetime, weaponBloodFadeDuration
        )
    }
}
