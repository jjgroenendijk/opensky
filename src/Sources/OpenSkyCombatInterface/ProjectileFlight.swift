import OpenSkyGameData
import OpenSkyPhysics
import simd

/// Where a projectile is, right now.
nonisolated public struct ProjectileFlightState: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    /// Path length travelled since launch, world units. This is what `range` is
    /// compared against, not the straight-line distance from the muzzle: an
    /// arrow lobbed in an arc has travelled further than it has displaced, and
    /// `range` bounds the flight rather than the reach.
    public var travelled: Float = 0
    /// Seconds since launch, what `lifetime` is compared against.
    public var age: Float = 0

    public init(
        position: SIMD3<Float>,
        velocity: SIMD3<Float>,
        travelled: Float = 0,
        age: Float = 0
    ) {
        self.position = position
        self.velocity = velocity
        self.travelled = travelled
        self.age = age
    }
}
