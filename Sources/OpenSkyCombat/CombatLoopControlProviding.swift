// The combat readout's seam: the hostility toggle, combat state and target, one line per
// fighting actor, and transient counts. One snapshot value, so the readout comes from a
// single observation while a fight runs.

import Foundation
import OpenSkyCombatInterface

/// One observation of the combat loop.
nonisolated public struct CombatLoopSnapshot: Equatable, Sendable {
    /// Whether the player is in combat, and with whom.
    public let isPlayerInCombat: Bool
    /// Resident actors that are hostile and alive, and those recorded dead.
    public let hostileCount: Int
    /// Spells NPCs have finished casting this session.
    public let actorCastCount: Int
    /// Human-readable result of the last control action.
    public let lastActionText: String
    /// Whether Confidence and Assistance are on: the readout's own switch.
    public var usesTemperament = true
    /// The game's combat AI settings and whether the fight is indoors.
    public var combatAI = CombatAISettings.vanilla
    public var isInInterior = false

    /// The reading with no runtime attached.
    public static let unavailable = CombatLoopSnapshot(
        isPlayerInCombat: false,
        hostileCount: 0,
        actorCastCount: 0,
        lastActionText: "Combat unavailable: no game data loaded."
    )

    public init(
        isPlayerInCombat: Bool,
        hostileCount: Int,
        actorCastCount: Int,
        lastActionText: String
    ) {
        self.isPlayerInCombat = isPlayerInCombat
        self.hostileCount = hostileCount
        self.actorCastCount = actorCastCount
        self.lastActionText = lastActionText
    }
}
