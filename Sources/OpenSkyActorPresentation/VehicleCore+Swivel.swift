// A towed cart's front axle swivels toward the horse, and its body trails behind
// that axle, so in a curve each wheel rolls its own distance. See docs/engine/vehicles.md.

import simd

/// How far each axle rolled and turned since the link, and the front axle's swivel.
/// Turns are in `angleZ` terms: clockwise from north, in radians.
nonisolated public struct VehicleWheelTurns: Equatable, Sendable {
    public var frontRolled: Float = 0
    public var rearRolled: Float = 0
    public var frontTurned: Float = 0
    public var rearTurned: Float = 0
    /// The front axle's heading less the body's.
    public var steer: Float = 0

    public init() {}

    /// The distance a wheel at model-frame `side` (its x) rolled. A wheel on the outside of
    /// a curve rolls further: turning right, the left wheel (negative x) rolls more.
    public func rolled(front: Bool, side: Float) -> Float {
        front ? frontRolled - side * frontTurned : rearRolled - side * rearTurned
    }
}

nonisolated extension VehicleCore {
    /// The game's front turntable hinge stops at 40 degrees each way.
    public static let maximumSteer: Float = 40 * .pi / 180

    /// The distance between the front and the rear axle, or 0 for one axle.
    static func wheelbase(_ wheels: [SIMD2<Float>]?) -> Float {
        guard let ys = wheels?.map(\.y), let high = ys.max(), let low = ys.min() else { return 0 }
        return high - low
    }

    /// Moves the rear axle after the front one, which moved from `tow.position` to `front`.
    static func trail(_ tow: inout VehicleTow, front: SIMD2<Float>, previousHeading: Float) {
        let base = wheelbase(tow.wheels)
        tow.turns.frontRolled = tow.rolled
        tow.turns.frontTurned += wrapped(tow.heading - previousHeading)
        guard base > 1 else {
            tow.turns.rearRolled = tow.rolled
            tow.turns.rearTurned = tow.turns.frontTurned
            tow.bodyHeading = nil
            return
        }
        let before = tow.bodyHeading ?? previousHeading
        let rear = SIMD2(tow.position.x, tow.position.y) - SIMD2(sin(before), cos(before)) * base
        let pull = front - rear
        var heading = simd_length(pull) > 0.001 ? atan2(pull.x, pull.y) : before
        let steer = min(max(wrapped(tow.heading - heading), -maximumSteer), maximumSteer)
        heading = tow.heading - steer
        let axis = SIMD2(sin(heading), cos(heading))
        tow.turns.rearRolled += simd_dot(front - axis * base - rear, axis)
        tow.turns.rearTurned += wrapped(heading - before)
        tow.turns.steer = steer
        tow.bodyHeading = heading
    }

    static func wrapped(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
    }
}
