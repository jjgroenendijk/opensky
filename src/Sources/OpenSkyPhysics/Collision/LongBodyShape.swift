// A character longer than it is tall, such as a horse: two end spheres beside its upright
// capsule, sized from the skeleton's `BBX` bound. See docs/engine/character-shapes.md.

import OpenSkyFormatsCore
import simd

nonisolated extension PlayerCapsule {
    /// The game's capsule for an upright body, from its skeleton's `BBX` half size; nil
    /// for a long body. The eye keeps the standard capsule's share of the height.
    public static func upright(halfExtents: SIMD3<Float>, scale: Float = 1) -> PlayerCapsule? {
        let size = halfExtents * (scale > 0 && scale.isFinite ? scale : 1)
        guard size.min() > 0, size.z >= max(size.x, size.y) else { return nil }
        let height = size.z * 2
        return PlayerCapsule(
            radius: (size.x + size.y) / 2, height: height,
            eyeHeight: height * standard.eyeHeight / standard.height
        )
    }
}

nonisolated public struct LongBodyShape: Equatable, Sendable {
    /// Along the model's long axis: true for +Y (forward), false for +X (right).
    public let isForwardLong: Bool
    /// From the centre to each end sphere's centre, along the long axis.
    public let endOffset: Float
    public let endRadius: Float
    /// The body capsule along the long axis: its radius, the height of its axis above the
    /// feet, and the half length of its segment.
    public let bodyRadius: Float
    public let bodyHeight: Float
    public let bodyHalfLength: Float
    /// The ends ride this far above the ground, so an obstacle the walk steps over does not
    /// stop them.
    public var stepHeight: Float = 0

    /// The half size the game uses for a skeleton without a `BBX` bound.
    public static let missingBoundHalfExtents = SIMD3<Float>(repeating: 25)

    /// Ends sit this far inside the long capsule's segment ends.
    public static let endInset: Float = 8

    /// Nil for an upright body, and for a long one thick enough for one capsule.
    public init?(halfExtents: SIMD3<Float>, scale: Float = 1) {
        let size = halfExtents * (scale > 0 && scale.isFinite ? scale : 1)
        let long = max(size.x, size.y)
        guard long > size.z, size.min() > 0 else { return nil }
        let other = min(size.x, size.y)
        let radius = min(other, size.z)
        let thickest = max(other, size.z)
        guard radius < 0.75 * thickest else { return nil }
        isForwardLong = size.y >= size.x
        endRadius = thickest - radius
        endOffset = max(long - radius - Self.endInset, 0)
        bodyRadius = radius
        bodyHeight = thickest - radius + thickest
        bodyHalfLength = max(long - radius, 0)
    }

    private func axis(yaw: Float) -> SIMD2<Float> {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        return isForwardLong ? forward : SIMD2(forward.y, -forward.x)
    }

    /// The feet of each end sphere's short capsule. `yaw` is counter-clockwise from +X.
    public func endFeet(at feet: SIMD3<Float>, yaw: Float, lift: Float) -> [SIMD3<Float>] {
        let axis = axis(yaw: yaw)
        return [1, -1].map { (side: Float) in
            let point = SIMD2(feet.x, feet.y) + axis * endOffset * side
            return SIMD3(point.x, point.y, feet.z + lift)
        }
    }

    public var endCapsule: PlayerCapsule {
        .ball(radius: endRadius)
    }

    /// The body capsule as a row of balls along its segment, no more than one radius apart,
    /// so a beam that passes between two of them still meets one.
    public func bodyBallFeet(at feet: SIMD3<Float>, yaw: Float) -> [SIMD3<Float>] {
        let axis = axis(yaw: yaw)
        let gaps = max(1, Int(ceilf(2 * bodyHalfLength / max(bodyRadius, 1))))
        return (0 ... gaps).map { index in
            let along = -bodyHalfLength + 2 * bodyHalfLength * Float(index) / Float(gaps)
            let point = SIMD2(feet.x, feet.y) + axis * along
            return SIMD3(point.x, point.y, feet.z + bodyHeight - bodyRadius)
        }
    }

    /// The horizontal change to `displacement` that keeps the ends and the body out of
    /// `query`'s shapes. Each end stands on the ground under it, from `ground`, and follows
    /// that ground. Only the push a move adds over standing still counts, so the slope an
    /// end stands on does not push the body back.
    func correction(
        pose: (feet: SIMD3<Float>, yaw: Float), displacement: SIMD2<Float>,
        ground: (SIMD2<Float>) -> Float?, query: CapsuleWorldCollider.CandidateQuery
    ) -> SIMD2<Float> {
        largestPush(pose: pose, displacement: displacement, ground: ground, query: query).added
    }

    /// The part whose push `correction` returns, with the push it meets standing still.
    public func largestPush(
        pose: (feet: SIMD3<Float>, yaw: Float), displacement: SIMD2<Float>,
        ground: (SIMD2<Float>) -> Float?, query: CapsuleWorldCollider.CandidateQuery
    ) -> LongBodyPush {
        let (feet, yaw) = pose
        var largest = LongBodyPush()
        func keepLarger(_ push: LongBodyPush) {
            if simd_length_squared(push.added) > simd_length_squared(largest.added) {
                largest = push
            }
        }
        let move = SIMD3(displacement.x, displacement.y, 0)
        let ends = endFeet(at: feet, yaw: yaw, lift: 0).map { start in
            let here = SIMD2(start.x, start.y)
            let floor = ground(here) ?? start.z
            let rise = (ground(here + displacement) ?? start.z) - floor
            return (
                start: SIMD3(here.x, here.y, floor + stepHeight),
                move: move + SIMD3(0, 0, rise)
            )
        }
        let balls = bodyBallFeet(at: feet, yaw: yaw)
        // One search for the whole body: each part then tests only the shapes found here.
        let shapes = query(partBounds(ends.flatMap { [$0.start, $0.start + $0.move] }
                + balls.flatMap { [$0, $0 + move] }))
        let nearby: CapsuleWorldCollider.CandidateQuery = { bounds in
            shapes.filter { $0.bounds.overlaps(bounds) }
        }
        let endCollider = CapsuleWorldCollider(capsule: endCapsule)
        for (index, end) in ends.enumerated() {
            var push = Self.push(endCollider, from: end.start, move: end.move, query: nearby)
            push.part = .end(index)
            keepLarger(push)
        }
        let body = CapsuleWorldCollider(capsule: .ball(radius: bodyRadius))
        for (index, start) in balls.enumerated() {
            var push = Self.push(body, from: start, move: move, query: nearby)
            push.part = .body(index)
            keepLarger(push)
        }
        return largest
    }

    /// A box round every part at each of `feet`, with room for the push out of a wall.
    private func partBounds(_ feet: [SIMD3<Float>]) -> ModelBounds {
        let radius = max(endRadius, bodyRadius)
        var low = feet.first ?? .zero
        var high = low
        for point in feet {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        let room = SIMD3<Float>(repeating: radius * 2 + 1)
        return ModelBounds(min: low - room, max: high + room + SIMD3(0, 0, radius * 2))
    }

    /// The horizontal push a move meets. The move starts where the shape rests after the
    /// collision pushed it out, so a part that sits inside a wall may leave that wall.
    private static func push(
        _ collider: CapsuleWorldCollider, from start: SIMD3<Float>, move: SIMD3<Float>,
        query: CapsuleWorldCollider.CandidateQuery
    ) -> LongBodyPush {
        let resting = collider.move(from: start, displacement: .zero, query: query).position
        let moved = collider.move(from: resting, displacement: move, query: query).position
        var push = LongBodyPush()
        push.resting = resting - start
        push.added = SIMD2(moved.x - resting.x - move.x, moved.y - resting.y - move.y)
        return push
    }
}

/// One part of a long body, and what pushes it: `resting` while it stands still, and
/// `added`, the horizontal push the move adds to that.
nonisolated public struct LongBodyPush: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        case end(Int)
        case body(Int)
    }

    public var part: Part?
    public var resting = SIMD3<Float>.zero
    public var added = SIMD2<Float>.zero

    public init() {}
}
