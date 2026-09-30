// How a launched projectile moves: a pure function of numbers, with no world,
// clock, or collision. With no drag the step is the exact closed form
// `p(t) = p0 + v0 t + a t^2 / 2`, so apex and drop are checkable. PROJ `gravity`
// multiplies `PhysicsStep.gravity`; the census that settles it is in
// docs/engine/projectiles.md.

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
}

nonisolated public enum ProjectileFlight: Sendable {
    /// Engine units per second squared. The same constant the player capsule
    /// and every dynamic body fall under.
    public static let worldGravity = PhysicsStep.gravity

    /// The downward acceleration this profile flies under, world units per
    /// second squared.
    public static func acceleration(of profile: ProjectileProfile) -> SIMD3<Float> {
        SIMD3(0, 0, -worldGravity * profile.gravityFactor)
    }

    /// The state a shot starts in.
    /// - Parameters:
    ///   - origin: the muzzle, world space.
    ///   - direction: the aim ray, normalized here; zero length launches along +X.
    ///   - profile: the PROJ's flight numbers.
    ///   - speedScale: the launch speed factor for a partial draw; 1 is full.
    public static func launch(
        from origin: SIMD3<Float>,
        along direction: SIMD3<Float>,
        profile: ProjectileProfile,
        speedScale: Float = 1
    ) -> ProjectileFlightState {
        let scale = speedScale.isFinite ? max(0, speedScale) : 1
        return ProjectileFlightState(
            position: origin,
            velocity: normalized(direction) * profile.speed * scale
        )
    }

    /// One step of flight. Exact for the constant acceleration this model
    /// carries, so the result does not depend on how the caller subdivided the
    /// frame.
    public static func step(
        _ state: ProjectileFlightState,
        profile: ProjectileProfile,
        dt: Float
    ) -> ProjectileFlightState {
        guard dt.isFinite, dt > 0 else { return state }
        let acceleration = acceleration(of: profile)
        let displacement = state.velocity * dt + acceleration * (0.5 * dt * dt)
        var next = state
        next.position = state.position + displacement
        next.velocity = state.velocity + acceleration * dt
        next.travelled = state.travelled + simd_length(displacement)
        next.age = state.age + dt
        return next
    }

    /// The greatest height a shot reaches above its launch point, world units.
    /// Zero for a level or descending shot. Closed form, for the readout and
    /// for the trajectory the acceptance test pins.
    public static func apexHeight(
        of launch: ProjectileFlightState,
        profile: ProjectileProfile
    ) -> Float {
        let acceleration = -acceleration(of: profile).z
        guard acceleration > 0, launch.velocity.z > 0 else { return 0 }
        return launch.velocity.z * launch.velocity.z / (2 * acceleration)
    }

    /// How far a shot has fallen below the straight line it was aimed along,
    /// after `time` seconds. Closed form: the whole of the deviation is the
    /// `½at²` term, because the launch velocity *is* the aim line.
    public static func drop(of profile: ProjectileProfile, after time: Float) -> Float {
        guard time.isFinite, time > 0 else { return 0 }
        return 0.5 * worldGravity * profile.gravityFactor * time * time
    }

    /// The same, at a horizontal distance rather than at a time. Nil when the
    /// shot has no horizontal speed to cover the distance with.
    ///
    /// Reported against the horizontal component so that "drop at 1000 units"
    /// means what an archer means by it — how far below the reticle the arrow
    /// lands on a level shot — rather than how far it fell along its own arc.
    public static func drop(
        of profile: ProjectileProfile,
        atHorizontalDistance distance: Float,
        launchDirection: SIMD3<Float>
    ) -> Float? {
        let direction = normalized(launchDirection)
        let horizontalSpeed = simd_length(SIMD2(direction.x, direction.y)) * profile.speed
        guard horizontalSpeed > 0, distance.isFinite, distance >= 0 else { return nil }
        return drop(of: profile, after: distance / horizontalSpeed)
    }

    /// A unit vector, with a documented answer for the degenerate input.
    public static func normalized(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(direction)
        guard length.isFinite, length > Float.ulpOfOne else { return SIMD3(1, 0, 0) }
        return direction / length
    }

    /// The aim ray for a shot: the camera's forward direction rotated up by
    /// `tiltDegrees` about the horizontal axis perpendicular to it.
    ///
    /// The tilt is a rotation of the whole ray rather than an addition to its
    /// pitch, so a shot aimed straight down is tilted by the same angle as one
    /// aimed level instead of wrapping past vertical.
    public static func aimDirection(
        cameraForward: SIMD3<Float>,
        tiltDegrees: Float
    ) -> SIMD3<Float> {
        let forward = normalized(cameraForward)
        guard tiltDegrees.isFinite, tiltDegrees != 0 else { return forward }
        // The axis to pitch about is the horizontal right vector. A ray aimed
        // exactly along the world's up axis has none, and is left untilted:
        // there is no "up" left to tilt it toward.
        let right = simd_cross(forward, SIMD3<Float>(0, 0, 1))
        let length = simd_length(right)
        guard length > Float.ulpOfOne else { return forward }
        let rotation = simd_quatf(
            angle: tiltDegrees * Float.pi / 180, axis: right / length
        )
        return normalized(rotation.act(forward))
    }
}
