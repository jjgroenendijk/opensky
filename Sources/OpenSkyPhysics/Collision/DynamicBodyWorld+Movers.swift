// Loose bodies shoved by a reference a script moves, such as a `TranslateTo` platform.
// See docs/engine/papyrus-translation.md.

public import simd

/// A reference box that moves at a set velocity and has no physics body of its own.
nonisolated public struct ScriptedMover: Equatable, Sendable {
    /// Where the box stands, without scale.
    public let placement: float4x4
    public let minimum: SIMD3<Float>
    public let maximum: SIMD3<Float>
    public let velocity: SIMD3<Float>

    public init(
        placement: float4x4, minimum: SIMD3<Float>, maximum: SIMD3<Float>,
        velocity: SIMD3<Float>
    ) {
        self.placement = placement
        self.minimum = simd_min(minimum, maximum)
        self.maximum = simd_max(minimum, maximum)
        self.velocity = velocity
    }
}

nonisolated extension DynamicBodyWorld {
    /// A mover has no mass and cannot be stopped, so a body it touches keeps up with it
    /// along its path. A body already faster that way is left alone. Returns the bodies
    /// pushed.
    @discardableResult
    public mutating func push(by mover: ScriptedMover) -> Int {
        let speed = simd_length(mover.velocity)
        guard speed > Float.ulpOfOne, speed.isFinite else { return 0 }
        let direction = mover.velocity / speed
        let toLocal = mover.placement.inverse
        var pushed = 0
        for index in bodies.indices {
            let body = bodies[index]
            let local = toLocal * SIMD4(body.position, 1)
            let reach = SIMD3<Float>(repeating: body.definition.boundingRadius)
            let point = SIMD3(local.x, local.y, local.z)
            guard
                all(point .>= mover.minimum - reach), all(point .<= mover.maximum + reach)
            else { continue }
            let behind = speed - simd_dot(body.linearVelocity, direction)
            guard behind > 0 else { continue }
            bodies[index].applyImpulse(
                direction * behind * body.definition.mass, at: body.position
            )
            pushed += 1
        }
        return pushed
    }
}
