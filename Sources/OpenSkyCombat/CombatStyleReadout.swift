// The combat readout's style lines: an actor's resolved CSTY and the settings its
// machine runs on, next to the base values. See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyCombatInterface

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
                + "cast: %.0f%% (base %.0f%%), from range: %.0f%% (base %.0f%%)",
            derived.attackIntervalSeconds, base.attackIntervalSeconds,
            derived.blockChance * 100, base.blockChance * 100,
            derived.castChance * 100, base.castChance * 100,
            derived.rangedCastChance * 100, base.rangedCastChance * 100
        )
    }
}

nonisolated extension CombatStyleReadout {
    /// The game settings this actor's style picks, or that they are off.
    public func gameSettingsText(_ combatAI: CombatAISettings, isOn: Bool) -> String {
        guard isOn else { return "Game combat settings: off (OpenSky's numbers)" }
        let settings = combatAI.applyingRanges(to: base, tuning: tuning)
        let flight = settings.flight
        return String(
            format: "Advance: walk inside %.0f u, back off to %.0f u, weapon hold x%.2f, "
                + "absolute x%.0f · heal below %.0f%% · shout aim %.1f s within %.0f deg "
                + "(retry %.0f s)\nFlight: orbit %.0f u, air %.1f s, perch %.1f s "
                + "(%.0f%%), ground %.1f s",
            settings.walkRadius, settings.backOffRadius, settings.weaponRangeHoldMult,
            settings.weaponAbsoluteRangeMult, settings.restoreHealthFraction * 100,
            settings.shoutAimSeconds, settings.shoutToleranceRadians * 180 / .pi,
            settings.shoutRetrySeconds, flight.orbitDistance, flight.airSeconds,
            flight.perchSeconds, flight.perchChance * 100, flight.groundSeconds
        )
    }
}
