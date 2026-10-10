// The renderer half of kill cams and camera shake. A cinematic pose outranks
// the dialogue camera; a shake adds on top of either. Both use the dialogue
// camera's saved player pose, so simulation never sees them.
// See docs/engine/kill-cam.md.

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
}

extension Renderer {
    public var isCinematicCameraEngaged: Bool {
        cinematicCameraState.pose != nil
    }

    /// Sets this frame's shot pose and shake. Called every frame while either runs.
    public func setCinematicCamera(
        _ pose: CinematicCameraPose?,
        shakeOffset: SIMD3<Float> = .zero
    ) {
        restorePlayerCameraPose()
        cinematicCameraState.pose = pose
        cinematicCameraState.shakeOffset = shakeOffset
        applyDialogueCamera()
    }

    /// Writes the shot pose into the view. The eye is pulled toward the look
    /// target when a wall stands between them. False when no shot plays.
    func applyCinematicPose() -> Bool {
        guard let pose = cinematicCameraState.pose else { return false }
        let resolved = DialogueCamera.collisionProbe.resolve(
            pivot: pose.lookAt,
            offset: pose.eye - pose.lookAt,
            collisionQuery: pose.avoidsGeometry ? collisionQuery ?? { _ in [] } : { _ in [] }
        )
        cinematicCameraState.isCollisionLimited = resolved.isCollisionLimited
        let look = pose.lookAt - resolved.position
        let horizontal = simd_length(SIMD2<Float>(look.x, look.y))
        freeFlyCamera.position = resolved.position
        freeFlyCamera.yaw = horizontal > .ulpOfOne ? atan2f(look.y, look.x) : freeFlyCamera.yaw
        freeFlyCamera.pitch = FreeFlyCamera.clampPitch(atan2f(look.z, horizontal))
        return true
    }
}
