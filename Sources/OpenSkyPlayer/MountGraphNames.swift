// The graph names of mounting, riding, and dismounting. Read from the install's
// `0_master.hkx`, the horse's `horsebehavior.hkx`, and `dragonbehavior.hkx`
// (docs/engine/riding.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyWorldInterface

nonisolated public enum MountGraphNames: Sendable {
    /// The rider's graph sends this when its half of the paired mount clip ends.
    public static let pairedStop = "pairedStop"
    /// The bone a rider's root sits on: `SaddleBone` in the horse skeleton,
    /// `NPC Saddlebone` in the dragon skeleton.
    public static let saddleBones = ["SaddleBone", "NPC Saddlebone"]

    /// `iCombatStance` and its two transitions (`ActorGraphNames`).
    public static let combatStance = ActorGraphNames.combatStance
    public static let combatStanceStart = ActorGraphNames.combatStanceStart
    public static let combatStanceStop = ActorGraphNames.combatStanceStop

    /// A still horse rears up on the jump key; a moving one jumps forward.
    public static let standingRearUp = "standingRearUp"
    public static let forwardJumpStart = "forwardJumpStart"

    /// The `iCombatStance` value of a stance.
    public static func combatStanceValue(_ combat: Bool) -> Int32 {
        combat ? 1 : 0
    }

    /// The event a change of stance raises, or nil when it did not change.
    public static func combatStanceEvent(from old: Bool, to new: Bool) -> String? {
        guard old != new else { return nil }
        return new ? combatStanceStart : combatStanceStop
    }
}
