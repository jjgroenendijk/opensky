// When a walk to furniture counts as arrived, and the turn to the seat's heading before
// the entry clip. See docs/engine/furniture.md#arriving-at-the-seat.

import Foundation
public import OpenSkyGameData
import OpenSkyWorldInterface
import simd

nonisolated public struct FurnitureArrivalSettings: Equatable, Sendable {
    /// `fAIFurnitureDestinationRadius`: an actor this close to its seat has arrived.
    public var destinationRadius: Float = 150
    /// `fFurnitureMarkerAngleTolerance`, in degrees: the facing error the entry clip allows.
    public var markerAngleTolerance: Float = 10

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fAIFurnitureDestinationRadius", into: &settings, \.destinationRadius)
        store.read("fFurnitureMarkerAngleTolerance", into: &settings, \.markerAngleTolerance)
        return settings
    }

    var angleToleranceRadians: Float {
        max(0, markerAngleTolerance) * .pi / 180
    }
}

/// An actor that turns to its seat's heading before it sits.
nonisolated struct FurnitureSeatTurn: Equatable {
    let seat: PackageSeat
    var seconds: Float = 0
}

nonisolated enum FurnitureArrival {
    /// A turn that takes longer than this is blocked, and the actor sits anyway.
    static let turnTimeout: Float = 3
    /// The largest height difference at which a walk still counts as arrived.
    static let heightLimit: Float = 128

    /// The larger of the furniture radius and the radius the walk asks for, with the
    /// height difference inside the limit.
    static func hasArrived(
        feet: SIMD3<Float>, seat: FurnitureSeat, askedRadius: Float,
        settings: FurnitureArrivalSettings
    ) -> Bool {
        let offset = feet - seat.root
        let flat = simd_length(SIMD2(offset.x, offset.y))
        return flat <= max(settings.destinationRadius, askedRadius)
            && abs(offset.z) <= heightLimit
    }

    /// Whether the entry clip may start: the turn left is inside the furniture angle, the
    /// actor cannot turn at all, or the turn ran out of time.
    static func mayEnter(
        remainingTurn: Float?, seconds: Float, settings: FurnitureArrivalSettings
    ) -> Bool {
        guard let remainingTurn else { return true }
        return abs(remainingTurn) <= settings.angleToleranceRadians || seconds >= turnTimeout
    }
}
