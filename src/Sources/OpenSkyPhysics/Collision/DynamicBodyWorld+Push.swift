// The player's shove on the clutter it walks into. See docs/engine/dynamic-bodies.md.

import simd

nonisolated extension DynamicBodyWorld {
    /// The push a moving player capsule gives the clutter it walks into. The capsule
    /// has no mass, so the shove is modeled: an overlapping body gets a horizontal
    /// impulse sized by the player's speed and the body's mass.
    public mutating func push(
        capsule: PlayerCapsule,
        feetPosition: SIMD3<Float>,
        velocity: SIMD3<Float>
    ) {
        lastPushCount = 0
        let horizontal = SIMD3<Float>(velocity.x, velocity.y, 0)
        let speed = simd_length(horizontal)
        guard speed > Float.ulpOfOne else { return }
        let segment = (
            feetPosition + SIMD3<Float>(0, 0, capsule.radius),
            feetPosition + SIMD3<Float>(0, 0, capsule.height - capsule.radius)
        )
        for index in bodies.indices {
            let body = bodies[index]
            let near = DynamicCollisionMath.closestPoint(onSegment: segment, to: body.position)
            let combined = capsule.radius + body.definition.boundingRadius
            guard simd_distance_squared(near, body.position) <= combined * combined else {
                continue
            }
            var direction = SIMD3<Float>(
                body.position.x - near.x, body.position.y - near.y, 0
            )
            let length = simd_length(direction)
            direction = length > Float.ulpOfOne ? direction / length : horizontal / speed
            // Only the component of the walk that is into the body pushes it;
            // walking away from a crate must not drag it along.
            let approach = max(0, simd_dot(horizontal, direction))
            guard approach > Float.ulpOfOne else { continue }
            let mass = body.definition.mass
            let push = approach * mass * Self.pushEfficiency
            let factor = PlayerPushFactor.factor(
                mass: mass, layer: body.definition.collisionLayer, impulse: push
            )
            guard factor > 0 else { continue }
            bodies[index].applyImpulse(direction * push * factor, at: near)
            lastPushCount += 1
        }
    }
}
