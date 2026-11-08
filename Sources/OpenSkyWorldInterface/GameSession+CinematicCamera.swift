import OpenSkyPhysics
import OpenSkyRendering
import simd

public struct RendererCinematicCameraState {
    /// The shot's pose this frame, or nil when no shot plays.
    public var pose: CinematicCameraPose?
    /// The shake's offset this frame, in world units.
    public var shakeOffset = SIMD3<Float>.zero
    /// True when the last resolve pulled the eye in front of geometry.
    public var isCollisionLimited = false

    public init() {}
}
