// The pull-in every world-space camera performs when geometry stands between
// the point it frames and the point it wants to watch from (issues #189, #427).
//
// Extracted from `ThirdPersonCamera.resolve` when the dialogue camera became
// the second camera that needed it. Both cameras have the same shape — a pivot
// they orbit, an offset they would like to sit at, and a wall that may be in
// the way — and both must collide against the *same* shapes the character
// controller does, so the sweep goes through `CapsuleWorldCollider` and the
// `WalkController.CollisionQuery` seam rather than through a second collision
// world that could disagree with the first.
//
// The sweep is a small capsule rather than a ray because a ray slips through
// the seam between two walls that a camera's near plane would clip through.
// See docs/engine/walk-mode.md, "Third-person camera".

import simd

nonisolated struct CameraCollisionProbe: Equatable {
    /// How much shorter than the ideal offset a resolve has to land before it
    /// is called collision-limited. Half a world unit is below anything a
    /// viewer can see and above what a sweep's own arithmetic moves by, so a
    /// camera standing in the open never reports itself squeezed.
    static let limitSlack: Float = 0.5

    /// Radius of the swept probe capsule.
    let radius: Float
    /// How close to the pivot the eye may be pushed. A collision that would
    /// bring it closer stops here instead, so a camera in a corner ends up
    /// tight rather than inside the thing it is framing.
    let minimumDistance: Float

    nonisolated struct Result: Equatable {
        /// Where the eye ends up, always on the pivot-to-ideal-eye line.
        let position: SIMD3<Float>
        /// How far that is from the pivot.
        let distance: Float
        /// True when geometry, rather than the request, decided the distance.
        let isCollisionLimited: Bool
    }

    /// Sweeps from `pivot` along `offset` and reports where the eye may sit.
    ///
    /// Collide-and-slide can push the probe sideways as well as short; a camera
    /// only ever moves along its own offset line, so the sweep's answer is read
    /// as a distance and re-applied to the original direction. A sideways slide
    /// that ends up further out than asked for is clamped back to the ideal.
    func resolve(
        pivot: SIMD3<Float>,
        offset: SIMD3<Float>,
        collisionQuery: WalkController.CollisionQuery
    ) -> Result {
        let wanted = simd_length(offset)
        guard wanted > .ulpOfOne else {
            return Result(position: pivot, distance: 0, isCollisionLimited: false)
        }
        let capsule = PlayerCapsule(radius: radius, height: radius * 2, eyeHeight: radius)
        // `CapsuleWorldCollider` positions a capsule by its bottom, so the
        // probe's centre is its eye height above the position it is given.
        let bottom = SIMD3<Float>(0, 0, -radius)
        let swept = CapsuleWorldCollider(capsule: capsule).move(
            from: pivot + bottom,
            displacement: offset,
            query: collisionQuery
        )
        let travelled = simd_length((swept.position - bottom) - pivot)
        let limited = min(travelled, wanted)
        let distance = max(limited, min(minimumDistance, wanted))
        return Result(
            position: pivot + offset / wanted * distance,
            distance: distance,
            isCollisionLimited: limited < wanted - Self.limitSlack
        )
    }
}
