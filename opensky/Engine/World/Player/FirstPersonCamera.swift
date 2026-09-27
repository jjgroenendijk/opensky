// Where the first-person eye sits, how wide it sees, and how the arms in front
// of it are kept out of the walls (issue #190).
//
// **Field of view has no source in the data OpenSky may read, and that is a
// probe result rather than an omission.** `Skyrim.esm` declares no GMST whose
// editor ID is `fDefaultWorldFOV`, `fDefault1stPersonFOV`, or `fDefaultFOV`
// (`openskycli record <name>` answers "no record" for each), and the install's
// shipped `Skyrim_Default.ini` carries no key containing "fov" in any of its
// twelve sections. Those values live in the retail executable and in the
// user's own `My Games\Skyrim Special Edition\*.ini` profile, and neither is
// something this engine reads: the install is read-only external input and the
// profile is outside it. So the first-person field of view is an OpenSky
// setting with the renderer's own world value as its default, exposed as a
// control rather than buried as a constant. The same probe is on record for
// the third-person framing distance (`ThirdPersonCamera`).
//
// **The eye is the rig's own camera bone, not a number.** The first-person
// Havok rig declares a bone the third-person rig does not have at all:
// `Camera1st [Cam1]`, bone 97 of 99, parented to `NPC Root [Root]`. Driving
// the vanilla `_1stperson\behaviors\0_master.hkx` for 120 steps of walking
// puts it at rig-space (0, 0, 121) with an identity rotation and leaves it
// there — spread 0.0 over the whole run. So vanilla *does* couple the
// first-person camera to a skeleton bone, and in the locomotion states this
// milestone covers that bone happens to be still. Reading it every frame
// rather than baking the 121 in is what makes a state that does move it (a
// weapon recoil, M15) move the view without another change here.
//
// Note that 121 is not the capsule's own eye height of 112
// (`PlayerCapsule.standard`, derived in docs/engine/walk-mode.md). The two
// disagree by 9 units because they are measurements of different things: 112
// is where OpenSky's capsule puts an eye, 121 is where the vanilla rig puts
// its camera bone. First person uses the rig's answer, which is the one the
// arms were authored against.

import simd

nonisolated struct FirstPersonCamera: Equatable {
    /// The default vertical field of view, in radians: the same 65 degrees the
    /// scene pass projects the world with (`RendererDraw`, `RendererOffscreen`).
    /// Chosen as the default because no readable game data names another, and
    /// asserted against the renderer by `FirstPersonCameraTests`.
    static let defaultFOVYRadians = MatrixMath.radians(fromDegrees: defaultFOVYDegrees)

    /// The same angle in the unit the panel control presents, so the slider,
    /// the override check, and the engine cannot disagree about "default".
    static let defaultFOVYDegrees: Float = 65

    /// How far the field of view may be pushed from the panel. Wide enough to
    /// cover the range a Skyrim player's own INI profile realistically holds
    /// and narrow enough that the projection stays well conditioned.
    static let fovYRange: ClosedRange<Float> = (
        MatrixMath.radians(fromDegrees: 30) ... MatrixMath.radians(fromDegrees: 120)
    )

    /// The rig bone the eye rides. Present only in the first-person skeleton.
    static let cameraBoneName = "Camera1st [Cam1]"

    /// Where the camera bone sits in rig space when the graph has produced no
    /// pose yet — the reference-pose value, so the first frame after attach is
    /// framed like every frame after it rather than at the rig's feet.
    static let fallbackCameraBoneHeight: Float = 121

    /// The share of the depth range the first-person arms are compressed into.
    ///
    /// Vanilla's own mechanism for keeping first-person geometry out of walls
    /// is in its renderer, which is not observable from the data, so this is a
    /// deliberate deviation and is recorded as one in
    /// docs/engine/behavior-runtime.md. What OpenSky does instead: the arms are
    /// encoded last, into a viewport whose depth range is `[0, depthSlice]`,
    /// with the same projection everything else uses. Their depths stay
    /// monotonic in distance, so the arms occlude *each other* correctly, and
    /// every one of them lands in front of any world fragment further than
    /// `nearPlane / (1 - depthSlice)` from the eye — about 10.2 units with the
    /// 10-unit near plane — which is inside the capsule's own radius and so
    /// unreachable by world geometry.
    static let depthSlice: Float = 0.02

    /// The requested vertical field of view, clamped to `fovYRange`.
    private(set) var fovYRadians = defaultFOVYRadians

    /// Sets the field of view, clamping rather than refusing: the control is a
    /// slider and the engine must never be handed a degenerate projection.
    mutating func setFOVY(radians: Float) {
        guard radians.isFinite else { return }
        fovYRadians = min(max(radians, Self.fovYRange.lowerBound), Self.fovYRange.upperBound)
    }

    mutating func reset() {
        fovYRadians = Self.defaultFOVYRadians
    }

    var isOverridden: Bool {
        fovYRadians != Self.defaultFOVYRadians
    }

    /// The world matrix the first-person rig's camera bone has to land on: at
    /// the eye, facing the look direction.
    ///
    /// The quarter turn is the same actor convention `PlayerBody.transform`
    /// documents — character meshes are authored facing +Y and walk-mode yaw is
    /// measured counterclockwise from +X — and the pitch that follows it is
    /// applied in the rig's own frame, whose X axis is the camera's right
    /// vector after the yaw. So looking down tips the arms down with the view
    /// instead of sliding them.
    static func eyeMatrix(
        eyePosition: SIMD3<Float>,
        yaw: Float,
        pitch: Float
    ) -> float4x4 {
        MatrixMath.translation(eyePosition)
            * MatrixMath.rotationZ(radians: yaw - .pi / 2)
            * MatrixMath.rotationX(radians: pitch)
    }

    /// Where to place the whole first-person rig so its camera bone lands on
    /// `eyeMatrix`.
    ///
    /// `cameraBone` is that bone's matrix in rig space, taken from the pose the
    /// behavior graph just produced. Composing with its inverse states the
    /// coupling exactly once: whatever the graph does to the camera bone is
    /// what happens to the view, because the two are the same matrix by
    /// construction. A non-invertible bone matrix — only reachable from
    /// malformed data — falls back to the reference height so the arms stay in
    /// front of the player instead of collapsing onto the origin.
    static func rigTransform(
        eyeMatrix: float4x4,
        cameraBone: float4x4?
    ) -> float4x4 {
        guard let cameraBone, abs(cameraBone.determinant) > .ulpOfOne else {
            return eyeMatrix
                * MatrixMath.translation(SIMD3<Float>(0, 0, -fallbackCameraBoneHeight))
        }
        return eyeMatrix * cameraBone.inverse
    }
}
