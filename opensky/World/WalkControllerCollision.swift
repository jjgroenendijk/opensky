// Static mesh horizontal response + bounded step-offset helpers.

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
        if let maintained {
            return HorizontalMove(result: direct, supportHeight: maintained)
        }
        guard isGrounded, isHorizontallyBlocked(direct, start: start, desired: displacement) else {
            return HorizontalMove(result: direct, supportHeight: nil)
        }
        guard
            let supportHeight = stepSupport(
                from: start,
                displacement: displacement,
                collider: collider,
                collisionQuery: collisionQuery
            ) else { return HorizontalMove(result: direct, supportHeight: nil) }
        let raised = collider.move(
            from: start,
            displacement: SIMD3<Float>(0, 0, Self.stepHeight),
            query: collisionQuery
        )
        guard raised.position.z >= start.z + Self.stepHeight - 0.05 else {
            return HorizontalMove(result: direct, supportHeight: nil)
        }
        let across = collider.move(
            from: raised.position,
            displacement: displacement,
            query: collisionQuery
        )
        guard horizontalProgress(across.position - start, along: displacement) > 0 else {
            return HorizontalMove(result: direct, supportHeight: nil)
        }
        var steppedPosition = across.position
        steppedPosition.z = supportHeight
        return HorizontalMove(
            result: CapsuleMoveResult(
                position: steppedPosition,
                contacts: [CapsuleCollisionContact(normal: SIMD3(0, 0, 1), depth: 0)],
                hasUnresolvedPenetration: raised.hasUnresolvedPenetration
                    || across.hasUnresolvedPenetration
            ),
            supportHeight: supportHeight
        )
    }

    func maintainedStepSupport(
        from start: SIMD3<Float>,
        displacement: SIMD3<Float>,
        collider: CapsuleWorldCollider,
        collisionQuery: CollisionQuery
    ) -> Float? {
        guard let activeStepSupportHeight else { return nil }
        let center = SIMD2<Float>(start.x + displacement.x, start.y + displacement.y)
        let centerSupport = collider.stepSupportHeight(
            at: center,
            minimumHeight: activeStepSupportHeight - 0.1,
            maximumHeight: activeStepSupportHeight + 0.1,
            query: collisionQuery
        )
        if let centerSupport {
            return centerSupport
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
    ) -> Float? {
        let horizontal = SIMD2<Float>(displacement.x, displacement.y)
        let length = simd_length(horizontal)
        guard length > Float.ulpOfOne else { return nil }
        let direction = horizontal / length
        let point = SIMD2<Float>(start.x, start.y) + direction * (capsule.radius + length)
        return collider.stepSupportHeight(
            at: point,
            minimumHeight: start.z + 0.05,
            maximumHeight: start.z + Self.stepHeight,
            query: collisionQuery
        )
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

    func isWalkable(_ normal: SIMD3<Float>) -> Bool {
        let minimumUp = cosf(MatrixMath.radians(fromDegrees: Self.maximumSlopeDegrees))
        return normal.z >= minimumUp
    }

    func isBlockedSlope(
        at position: SIMD2<Float>,
        direction: SIMD2<Float>,
        sampleGround: GroundSampler
    ) -> Bool {
        guard
            isGrounded,
            simd_length_squared(direction) > .ulpOfOne,
            let candidate = sampleGround(position)
        else { return false }
        return !isWalkable(candidate.normal)
    }
}
