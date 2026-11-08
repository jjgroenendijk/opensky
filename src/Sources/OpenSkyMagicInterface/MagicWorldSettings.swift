// Game settings for how magic meets the world: the absorb visual, the ward cap, and
// where a cone projectile stops. See docs/engine/magic-archetypes.md and
// docs/engine/spell-delivery.md.

import Foundation
public import OpenSkyGameData

nonisolated public struct MagicWorldSettings: Equatable, Sendable {
    /// `fMagicAbsorbVisualTimer`: seconds an instant Absorb hit keeps its visual.
    public var absorbVisualSeconds: Float = 2.5
    /// `fMagicWardPowerMaxBase` and `fMagicWardPowerMaxMult`: the most ward power an
    /// actor holds, as a share of its strongest ward (`wardPowerCap`).
    public var wardPowerMaxBase: Float = 1.3
    public var wardPowerMaxMult: Float = 0
    /// `fConeProjectileEnvironmentDistance`: how far ahead a cone looks for a wall, units.
    public var coneEnvironmentDistance: Float = 192
    /// `fConeProjectileEnvironmentTimer`: seconds between two of those looks.
    public var coneEnvironmentTimer: Float = 0.125

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fMagicAbsorbVisualTimer", into: &settings, \.absorbVisualSeconds)
        store.read("fMagicWardPowerMaxBase", into: &settings, \.wardPowerMaxBase)
        store.read("fMagicWardPowerMaxMult", into: &settings, \.wardPowerMaxMult)
        store.read("fConeProjectileEnvironmentDistance", into: &settings, \.coneEnvironmentDistance)
        store.read("fConeProjectileEnvironmentTimer", into: &settings, \.coneEnvironmentTimer)
        return settings
    }

    /// The ward power cap: `strongest * (base + mult * skill)`, where `strongest` is the
    /// largest running ward magnitude and `skill` the holder's Restoration. No source gives
    /// the form; the names say a maximum with a base and a multiplier.
    public func wardPowerCap(strongest: Float, skill: Float) -> Float {
        let share = wardPowerMaxBase + wardPowerMaxMult * (skill.isFinite ? max(0, skill) : 0)
        guard strongest.isFinite, share.isFinite else { return .infinity }
        return max(0, strongest * share)
    }
}
