import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public enum KnockdownPhase: Equatable, Sendable {
    /// On the ground, with the seconds left before it gets up anyway.
    case down(remaining: Float)
    /// Getting up: the ragdoll pose fades out over `duration` seconds.
    case gettingUp(elapsed: Float, duration: Float)
}
