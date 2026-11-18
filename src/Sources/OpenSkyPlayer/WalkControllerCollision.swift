// Static mesh horizontal response + bounded step-offset helpers.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRenderCore
import simd

nonisolated extension WalkController {
    mutating func moveHorizontal(
        from start: SIMD3<Float>,
        displacement: SIMD3<Float>,
        collider: CapsuleWorldCollider,
        collisionQuery: CollisionQuery
    ) -> HorizontalMove {
        let direct = collider.move(from: start, displacement: displacement, query: collisionQuery)
        let maintained = maintainedStepSupport(
            from: start,
            displacement: displacement,
            collider: collider,
            collisionQuery: collisionQuery
        )
        let blocked = isHorizontallyBlocked(direct, start: start, desired: displacement)
        // A tread that still holds the feet keeps them there, unless the next riser blocks
        // the move: then the step up below is tried.
        if let maintained, !blocked {
            return HorizontalMove(result: direct, support: maintained)
        }
        guard
            isGrounded, blocked,
            let support = stepSupport(
                from: start,
                displacement: displacement,
                collider: collider,
                collisionQuery: collisionQuery
            ) else { return HorizontalMove(result: direct, support: maintained) }
        let raised = collider.move(
            from: start,
            displacement: SIMD3<Float>(0, 0, configuration.stepHeight.value),
            query: collisionQuery
        )
        guard raised.position.z >= start.z + configuration.stepHeight.value - 0.05 else {
            return HorizontalMove(result: direct, support: maintained)
        }
        let across = collider.move(
            from: raised.position,
            displacement: displacement,
            query: collisionQuery
        )
        guard horizontalProgress(across.position - start, along: displacement) > 0 else {
            return HorizontalMove(result: direct, support: maintained)
        }
        var steppedPosition = across.position
        steppedPosition.z = support.height
        return HorizontalMove(
            result: CapsuleMoveResult(
                position: steppedPosition,
                contacts: [CapsuleCollisionContact(
                    normal: SIMD3(0, 0, 1),
                    depth: 0,
                    material: support.material
                )],
                hasUnresolvedPenetration: raised.hasUnresolvedPenetration
                    || across.hasUnresolvedPenetration
            ),
            support: support
        )
    }

    func maintainedStepSupport(
        from start: SIMD3<Float>,
        displacement: SIMD3<Float>,
        collider: CapsuleWorldCollider,
        collisionQuery: CollisionQuery
    ) -> CapsuleStepSupport? {
        guard let activeStepSupport else { return nil }
        let center = SIMD2<Float>(start.x + displacement.x, start.y + displacement.y)
        let centerSupport = collider.stepSupport(
            at: center,
            minimumHeight: activeStepSupport.height - 0.1,
            maximumHeight: activeStepSupport.height + 0.1,
            query: collisionQuery
        )
        if let centerSupport {
            return centerSupport
        }
        // Just after a step up the centre is not over the tread yet; the tread ahead holds it.
        if
            let ahead = stepProbePoint(from: start, displacement: displacement),
            let held = collider.stepSupport(
                at: ahead,
                minimumHeight: activeStepSupport.height - 0.1,
                maximumHeight: activeStepSupport.height + 0.1,
                query: collisionQuery
            )
        {
            return held
        }
        return stepSupport(
            from: start,
            displacement: displacement,
            collider: collider,
            collisionQuery: collisionQuery
        )
    }

    func stepSupport(
        from start: SIMD3<Float>,
        displacement: SIMD3<Float>,
        collider: CapsuleWorldCollider,
        collisionQuery: CollisionQuery
    ) -> CapsuleStepSupport? {
        guard let point = stepProbePoint(from: start, displacement: displacement) else {
            return nil
        }
        return collider.stepSupport(
            at: point,
            minimumHeight: start.z + 0.05,
            maximumHeight: start.z + configuration.stepHeight.value,
            query: collisionQuery
        )
    }

    /// Just past the capsule's front edge after this move.
    func stepProbePoint(from start: SIMD3<Float>, displacement: SIMD3<Float>) -> SIMD2<Float>? {
        let horizontal = SIMD2<Float>(displacement.x, displacement.y)
        let length = simd_length(horizontal)
        guard length > Float.ulpOfOne else { return nil }
        return SIMD2(start.x, start.y) + horizontal / length * (capsule.radius + length)
    }

    func isHorizontallyBlocked(
        _ result: CapsuleMoveResult,
        start: SIMD3<Float>,
        desired: SIMD3<Float>
    ) -> Bool {
        let desiredLength = simd_length(SIMD2<Float>(desired.x, desired.y))
        guard desiredLength > Float.ulpOfOne else { return false }
        return horizontalProgress(result.position - start, along: desired)
            < desiredLength - 0.05
    }

    func horizontalProgress(_ delta: SIMD3<Float>, along desired: SIMD3<Float>) -> Float {
        let horizontal = SIMD2<Float>(desired.x, desired.y)
        let length = simd_length(horizontal)
        guard length > Float.ulpOfOne else { return 0 }
        return simd_dot(SIMD2<Float>(delta.x, delta.y), horizontal / length)
    }

    func hasWalkableContact(_ contacts: [CapsuleCollisionContact]) -> Bool {
        contacts.contains { isWalkable($0.normal) }
    }

    /// The material of the flattest walkable contact, which is the one the
    /// weight is on: several shapes can touch the capsule at once — a floor and
    /// the wall beside it — and only the floor is what is being stood on.
    /// Contacts that name no material are skipped rather than winning, so a
    /// material-less decoration touching the foot does not silence the step.
    func walkableMaterial(_ contacts: [CapsuleCollisionContact]) -> FormID? {
        contacts
            .filter { isWalkable($0.normal) && $0.material != nil }
            .max { $0.normal.z < $1.normal.z }?
            .material
    }

    func isWalkable(_ normal: SIMD3<Float>) -> Bool {
        let minimumUp = cosf(MatrixMath.radians(fromDegrees: Self.maximumSlopeDegrees))
        return normal.z >= minimumUp
    }
}
