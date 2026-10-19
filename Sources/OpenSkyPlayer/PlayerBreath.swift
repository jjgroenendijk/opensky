// How long the player can stay under water, and the health a dive costs after that.
// The settings are on the CK wiki "Category:Settings" page. See docs/engine/walk-mode.md.

import OpenSkyGameData

/// The breath game settings. `Skyrim.esm` holds no `fActorSwimBreathBase`, so its CK
/// wiki default applies.
nonisolated public struct BreathSettings: Equatable, Sendable {
    /// `fActorSwimBreathBase`: seconds under water before drowning starts.
    public var breathSeconds: Float = 10
    /// `fActorSwimBreathDamage`: the fraction of the maximum health lost each second.
    public var damageFraction: Float = 0.08

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fActorSwimBreathBase", into: &settings, \.breathSeconds)
        store.read("fActorSwimBreathDamage", into: &settings, \.damageFraction)
        return settings
    }
}

/// The breath the player has left. It refills at once when the head leaves the water.
nonisolated public struct PlayerBreath: Equatable, Sendable {
    public let settings: BreathSettings
    public private(set) var remainingSeconds: Float
    public private(set) var isSubmerged = false

    public init(settings: BreathSettings = .vanilla) {
        self.settings = settings
        remainingSeconds = settings.breathSeconds
    }

    /// The eyes are below the water surface.
    public static func isSubmerged(eyeZ: Float, waterSurface: Float?) -> Bool {
        guard let waterSurface else { return false }
        return eyeZ < waterSurface
    }

    /// Spends `seconds` of breath under water and returns the health lost this step.
    /// Water breathing keeps the full breath.
    public mutating func advance(
        seconds: Float, submerged: Bool, waterBreathing: Bool, maximumHealth: Float
    ) -> Float {
        isSubmerged = submerged
        guard submerged, !waterBreathing, seconds.isFinite, seconds > 0 else {
            remainingSeconds = settings.breathSeconds
            return 0
        }
        let drowning = max(0, seconds - remainingSeconds)
        remainingSeconds = max(0, remainingSeconds - seconds)
        return drowning * settings.damageFraction * max(0, maximumHealth)
    }
}
