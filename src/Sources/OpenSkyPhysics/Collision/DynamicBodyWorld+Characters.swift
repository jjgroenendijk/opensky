// How moving bodies meet a character's capsule, as the game's character controller
// handles a touching body by its layer and mass. See docs/engine/dynamic-bodies.md.

public import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

nonisolated extension DynamicBodyDefinition {
    /// Clutter, weapons, and projectiles under 95 kg neither block nor push a character:
    /// it walks through them and only its own push moves them.
    public var blocksCharacters: Bool {
        let light = (4 ... 6).contains(collisionLayer) && mass < PlayerPushFactor.heaviest
        return !light
    }

    /// A blocking body moves the character it touches by its own velocity, except a
    /// prop (layer 10), which only blocks.
    public var carriesCharacters: Bool {
        blocksCharacters && collisionLayer != PlayerPushFactor.propsLayer
    }
}

nonisolated extension DynamicBodyWorld {
    /// The shapes a character's capsule collides with: every body but light clutter.
    public func characterShapes(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        bodies.filter { $0.definition.blocksCharacters && $0.worldBounds.overlaps(bounds) }
            .flatMap { $0.placedShapes() }
            .filter { $0.bounds.overlaps(bounds) }
    }

    /// The velocity a carrying body gives a capsule that stands on it or that it walks
    /// into: all of a supporting body's velocity, and the part of another one's that
    /// moves toward the capsule. Zero when nothing carries it.
    public func characterCarry(
        capsule: PlayerCapsule, feetPosition: SIMD3<Float>
    ) -> SIMD3<Float> {
        let reach = capsule.radius + DynamicBodyContacts.contactMargin * 2
        let segment = (
            feetPosition + SIMD3<Float>(0, 0, capsule.radius),
            feetPosition + SIMD3<Float>(0, 0, capsule.height - capsule.radius)
        )
        let walkable = cosf(MatrixMath.radians(fromDegrees: PhysicsStep.maximumSlopeDegrees))
        var carry = SIMD3<Float>.zero
        for body in bodies where body.definition.carriesCharacters && !body.isSleeping {
            let axis = DynamicCollisionMath.closestPoint(onSegment: segment, to: body.position)
            let toward = body.penetration(of: axis, radius: reach)
            guard let toward else { continue }
            let contact = axis - toward.normal * (reach - toward.depth)
            let velocity = body.velocity(at: contact)
            if toward.normal.z >= walkable {
                carry = velocity
            } else {
                let push = simd_dot(velocity, toward.normal)
                if push > simd_dot(carry, toward.normal) {
                    carry += toward.normal * (push - simd_dot(carry, toward.normal))
                }
            }
        }
        return carry
    }
}
