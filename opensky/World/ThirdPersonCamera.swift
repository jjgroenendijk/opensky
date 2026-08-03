// The third-person orbit camera (issue #189): where the eye sits when the
// player is watched from behind rather than looked out of.
//
// Every distance below is derived from something OpenSky can measure, and the
// derivation is spelled out rather than a remembered number, because the
// numbers vanilla's own camera uses are not in the data. The probe is on
// record: `Skyrim.esm` declares no `fOverShoulder*`, `fVanityMode*`, or
// `fMouseWheelZoom*` game setting, and the install's shipped
// `Skyrim_Default.ini` carries no `[Camera]` section at all — those values live
// in the retail executable and in a user's own `My Games` profile, neither of
// which OpenSky reads. So the framing is computed from two things that are
// measurable here: the player capsule (`PlayerCapsule.standard`, itself derived
// in docs/engine/walk-mode.md) and the vertical field of view the renderer
// projects with. See docs/engine/walk-mode.md, "Third-person camera".
//
// The camera never integrates a pose of its own. It is a pure function of the
// capsule's feet position and the look angles the shared `FreeFlyCamera`
// already owns, so switching between `.walk` and `.thirdPerson` changes where
// the eye is and nothing about where the player is looking.

import simd

nonisolated struct ThirdPersonCamera: Equatable {
    /// The vertical field of view the scene pass projects with
    /// (`RendererDraw.swift`, `RendererOffscreen.swift`). Framing distance is
    /// meaningless without it, so it is stated here and asserted against the
    /// renderer by `ThirdPersonCameraTests`.
    static let fovYRadians = MatrixMath.radians(fromDegrees: 65)

    /// How much of the frame's height the standing body should occupy. Chosen
    /// rather than measured: it is the one number here with no source in the
    /// data, so it is the one place a taste decision is made and it is made
    /// once. Three fifths leaves head- and foot-room without shrinking the
    /// character into the scene.
    static let framingFillFraction: Float = 0.6

    /// The point the camera orbits: the capsule's own eye height above the
    /// feet, which is exactly where `.walk` puts the first-person eye. Sharing
    /// the pivot with first person is what makes the two modes agree about what
    /// is at the centre of the screen.
    static let pivotHeight = PlayerCapsule.standard.eyeHeight

    /// Distance from the pivot at which a capsule-tall subject fills
    /// `framingFillFraction` of the view height:
    /// `(height / 2 / fill) / tan(fov / 2)`. With the standard capsule (128
    /// units) and a 65-degree vertical fov this resolves to about 167 units.
    static let orbitDistance =
        (PlayerCapsule.standard.height / 2 / framingFillFraction)
            / tanf(fovYRadians / 2)

    /// How far right of the spine axis the eye sits. One capsule radius: the
    /// camera rides the shoulder line of the measured capsule rather than its
    /// centre, so the body sits left of frame and the crosshair looks past it.
    static let shoulderOffset = PlayerCapsule.standard.radius

    /// The radius the zoom sweep collides with. A third of the capsule radius
    /// keeps a thin probe that can follow the camera into a doorway, while
    /// still being wide enough that a wall corner pushes it out before the near
    /// plane (10 units, docs/decisions/coordinates.md) clips through.
    static let collisionRadius = PlayerCapsule.standard.radius / 3

    /// How close the eye may be pulled before third person is no longer worth
    /// the name. Set to the shoulder offset so a fully collapsed camera still
    /// sits outside the capsule's own silhouette rather than inside the head.
    static let minimumDistance = shoulderOffset

    /// The distance the last resolve settled on, after collision. Kept so the
    /// panel can report a camera that is being squeezed by geometry, and so a
    /// test can assert the pull-in happened.
    private(set) var resolvedDistance = orbitDistance
    /// True when the last resolve was shortened by world geometry.
    private(set) var isCollisionLimited = false

    /// The point the camera orbits for a capsule standing at `feetPosition`.
    static func pivot(feetPosition: SIMD3<Float>) -> SIMD3<Float> {
        feetPosition + SIMD3<Float>(0, 0, pivotHeight)
    }

    /// Where the eye would sit with nothing in the way: back along the view
    /// direction by `orbitDistance`, then right by `shoulderOffset`.
    ///
    /// The offset is built from the same `FreeFlyCamera` basis the view matrix
    /// uses, so the resolved eye and the resolved forward vector cannot drift
    /// apart.
    static func idealOffset(yaw: Float, pitch: Float) -> SIMD3<Float> {
        let camera = FreeFlyCamera(position: .zero, yaw: yaw, pitch: pitch)
        return camera.right * shoulderOffset - camera.forward * orbitDistance
    }

    /// Resolves this frame's eye position, pulling in along the pivot-to-eye
    /// line when static geometry is in the way.
    ///
    /// The pull-in goes through the same `CapsuleWorldCollider` seam the
    /// character controller collides with (`WalkController.CollisionQuery`), so
    /// the camera sees exactly the shapes the player does and no second
    /// collision world exists to disagree with the first.
    mutating func resolve(
        feetPosition: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        collisionQuery: WalkController.CollisionQuery
    ) -> SIMD3<Float> {
        let pivot = Self.pivot(feetPosition: feetPosition)
        let offset = Self.idealOffset(yaw: yaw, pitch: pitch)
        let wanted = simd_length(offset)
        guard wanted > .ulpOfOne else {
            resolvedDistance = 0
            isCollisionLimited = false
            return pivot
        }
        let probe = PlayerCapsule(
            radius: Self.collisionRadius,
            height: Self.collisionRadius * 2,
            eyeHeight: Self.collisionRadius
        )
        // `CapsuleWorldCollider` positions a capsule by its bottom, so the
        // probe's centre is its eye height above the position it is given.
        let bottom = SIMD3<Float>(0, 0, -Self.collisionRadius)
        let result = CapsuleWorldCollider(capsule: probe).move(
            from: pivot + bottom,
            displacement: offset,
            query: collisionQuery
        )
        let reached = result.position - bottom
        let travelled = simd_length(reached - pivot)
        // Collide-and-slide can push the probe sideways as well as short; the
        // camera only ever moves along its own offset line, so the sweep's
        // answer is read as a distance and re-applied to the original
        // direction. A sideways slide that ends up further out than asked for
        // is clamped back to the ideal distance.
        let limited = min(travelled, wanted)
        resolvedDistance = max(limited, min(Self.minimumDistance, wanted))
        isCollisionLimited = limited < wanted - 0.5
        return pivot + offset / wanted * resolvedDistance
    }

    /// Forgets the collision readout, so a teleport does not report the zoom
    /// state of the place the player just left.
    mutating func reset() {
        resolvedDistance = Self.orbitDistance
        isCollisionLimited = false
    }
}
