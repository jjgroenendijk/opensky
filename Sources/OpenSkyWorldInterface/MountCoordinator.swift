import Foundation
public import OpenSkyFormatsESM
import simd

nonisolated public enum MountCommand: Equatable, Sendable {
    /// Links the player to the mount's root, for the paired clips.
    case boardPlayer(ReferenceKey)
    /// Links the player's root to the saddle bone.
    case seatPlayer(ReferenceKey, bone: String)
    case detachPlayer
    /// Stands the player at `feet`, facing walk yaw `yaw`.
    case placePlayer(feet: SIMD3<Float>, yaw: Float)
    case raiseOnPlayer(String)
    case steerMount(ReferenceKey, feet: SIMD3<Float>, yaw: Float)
    case reportMountEvents(ReferenceKey, [String])
    /// Gives the mount back to its packages and its graph runner.
    case releaseMount(ReferenceKey)
    /// Riding somebody else's horse is a theft: ask first, with `sStealHorse`.
    case askToSteal(ReferenceKey)
    case reportTheft(ReferenceKey)
    case refused(MountRefusal)
    /// A short message on screen, such as the landing order.
    case notify(String)
    /// The ridden dragon breathes at its locked target.
    case dragonBreath(ReferenceKey, at: ReferenceKey)
}

nonisolated public enum MountPhase: Equatable, Sendable {
    case none
    case mounting(elapsed: Float)
    case riding
    case dismounting(elapsed: Float)
}
