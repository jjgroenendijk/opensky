// The combat panel's style lines: an actor's resolved CSTY and the settings its
// machine runs on, next to the base values. See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM

nonisolated public struct CombatStyleReadout: Equatable, Sendable {
    public let tuning: CombatStyleTuning?
    public let base: CombatBehaviorSettings
    public let derived: CombatBehaviorSettings

    public init(tuning: CombatStyleTuning?, base: CombatBehaviorSettings) {
        self.tuning = tuning
        self.base = base
        derived = base.tuned(by: tuning)
    }

    public var styleText: String {
        guard let tuning else { return "Style: none" }
        return "Style: \(tuning.name ?? "unnamed")"
            + String(
                format: " (offense %.2f, defense %.2f, melee %.2f, magic %.2f)",
                tuning.offensiveMultiplier, tuning.defensiveMultiplier,
                tuning.meleeScoreMultiplier, tuning.magicScoreMultiplier
            )
    }

    public var settingsText: String {
        String(
            format: "Attack gap: %.2f s (base %.2f), block: %.0f%% (base %.0f%%), "
                + "cast: %.0f%% (base %.0f%%)",
            derived.attackIntervalSeconds, base.attackIntervalSeconds,
            derived.blockChance * 100, base.blockChance * 100,
            derived.castChance * 100, base.castChance * 100
        )
    }
}

extension CombatLoopRuntime {
    /// The style `key` fights with and what it makes of the base settings.
    public func styleReadout(of key: ReferenceKey) -> CombatStyleReadout {
        CombatStyleReadout(tuning: styleTuning(of: key), base: behaviorSettings)
    }
}
