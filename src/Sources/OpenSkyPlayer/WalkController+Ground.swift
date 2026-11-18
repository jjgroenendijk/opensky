// Ground contact: gravity by phase, the ground search under the feet, walking along the
// ground plane, and the slide off a surface too steep to stand on. Terrain and meshes are
// one kind of ground. See docs/engine/ground-and-water-contact.md.

import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRenderCore
import simd

nonisolated extension WalkController {
    /// Gravity while rising after a jump is 1; these scale it in the other phases.
    static let fallingGravityScale: Float = 1.35
    static let groundedGravityScale: Float = 4
    static let terrainContactTolerance: Float = 0.05

    /// The world one step's vertical move touches.
    struct ContactWorld {
        let collider: CapsuleWorldCollider
        let sampleGround: GroundSampler
        let collisionQuery: CollisionQuery
    }

    /// A walkable surface the feet stand on or found below.
    struct GroundContact {
        let normal: SIMD3<Float>
        let material: FormID?
    }

    func gravityScale(wasGrounded: Bool) -> Float {
        if wasGrounded {
            return Self.groundedGravityScale
        }
        return verticalVelocity > 0 ? 1 : Self.fallingGravityScale
    }

    /// The drop that turns this step's level move along the ground plane, so the feet
    /// follow a downhill slope instead of stepping off into the air. Never upward:
    /// collision and the terrain already lift the feet going uphill.
    func groundSlopeDrop(moved: SIMD3<Float>) -> Float {
        guard isGrounded, activeStepSupport == nil, let normal = groundNormal, normal.z > 0 else {
            return 0
        }
        return min(-(moved.x * normal.x + moved.y * normal.y) / normal.z, 0)
    }

    mutating func resolveVerticalMovement(dt: Float, slopeDrop: Float, world: ContactWorld) {
        if let support = activeStepSupport {
            feetPosition.z = support.height
            verticalVelocity = 0
            isGrounded = true
            groundNormal = SIMD3(0, 0, 1)
            groundMaterial = support.material
            return
        }
        let wasGrounded = isGrounded
        verticalVelocity -= gravityScale(wasGrounded: wasGrounded) * Self.gravity * dt
        let result = world.collider.move(
            from: feetPosition,
            displacement: SIMD3<Float>(0, 0, verticalVelocity * dt + slopeDrop),
            query: world.collisionQuery
        )
        feetPosition = result.position
        hasUnresolvedPenetration = hasUnresolvedPenetration || result.hasUnresolvedPenetration
        var ground = walkableGround(result.contacts)
        let hitCeiling = result.contacts.contains { $0.normal.z < -0.1 }
        if ground != nil, verticalVelocity <= 0 {
            verticalVelocity = 0
        } else if verticalVelocity > 0, hitCeiling {
            verticalVelocity = 0
        }
        if let terrain = touchTerrain(world) {
            ground = terrain
        }
        if ground == nil, wasGrounded, verticalVelocity <= 0 {
            ground = probeGround(world)
        }
        land(on: ground)
    }

    mutating func land(on ground: GroundContact?) {
        isGrounded = ground != nil
        groundNormal = ground?.normal
        groundMaterial = ground?.material
    }

    /// The flattest walkable contact, which is the one the weight is on.
    func walkableGround(_ contacts: [CapsuleCollisionContact]) -> GroundContact? {
        guard
            let flattest = contacts.filter({ isWalkable($0.normal) })
                .max(by: { $0.normal.z < $1.normal.z })
        else { return nil }
        return GroundContact(normal: flattest.normal, material: walkableMaterial(contacts))
    }

    /// Keeps the feet out of the terrain. Walkable terrain under the feet holds them up;
    /// a steeper face pushes them out along its normal, so gravity slides them down it.
    mutating func touchTerrain(_ world: ContactWorld) -> GroundContact? {
        guard let terrain = world.sampleGround(SIMD2(feetPosition.x, feetPosition.y)) else {
            return nil
        }
        let depth = terrain.height - feetPosition.z
        // A mesh resting the feet a hair above the terrain still leaves them on the terrain.
        guard depth >= -Self.terrainContactTolerance else { return nil }
        let walkable = isWalkable(terrain.normal)
        // Feet a whole body deep under a steep face did not walk there; stand them on it.
        guard walkable || depth > capsule.height else {
            slide(off: terrain, depth: max(depth, 0), world: world)
            return nil
        }
        feetPosition.z = terrain.height
        guard walkable, verticalVelocity <= 0 else { return nil }
        verticalVelocity = 0
        return GroundContact(normal: terrain.normal, material: terrain.material)
    }

    private mutating func slide(
        off terrain: TerrainGroundSample,
        depth: Float,
        world: ContactWorld
    ) {
        let normal = simd_normalize(terrain.normal)
        let result = world.collider.move(
            from: feetPosition,
            displacement: normal * (depth * normal.z),
            query: world.collisionQuery
        )
        feetPosition = result.position
        hasUnresolvedPenetration = hasUnresolvedPenetration || result.hasUnresolvedPenetration
    }

    /// The ground search: the highest walkable surface, terrain or mesh, within
    /// `groundProbeDepth` below the feet. It finds ground; it does not move the feet.
    func probeGround(_ world: ContactWorld) -> GroundContact? {
        var found: GroundContact?
        var foundHeight = -Float.greatestFiniteMagnitude
        if
            let terrain = world.sampleGround(SIMD2(feetPosition.x, feetPosition.y)),
            feetPosition.z - terrain.height <= Self.groundProbeDepth,
            isWalkable(terrain.normal)
        {
            found = GroundContact(normal: terrain.normal, material: terrain.material)
            foundHeight = terrain.height
        }
        let sweep = world.collider.move(
            from: feetPosition,
            displacement: SIMD3<Float>(0, 0, -Self.groundProbeDepth),
            query: world.collisionQuery
        )
        if let mesh = walkableGround(sweep.contacts), sweep.position.z > foundHeight {
            found = mesh
        }
        return found
    }

    /// A steep terrain face the feet would end up under acts as a wall: the part of the
    /// move into it is removed. Gravity, not the walk, then decides how the feet slide.
    func wallOffSteepTerrain(
        _ candidate: inout SIMD2<Float>,
        from current: SIMD3<Float>,
        sampleGround: GroundSampler
    ) {
        let currentXY = SIMD2(current.x, current.y)
        guard
            candidate != currentXY,
            let terrain = sampleGround(candidate),
            terrain.height > current.z,
            !isWalkable(terrain.normal)
        else { return }
        let outward = SIMD2(terrain.normal.x, terrain.normal.y)
        guard simd_length_squared(outward) > .ulpOfOne else { return }
        let away = simd_normalize(outward)
        let move = candidate - currentXY
        let into = simd_dot(move, away)
        if into < 0 {
            candidate = currentXY + move - into * away
        }
    }
}
