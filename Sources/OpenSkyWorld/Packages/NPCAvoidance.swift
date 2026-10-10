// Local steering so walking actors pass each other instead of walking through. Actors
// are not collision shapes, so this bends the walk direction around a neighbour ahead
// and pushes apart two that overlap. OpenSky's own rule; see docs/engine/navigation.md.

import OpenSkyFormatsESM
import simd

/// Another actor a mover should not walk through.
nonisolated public struct NPCNeighbour: Equatable, Sendable {
    public let key: ReferenceKey
    /// Feet, in the XY plane.
    public let position: SIMD2<Float>
    public let radius: Float

    public init(key: ReferenceKey, position: SIMD2<Float>, radius: Float) {
        self.key = key
        self.position = position
        self.radius = radius
    }
}

nonisolated public enum NPCAvoidance {
    /// Space kept between two capsules, world units.
    public static let margin: Float = 8
    /// How far ahead, past touching, a neighbour starts to bend the walk.
    public static let lookahead: Float = 96

    /// The unit walk direction after steering around `neighbours`. A neighbour dead
    /// ahead is passed on the right, so two actors walking at each other both turn right
    /// and pass. Returns `direction` when nothing is in the way.
    public static func steer(
        direction: SIMD2<Float>,
        from position: SIMD2<Float>,
        radius: Float,
        neighbours: [NPCNeighbour]
    ) -> SIMD2<Float> {
        guard simd_length_squared(direction) > 0 else { return direction }
        let forward = simd_normalize(direction)
        let left = SIMD2(-forward.y, forward.x)
        var push = SIMD2<Float>.zero
        for neighbour in neighbours {
            let offset = neighbour.position - position
            let distance = simd_length(offset)
            let clearance = radius + neighbour.radius + margin
            guard distance.isFinite, distance < clearance + lookahead else { continue }
            if distance < clearance {
                // Overlapping: straight apart, harder the deeper. Same spot: to the right.
                let away = distance > 0.001 ? -offset / distance : -left
                push += away * (2 - distance / clearance)
                continue
            }
            let ahead = simd_dot(offset, forward)
            let lateral = simd_dot(offset, left)
            guard ahead > 0, abs(lateral) < clearance else { continue }
            let nearness = 1 - (distance - clearance) / lookahead
            push += (lateral >= 0 ? -left : left) * nearness
        }
        let steered = forward + push
        guard simd_length_squared(steered) > 0.0001 else { return forward }
        return simd_normalize(steered)
    }

    /// True when a neighbour stands on `waypoint` and the mover is as close as it can get.
    /// A marker taken by another actor counts as reached, or both would wait forever.
    public static func isTaken(
        _ waypoint: SIMD2<Float>,
        from position: SIMD2<Float>,
        radius: Float,
        tolerance: Float,
        neighbours: [NPCNeighbour]
    ) -> Bool {
        neighbours.contains { neighbour in
            let reach = radius + neighbour.radius + margin
            return simd_distance(neighbour.position, waypoint) < reach
                && simd_distance(position, waypoint) <= reach + tolerance
        }
    }
}
