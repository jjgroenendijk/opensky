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
