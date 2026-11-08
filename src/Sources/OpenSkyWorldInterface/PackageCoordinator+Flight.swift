public import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// Where a flying actor's package sends it.
nonisolated public enum PackageFlightTarget: Equatable, Sendable {
    case point(SIMD3<Float>)
    /// The furniture of a sit procedure, which for a dragon is a perch.
    case perch(ReferenceKey)
}
