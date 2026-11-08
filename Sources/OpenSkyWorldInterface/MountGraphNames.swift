import Foundation

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
