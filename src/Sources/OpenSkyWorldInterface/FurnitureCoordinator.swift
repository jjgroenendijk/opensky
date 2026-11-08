import Foundation
import OpenSkyFormatsESM
import simd

/// One actor in one seat.
nonisolated public struct FurnitureOccupancy: Equatable, Sendable {
    public let seat: PackageSeat
    /// The side the actor came in by: 1 front, 2 behind, 4 right, 8 left, 16 up.
    public let entry: UInt16

    public init(seat: PackageSeat, entry: UInt16) {
        self.seat = seat
        self.entry = entry
    }
}

/// Why an actor could not use a piece of furniture.
nonisolated public enum FurnitureUseRefusal: String, Error, Equatable, Sendable {
    /// The launcher switch is off.
    case disabled
    case notLoaded
    case noSeats
    case noFreeSeat
    case alreadySeated
}
