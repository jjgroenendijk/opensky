// An NPC keeps facing its target from the start of a melee attack to its end. The aim
// is refreshed on a timer, faster for the player inside the track band.
// docs/engine/combat-assist.md#npc-attack-tracking.

import Foundation
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import simd

nonisolated public struct CombatAttackTrack: Equatable, Sendable {
    /// The track band, added to the attack's reach.
    public static let bandNear: Float = 128
    public static let bandFar: Float = 512
    /// Seconds between two refreshes of the aim, and for the priority target in the band.
    public static let refreshSeconds: Float = 0.25
    public static let priorityRefreshSeconds: Float = 0.1

    public let target: ReferenceKey
    /// Where the attacker faces: the target's place at the last refresh.
    public private(set) var aim: SIMD3<Float>
    public private(set) var sinceRefresh: Float = 0
    public private(set) var refreshes = 0

    public init(target: ReferenceKey, aim: SIMD3<Float>) {
        self.target = target
        self.aim = aim
    }

    /// Whether `distance` lies in the band of an attack with `reach`.
    public static func isInBand(distance: Float, reach: Float) -> Bool {
        distance >= reach + bandNear && distance <= reach + bandFar
    }

    /// One step of the attack. Returns the point to face.
    public mutating func advance(
        by seconds: Float, targetFeet: SIMD3<Float>, distance: Float, reach: Float
    ) -> SIMD3<Float> {
        sinceRefresh += seconds
        let fast = target == .player && Self.isInBand(distance: distance, reach: reach)
        if sinceRefresh >= (fast ? Self.priorityRefreshSeconds : Self.refreshSeconds) {
            sinceRefresh = 0
            aim = targetFeet
            refreshes += 1
        }
        return aim
    }
}

nonisolated extension CombatBehaviorPhase {
    /// From the start of the attack clip to the end of its follow-through.
    var isMeleeAttack: Bool {
        self == .windup || self == .contact || self == .recovery
    }
}
