// The graph names of mounting, riding, and dismounting. Read from the install's
// `0_master.hkx`, the horse's `horsebehavior.hkx`, and `dragonbehavior.hkx`
// (docs/engine/riding.md).

import Foundation
import OpenSkyActorPresentation

/// The events that move a rider and its mount through a mount or a dismount.
nonisolated public struct MountGraphEvents: Equatable, Sendable {
    /// Raised on the rider: plays its half of the paired mount clip.
    public let riderEnter: String
    /// Raised on the mount: plays its half, with the `2_` tracks.
    public let mountEnter: String
    public let riderExit: String
    public let mountExit: String
    /// The rider's graph sends this when the dismount clip ends.
    public let riderExitDone: String

    /// `HorseEnter` leads to the `MountSynced` state of `0_master.hkx`, and
    /// `HorseExit` from `HorseRider_State` to `DismountSynced`.
    public static let horse = MountGraphEvents(
        riderEnter: "HorseEnter", mountEnter: "pa_HorseEnter",
        riderExit: "HorseExit", mountExit: "pa_HorseExit", riderExitDone: "HorseExitOut"
    )
    /// `DragonMountEnter` leads to `DragonMountSynced`, and `DragonMountExit` from
    /// `DragonRider_State` to `DragonDismountSynced`.
    public static let dragon = MountGraphEvents(
        riderEnter: "DragonMountEnter", mountEnter: "pa_DragonMountEnter",
        riderExit: "DragonMountExit", mountExit: "pa_DragonMountExit",
        riderExitDone: "DragonMountExitOut"
    )
}

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
