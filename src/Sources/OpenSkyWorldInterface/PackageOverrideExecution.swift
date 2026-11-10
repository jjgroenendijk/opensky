public import OpenSkyFormatsESM
public import OpenSkyPhysics
import simd

nonisolated public enum PackageOverrideProgress: Equatable, Sendable {
    case running
    /// The procedure finished, or failed because OpenSky cannot run it yet.
    case done
    /// The actor is not simulated, for example because its cell is not loaded.
    case notSimulated
}

/// Whether a package walk started. `busy` means every mover slot is taken.
nonisolated public enum PackageMoveResult: Equatable, Sendable {
    case started
    case busy
    case failed
}

/// One package walk: where the actor goes and how. A `direct` move walks the straight
/// line on the terrain, as a static-pathing patrol does.
nonisolated public struct PackageMove: Equatable, Sendable {
    public var actor: ReferenceKey
    public var point: SIMD3<Float>
    public var direct: Bool
    public var gait: LocomotionGait?
    public var walkRunBlend: Float?

    public init(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false,
        gait: LocomotionGait? = nil, walkRunBlend: Float? = nil
    ) {
        self.actor = actor
        self.point = point
        self.direct = direct
        self.gait = gait
        self.walkRunBlend = walkRunBlend
    }
}

/// The furniture seat a sit package uses: the reference and its marker.
nonisolated public struct PackageSeat: Equatable, Sendable {
    public let furniture: ReferenceKey
    public let index: Int
    public let seat: FurnitureSeat

    public init(furniture: ReferenceKey, index: Int, seat: FurnitureSeat) {
        self.furniture = furniture
        self.index = index
        self.seat = seat
    }
}
