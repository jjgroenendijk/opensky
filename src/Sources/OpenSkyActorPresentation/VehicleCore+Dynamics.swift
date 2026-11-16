// A towed cart's motion along its tow line: the hitch holds the shaft tip with some play,
// so the cart lags a horse that starts, rolls on after one that stops, and rolls back on a
// slope. Its front axle swings toward the horse rather than snapping. See
// docs/engine/vehicles.md#towing and docs/engine/cart-tow-rig.md.

import OpenSkyFormatsMesh
import OpenSkyWorldInterface
import simd

/// The tow line's spring and the wheels' drag. The game builds this from Havok bodies and
/// joints; these values give its observed lag and roll (docs/engine/unverified-values.md).
nonisolated public struct VehicleTowSpring: Equatable, Sendable {
    /// How fast the line springs back to its length, in radians per second.
    public var frequency: Float = 6
    public var damping: Float = 0.35
    /// How far the shaft tip may move along the line from its rest place.
    public var play: Float = 24
    /// The share of its speed the cart loses each second by wheel friction.
    public var rolling: Float = 0.4
    /// The front axle's swing toward the horse.
    public var swingFrequency: Float = 7
    public var swingDamping: Float = 0.5
    /// Gravity, in units per second squared.
    public var gravity: Float = 9.81 * NIFCollisionModel.havokToEngineScale
    /// The longest step of the solver, in seconds.
    public var step: Float = 1.0 / 120

    public static let vanilla = Self()

    public init() {}
}

/// One frame of the tow line: how far the cart is past the link's length, where its front
/// axle points and should point, and how the hitch and the ground move it.
nonisolated struct VehicleTowInput {
    var stretch: Float
    var heading: Float
    var target: Float
    /// The hitch's speed along the line.
    var hitchSpeed: Float
    /// The rise of the ground per unit along the line toward the hitch.
    var grade: Float
}

nonisolated extension VehicleCore {
    /// The cart's distance past the link's length after `dt`, and its front axle's heading.
    static func towStep(
        _ motion: inout VehicleTowMotion, _ input: VehicleTowInput, dt: Float,
        spring: VehicleTowSpring = .vanilla
    ) -> (stretch: Float, heading: Float) {
        guard dt > 0, dt.isFinite else { return (input.stretch, input.target) }
        let steps = max(1, Int((dt / spring.step).rounded(.up)))
        let tick = dt / Float(steps)
        let stiffness = spring.frequency * spring.frequency
        let damping = 2 * spring.damping * spring.frequency
        let swingStiffness = spring.swingFrequency * spring.swingFrequency
        let swingDamping = 2 * spring.swingDamping * spring.swingFrequency
        let slope = -spring.gravity * input.grade / (1 + input.grade * input.grade).squareRoot()
        var stretch = input.stretch
        var heading = input.heading
        for _ in 0 ..< steps {
            let pull = stiffness * stretch + damping * (input.hitchSpeed - motion.speed)
            motion.speed += (pull + slope - spring.rolling * motion.speed) * tick
            stretch += (input.hitchSpeed - motion.speed) * tick
            if abs(stretch) > spring.play {
                stretch = stretch > 0 ? spring.play : -spring.play
                motion.speed = input.hitchSpeed
            }
            let error = wrapped(input.target - heading)
            motion.swing += (swingStiffness * error - swingDamping * motion.swing) * tick
            heading = wrapped(heading + motion.swing * tick)
        }
        return (stretch, heading)
    }
}

nonisolated extension VehicleCore {
    /// The follower's distance behind the hitch this frame, after the tow line's spring;
    /// sets `tow.heading`. Without `dt`, the link's length and the heading toward the hitch.
    /// The follower moves along the line from where it was toward the hitch.
    static func towDistance(
        _ tow: inout VehicleTow, hitch: SIMD4<Float>, ground: (SIMD3<Float>) -> Float?,
        dt: Float
    ) -> Float {
        let flat = SIMD2(hitch.x - tow.position.x, hitch.y - tow.position.y)
        let target = simd_length(flat) > 0.001 ? atan2(flat.x, flat.y) : tow.heading
        let here = SIMD3(hitch.x, hitch.y, hitch.z)
        defer { tow.motion.hitch = here }
        guard dt > 0, dt.isFinite, let last = tow.motion.hitch else {
            tow.heading = target
            return tow.length
        }
        let line = SIMD2(sin(target), cos(target))
        let moved = here - last
        let hitchSpeed = simd_dot(SIMD2(moved.x, moved.y), line) / dt
        let top = max(tow.position.z, hitch.z) + groundSearchHeight
        let rise = slope(
            from: ground(SIMD3(tow.position.x, tow.position.y, top)),
            to: ground(SIMD3(hitch.x, hitch.y, top)), tow.length
        )
        let input = VehicleTowInput(
            stretch: simd_length(flat) - tow.length, heading: tow.heading, target: target,
            hitchSpeed: hitchSpeed, grade: tan(rise)
        )
        let step = towStep(&tow.motion, input, dt: dt)
        tow.heading = step.heading
        return tow.length + step.stretch
    }
}
