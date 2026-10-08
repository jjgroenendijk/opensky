// The pull-in a world-space camera does when geometry blocks its view. Shared by the
// third-person and dialogue cameras, and swept through `CapsuleWorldCollider` so it hits
// the same shapes as the character controller. A small capsule, not a ray, because a ray
// slips through wall seams. See docs/engine/player-camera.md, "Third-person framing".

import simd

nonisolated public struct CameraCollisionProbe: Equatable, Sendable {
    /// How much shorter than the ideal offset a resolve has to land before it
    /// is called collision-limited. Half a world unit is below anything a
    /// viewer can see and above what a sweep's own arithmetic moves by, so a
    /// camera standing in the open never reports itself squeezed.
    public static let limitSlack: Float = 0.5

    /// Radius of the swept probe capsule.
    public let radius: Float
    /// How close to the pivot the eye may be pushed. A collision that would
    /// bring it closer stops here instead, so a camera in a corner ends up
    /// tight rather than inside the thing it is framing.
    public let minimumDistance: Float

    nonisolated public struct Result: Equatable, Sendable {
        /// Where the eye ends up, always on the pivot-to-ideal-eye line.
        public let position: SIMD3<Float>
        /// How far that is from the pivot.
        public let distance: Float
        /// True when geometry, rather than the request, decided the distance.
        public let isCollisionLimited: Bool
    }

    /// How far a step may be pushed off its line before it counts as a hit.
    static let deflectionTolerance: Float = 0.01

    /// Sweeps from `pivot` along `offset` and reports where the eye may sit.
    public func resolve(
        pivot: SIMD3<Float>,
        offset: SIMD3<Float>,
        collisionQuery: CapsuleWorldCollider.CandidateQuery
    ) -> Result {
        let wanted = simd_length(offset)
        guard wanted > .ulpOfOne else {
            return Result(position: pivot, distance: 0, isCollisionLimited: false)
        }
        let direction = offset / wanted
        let clear = clearDistance(
            pivot: pivot, direction: direction, wanted: wanted, query: collisionQuery
        )
        let distance = max(clear, min(minimumDistance, wanted))
        return Result(
            position: pivot + direction * distance,
            distance: distance,
            isCollisionLimited: clear < wanted - Self.limitSlack
        )
    }

    /// The probe moves in steps of half its radius and stops before the first step
    /// the collider pushes off the line. A collide-and-slide sweep would slide along
    /// an oblique wall, and its length read back along the line passes the wall.
    private func clearDistance(
        pivot: SIMD3<Float>,
        direction: SIMD3<Float>,
        wanted: Float,
        query: CapsuleWorldCollider.CandidateQuery
    ) -> Float {
        let capsule = PlayerCapsule(radius: radius, height: radius * 2, eyeHeight: radius)
        let collider = CapsuleWorldCollider(capsule: capsule)
        // The collider places a capsule by its bottom; the probe's centre is one radius up.
        let bottom = pivot - SIMD3<Float>(0, 0, radius)
        let stepLength = max(radius * 0.5, 1)
        var travelled: Float = 0
        while travelled < wanted {
            let step = min(stepLength, wanted - travelled)
            let start = bottom + direction * travelled
            let target = start + direction * step
            let moved = collider.move(from: start, displacement: direction * step, query: query)
            if simd_length(moved.position - target) > Self.deflectionTolerance {
                return travelled
            }
            travelled += step
        }
        return wanted
    }

    public init(radius: Float, minimumDistance: Float) {
        self.radius = radius
        self.minimumDistance = minimumDistance
    }
}
