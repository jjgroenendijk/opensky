// Combat-loop readout lines, formatted in the engine target so a unit test can check
// them without a window: one line per fighting actor with its phase, distance, health
// and regard for the player. See docs/engine/combat.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface

/// One fighting actor as the readout shows it.
nonisolated public struct CombatActorReadout: Equatable, Sendable {
    public let key: ReferenceKey
    /// FULL name when one resolves, else the editor ID, else the FormID.
    public let name: String
    public let phase: CombatBehaviorPhase
    /// How aware it is of the player right now.
    public let awareness: DetectionState
    /// Distance to the player, world units.
    public let distance: Float
    /// Its health over its maximum, 0 through 1.
    public let healthFraction: Float
    /// Attacks started, contact steps reached, guards raised and searches begun
    /// since it first fought.
    public let attackCount: Int
    public let contactCount: Int
    public let blockCount: Int
    public let searchCount: Int
    /// Casts begun since it first fought, and how many spells it could cast from here now.
    public let castCount: Int
    public let spellOptionCount: Int

    public init(
        key: ReferenceKey,
        name: String,
        phase: CombatBehaviorPhase,
        awareness: DetectionState,
        distance: Float,
        healthFraction: Float,
        attackCount: Int,
        contactCount: Int,
        blockCount: Int,
        searchCount: Int,
        castCount: Int = 0,
        spellOptionCount: Int = 0
    ) {
        self.key = key
        self.name = name
        self.phase = phase
        self.awareness = awareness
        self.distance = distance
        self.healthFraction = healthFraction
        self.attackCount = attackCount
        self.contactCount = contactCount
        self.blockCount = blockCount
        self.searchCount = searchCount
        self.castCount = castCount
        self.spellOptionCount = spellOptionCount
    }
}

nonisolated public enum CombatLoopReadout: Sendable {
    /// One incoming hit as a trace line.
    public static func traceLine(for hit: CombatIncomingHit) -> String {
        let blocked = hit.damage.wasBlocked
            ? String(format: ", blocked %.0f%%", hit.damage.blockedFraction * 100)
            : ""
        let reaction = hit.playedReaction ? "" : ", no reaction played"
        return "attack \(hit.attackID) from \(hit.aggressor)"
            + String(format: ": %.1f damage", hit.damage.applied)
            + blocked + reaction
    }
}
