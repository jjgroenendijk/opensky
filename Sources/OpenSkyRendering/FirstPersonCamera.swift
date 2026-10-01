// The first-person eye, its field of view, and how the arms stay out of walls. No
// readable data holds a FOV (no GMST, no `Skyrim_Default.ini` key), so it is our
// setting. The eye is the rig's `Camera1st [Cam1]` bone, read every frame (about
// z = 121 at rest, not the capsule's 112), so animations that move it move the view.
// See docs/engine/first-person.md.

import OpenSkyFormatsCore
import simd

nonisolated public struct FirstPersonCamera: Equatable, Sendable {
    /// The default vertical field of view, in radians: the same 65 degrees the
    /// scene pass projects the world with (`RendererDraw`, `RendererOffscreen`).
    /// Chosen as the default because no readable game data names another, and
    /// asserted against the renderer by `FirstPersonCameraTests`.
    public static let defaultFOVYRadians = MatrixMath.radians(fromDegrees: defaultFOVYDegrees)

    /// The same angle in the unit the panel control presents, so the slider,
    /// the override check, and the engine cannot disagree about "default".
    public static let defaultFOVYDegrees: Float = 65

    /// How far the field of view may be pushed from the panel. Wide enough to
    /// cover the range a Skyrim player's own INI profile realistically holds
    /// and narrow enough that the projection stays well conditioned.
    public static let fovYRange: ClosedRange<Float> = (
        MatrixMath.radians(fromDegrees: 30) ... MatrixMath.radians(fromDegrees: 120)
    )

    /// The rig bone the eye rides. Present only in the first-person skeleton.
    public static let cameraBoneName = "Camera1st [Cam1]"

    /// Where the camera bone sits in rig space when the graph has produced no
    /// pose yet — the reference-pose value, so the first frame after attach is
    /// framed like every frame after it rather than at the rig's feet.
    public static let fallbackCameraBoneHeight: Float = 121

    /// The depth-range share the arms are drawn into, last, at `[0, depthSlice]`. Arms
    /// still occlude each other, and beat any world fragment beyond
    /// `nearPlane / (1 - depthSlice)`, inside the capsule. See docs/engine/first-person.md.
    public static let depthSlice: Float = 0.02

    /// The requested vertical field of view, clamped to `fovYRange`.
    public private(set) var fovYRadians = defaultFOVYRadians

    public init() {}

    /// Sets the field of view, clamping rather than refusing: the control is a
    /// slider and the engine must never be handed a degenerate projection.
    public mutating func setFOVY(radians: Float) {
        guard radians.isFinite else { return }
        fovYRadians = min(max(radians, Self.fovYRange.lowerBound), Self.fovYRange.upperBound)
    }

    public mutating func reset() {
        fovYRadians = Self.defaultFOVYRadians
    }

    public var isOverridden: Bool {
        fovYRadians != Self.defaultFOVYRadians
    }

    /// Where the rig's camera bone must land: at the eye, facing the look direction. The
    /// quarter turn matches `PlayerBody.transform`; pitch is applied in the rig frame, so
    /// looking down tips the arms with the view.
    public static func eyeMatrix(
        eyePosition: SIMD3<Float>,
        yaw: Float,
        pitch: Float
    ) -> float4x4 {
        MatrixMath.translation(eyePosition)
            * MatrixMath.rotationZ(radians: yaw - .pi / 2)
            * MatrixMath.rotationX(radians: pitch)
    }

    /// Where to place the rig so its camera bone lands on `eyeMatrix`, using the inverse
    /// of `cameraBone`, so the graph's camera motion is the view's. A non-invertible
    /// bone falls back to the reference height.
    public static func rigTransform(
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
