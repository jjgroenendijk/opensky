// The renderer half of kill cams and camera shake. A cinematic pose outranks
// the dialogue camera; a shake adds on top of either. Both use the dialogue
// camera's saved player pose, so simulation never sees them.
// See docs/engine/kill-cam.md.

import OpenSkyCamera
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

extension GameSession.CinematicSteps {
    var isCinematicCameraEngaged: Bool {
        session.rigs.cinematicCameraState.pose != nil
    }

    /// Sets this frame's shot pose and shake. Called every frame while either runs.
    public func setCinematicCamera(
        _ pose: CinematicCameraPose?,
        shakeOffset: SIMD3<Float> = .zero
    ) {
        session.dialogueCameraSteps.restorePlayerCameraPose()
        session.rigs.cinematicCameraState.pose = pose
        session.rigs.cinematicCameraState.shakeOffset = shakeOffset
        session.dialogueCameraSteps.applyDialogueCamera()
    }

    /// Writes the shot pose into the view. The eye is pulled toward the look
    /// target when a wall stands between them. False when no shot plays.
    func applyCinematicPose() -> Bool {
        guard let pose = session.rigs.cinematicCameraState.pose else { return false }
        let resolved = DialogueCamera.collisionProbe.resolve(
            pivot: pose.lookAt,
            offset: pose.eye - pose.lookAt,
            collisionQuery: pose.avoidsGeometry ? session.motion
                .collisionQuery ?? { _ in [] } : { _ in [] }
        )
        session.rigs.cinematicCameraState.isCollisionLimited = resolved.isCollisionLimited
        let look = pose.lookAt - resolved.position
        let horizontal = simd_length(SIMD2<Float>(look.x, look.y))
        session.freeFlyCamera.position = resolved.position
        session.freeFlyCamera.yaw = horizontal > .ulpOfOne ? atan2f(look.y, look.x) : session
            .freeFlyCamera.yaw
        session.freeFlyCamera.pitch = FreeFlyCamera.clampPitch(atan2f(look.z, horizontal))
        return true
    }
}
