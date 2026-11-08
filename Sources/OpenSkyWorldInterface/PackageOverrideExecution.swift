public import OpenSkyFormatsESM
import OpenSkyPhysics
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
