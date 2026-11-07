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
    }

    /// The feet of each end sphere's short capsule. `yaw` is counter-clockwise from +X.
    public func endFeet(at feet: SIMD3<Float>, yaw: Float, lift: Float) -> [SIMD3<Float>] {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let axis = isForwardLong ? forward : SIMD2(forward.y, -forward.x)
        return [1, -1].map { (side: Float) in
            let point = SIMD2(feet.x, feet.y) + axis * endOffset * side
            return SIMD3(point.x, point.y, feet.z + lift)
        }
    }

    public var endCapsule: PlayerCapsule {
        PlayerCapsule(radius: endRadius, height: endRadius * 2, eyeHeight: endRadius)
    }

    /// The horizontal change to `displacement` that keeps both ends out of `query`'s shapes.
    /// The ends ride `lift` above the feet, so the ground under them is the capsule's job.
    public func correction(
        feet: SIMD3<Float>, yaw: Float, displacement: SIMD2<Float>, lift: Float,
        query: CapsuleWorldCollider.CandidateQuery
    ) -> SIMD2<Float> {
        let collider = CapsuleWorldCollider(capsule: endCapsule)
        let move = SIMD3(displacement.x, displacement.y, 0)
        var correction = SIMD2<Float>.zero
        for start in endFeet(at: feet, yaw: yaw, lift: lift) {
            let moved = collider.move(from: start, displacement: move, query: query)
            let push = SIMD2(moved.position.x, moved.position.y)
                - SIMD2(start.x + move.x, start.y + move.y)
            if simd_length_squared(push) > simd_length_squared(correction) {
                correction = push
            }
        }
        return correction
    }
}
