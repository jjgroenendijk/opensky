// The rules of blood that lasts: the splatters on the screen after the player is hit,
// and the blood on a weapon after it hits. Pure, so a test can drive them
// (docs/rendering/visual-effects.md#blood).

import OpenSkyFormatsCore
import OpenSkyRendering
import simd

/// The splatters on the screen. Each hit on the player adds some; each one fades.
nonisolated public struct ScreenBloodRuntime: Equatable, Sendable {
    nonisolated public struct Splatter: Equatable, Sendable {
        /// Screen position, 0-1 on each axis, y down.
        public var center: SIMD2<Float>
        /// The share of the screen height.
        public var size: Float
        public var opacity: Float
        public var rotation: Float
        /// Where the flare sits, in splatter sizes from the centre.
        public var flareOffset: SIMD2<Float>
        public var age: Float = 0
    }

    public var settings = BloodEffectSettings.vanilla
    /// The graphics option; off places none.
    public var enabled = true
    public private(set) var splatters: [Splatter] = []
    private var random: SplitMix64

    public init(settings: BloodEffectSettings = .vanilla, seed: UInt64 = SplitMix64.increment) {
        self.settings = settings
        random = SplitMix64(seed: seed)
    }

    /// How many splatters a hit of `damage` places, before the cap.
    public static func count(
        damage: Float, settings: BloodEffectSettings, roll: Float
    ) -> Int {
        let extra = max(damage - settings.countDamageBase, 0) * settings.countDamageMult
        let margin = settings.countRandomMargin * (roll * 2 - 1)
        let count = (settings.countBase + extra + margin).rounded()
        return count.isFinite ? max(Int(min(count, 1000)), 0) : 0
    }

    /// Places the splatters of one hit. Returns how many were added.
    @discardableResult
    public mutating func splatter(damage: Float) -> Int {
        let room = max(settings.maxCount - splatters.count, 0)
        let added = min(
            Self.count(damage: damage, settings: settings, roll: random.unitFloat()),
            room
        )
        for _ in 0 ..< added {
            splatters.append(makeSplatter())
        }
        return added
    }

    public mutating func advance(_ seconds: Float) {
        guard seconds > 0 else { return }
        for index in splatters.indices {
            splatters[index].age += seconds
        }
        splatters.removeAll { $0.age >= settings.duration }
    }

    public mutating func removeAll() {
        splatters.removeAll()
    }

    /// The share of its opacity a splatter of `age` keeps: whole until the fade starts,
    /// then falling evenly to nothing at the duration.
    public func fade(age: Float) -> Float {
        guard settings.duration > 0 else { return 0 }
        let unit = age / settings.duration
        let start = min(max(settings.fadeStart, 0), 1)
        guard unit > start else { return 1 }
        guard start < 1 else { return 0 }
        return max(1 - (unit - start) / (1 - start), 0)
    }

    /// This frame's quads for the renderer: each splatter, then its flare.
    public var draws: [ScreenBloodSplat] {
        splatters.flatMap { splatter -> [ScreenBloodSplat] in
            let opacity = splatter.opacity * fade(age: splatter.age)
            guard opacity > 0 else { return [] }
            let flareCenter = splatter.center + splatter.flareOffset * splatter.size
            return [
                ScreenBloodSplat(
                    center: splatter.center, size: splatter.size,
                    rotation: splatter.rotation, opacity: opacity, layer: .splatter
                ),
                ScreenBloodSplat(
                    center: flareCenter, size: settings.flareSize,
                    rotation: splatter.rotation, opacity: opacity * settings.flareMult,
                    layer: .flare
                )
            ]
        }
    }

    private mutating func makeSplatter() -> Splatter {
        let faint = random.unitFloat() < settings.opacityChance
        let opacity = faint
            ? lerp(settings.minOpacity2, settings.maxOpacity2)
            : lerp(settings.minOpacity, settings.maxOpacity)
        let angle = random.unitFloat() * 2 * .pi
        return Splatter(
            center: SIMD2(lerp(0.1, 0.9), lerp(0.1, 0.9)),
            size: lerp(settings.minSize, settings.maxSize),
            opacity: min(max(opacity, 0), 1),
            rotation: random.unitFloat() * 2 * .pi,
            flareOffset: SIMD2(cos(angle), sin(angle)) * settings.flareOffsetScale
        )
    }

    private mutating func lerp(_ low: Float, _ high: Float) -> Float {
        low + (high - low) * random.unitFloat()
    }
}

/// The blood on each weapon that hit a bleeding actor, by the weapon's holder.
nonisolated public struct WeaponBloodRuntime: Equatable, Sendable {
    public var settings = BloodEffectSettings.vanilla
    public private(set) var ages: [MembraneTarget: Float] = [:]

    public init(settings: BloodEffectSettings = .vanilla) {
        self.settings = settings
    }

    /// A new hit: the blood on `weapon` is fresh again.
    public mutating func bloody(_ weapon: MembraneTarget) {
        ages[weapon] = 0
    }

    public mutating func advance(_ seconds: Float) {
        guard seconds > 0 else { return }
        for key in ages.keys {
            ages[key, default: 0] += seconds
        }
        ages = ages.filter { strength(age: $0.value) > 0 }
    }

    /// Whole for `fWeaponBloodLifetime`, then fading over `fWeaponBloodFadeDuration`;
    /// gone below `fWeaponBloodFalloffThreshold`.
    public func strength(age: Float) -> Float {
        let fading = age - settings.weaponBloodLifetime
        let value = fading <= 0 ? 1
            : settings.weaponBloodFadeDuration > 0
            ? 1 - fading / settings.weaponBloodFadeDuration : 0
        return value < settings.weaponBloodFalloffThreshold ? 0 : min(value, 1)
    }

    /// The blood strength of each bloody weapon, which scales its blood shapes' alpha.
    public var strengths: [MembraneTarget: Float] {
        ages.mapValues(strength(age:))
    }
}
