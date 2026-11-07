// A dragon out of a fight flies where its package sends it: round a point, or onto
// the perch of a sit package. See docs/engine/dragon-flight.md.

public import OpenSkyFormatsESM
import simd

/// Where the dragon's package sends it.
nonisolated public enum DragonPackageFlight: Equatable, Sendable {
    case point(SIMD3<Float>)
    case perch(ReferenceKey)
}

extension DragonFlightCoordinator {
    /// The circle round a package point; close enough to pass a trigger near it.
    public static let packageCircleRadius: Float = 1024
    /// Horizontal distance at which a package point counts as reached.
    public static let packageArrivalDistance: Float = 1536

    /// A perch that is not loaded keeps the dragon circling where it is.
    func goal(
        for candidate: DragonFlightCandidate, flight: DragonPackageFlight, perches: [DragonPerch]
    ) -> DragonFlightGoal {
        switch flight {
        case let .point(point):
            return .circle(center: point, radius: Self.packageCircleRadius)
        case let .perch(furniture):
            let perch = perches.first { $0.reference == furniture }
            return perch.map(DragonFlightGoal.perch)
                ?? .circle(center: candidate.feet, radius: Self.packageCircleRadius)
        }
    }

    static func reached(_ flight: DragonPackageFlight, state: DragonFlightState) -> Bool {
        switch flight {
        case let .point(point):
            let flat = SIMD2(state.feet.x - point.x, state.feet.y - point.y)
            return state.phase.isFlying && simd_length(flat) < packageArrivalDistance
        case let .perch(furniture):
            return state.phase == .perched && state.perch?.reference == furniture
        }
    }
}
