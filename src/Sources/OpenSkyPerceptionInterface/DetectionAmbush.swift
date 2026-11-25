// Who an observer that runs an Ambush package waits for. See
// docs/engine/detection.md#ambush-packages.

import simd

/// The ambush target data of an observer's running Ambush package (`PKDT` type 9).
nonisolated public enum DetectionAmbushArea: Equatable, Sendable {
    /// No target data: every target is the ambush target.
    case everyone
    /// A place and a radius round it.
    case within(center: SIMD3<Float>, radius: Float)
    /// Target data OpenSky does not match yet, such as a reference or an object type.
    case unmatched

    /// Whether a target standing at `feet` is the ambush target.
    public func contains(_ feet: SIMD3<Float>) -> Bool {
        switch self {
        case .everyone: true
        case let .within(center, radius): simd_distance(center, feet) <= max(0, radius)
        case .unmatched: false
        }
    }
}

/// What an ambush package makes of one target.
nonisolated public enum DetectionAmbushRole: Equatable, Sendable {
    case target
    case other
}
