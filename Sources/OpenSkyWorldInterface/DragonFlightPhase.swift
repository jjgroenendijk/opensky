import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// The `GetFlyingState` values (<https://ck.uesp.net/wiki/GetFlyingState_-_Actor>).
nonisolated public enum DragonFlightPhase: Int32, Equatable, Sendable, CaseIterable {
    case grounded = 0
    case takingOff = 1
    case cruising = 2
    case hovering = 3
    case landing = 4
    /// Sitting on a perch: a word wall, a tower, or a rock.
    case perched = 5

    /// `GetIsFlying`: 1 until the landing on the ground is done. A perch has no navmesh,
    /// so a perched dragon still counts.
    public var isFlying: Bool {
        self != .grounded
    }
}

/// A landing the engine asks for, which `GetIsHastyLandRequest` and
/// `GetIsCrashLandRequest` report. It lands at once, without the long approach.
nonisolated public enum DragonLandingRequest: String, Equatable, Sendable {
    case none
    case hasty
    case crash
}

/// A dragon perch: furniture whose `MNAM` marks it as one, such as `DragonPerchTower`.
nonisolated public struct DragonPerch: Equatable, Sendable {
    public let reference: ReferenceKey
    /// Where the dragon's feet go.
    public let feet: SIMD3<Float>
    /// The walk yaw the perch faces, counter-clockwise from +X.
    public let yaw: Float

    public init(reference: ReferenceKey, feet: SIMD3<Float>, yaw: Float) {
        self.reference = reference
        self.feet = feet
        self.yaw = yaw
    }
}
