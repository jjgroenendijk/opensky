// The renderer half of the dialogue camera: engage the override, resolve it per
// input frame, and restore the player's view afterwards. The override writes
// `freeFlyCamera`, the one pose every pass reads, and remembers the old pose.
// It is undone before simulation each frame and re-applied after, so
// `WalkController` never turns the player to the dialogue pose.
// `movementMode` never changes.

import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import simd

extension GameSession.DialogueCameraSteps {
    public var restorePose: FreeFlyCamera? {
        session.rigs.dialogueCameraState.restorePose
    }

    /// True while a conversation owns the view.
    public var isDialogueCameraEngaged: Bool {
        session.rigs.dialogueCameraState.focus != nil
    }

    /// True while the override frames the player's own head.
    var isDialogueCameraFramingPlayer: Bool {
        session.rigs.dialogueCameraState.focus?.framesPlayer ?? false
    }

    /// The pose the last resolve settled on, or nil when none has run.
    public var dialogueCameraPose: DialogueCameraPose? {
        session.rigs.dialogueCameraState.camera.pose
    }

    /// The field of view that mode projects with, which is what releasing the
    /// override re-projects to. The one statement of the per-mode rule;
    /// `activeFOVYRadians` reads it rather than repeating it.
    var dialogueCameraRestoreFOVYRadians: Float {
        session.movementMode == .walk
            ? session.rigs.firstPersonCamera.fovYRadians
            : FirstPersonCamera.defaultFOVYRadians
    }

    /// Engages, re-aims, or releases the override: one decision about who the view
    /// frames. Engaging and releasing both re-project, because the dialogue field of
    /// view differs from first person.
    public func setDialogueCameraFocus(_ focus: DialogueCameraFocus?) {
        let wasEngaged = isDialogueCameraEngaged
        restorePlayerCameraPose()
        session.rigs.dialogueCameraState.focus = focus
        if focus == nil {
            session.rigs.dialogueCameraState.camera.reset()
        }
        applyDialogueCamera()
        guard wasEngaged != isDialogueCameraEngaged else { return }
    }

    /// Puts the player's own pose back. Safe to call when nothing is applied,
    /// which is what lets the input frame start with it unconditionally.
    public func restorePlayerCameraPose() {
        guard let restorePose = session.rigs.dialogueCameraState.restorePose else { return }
        session.freeFlyCamera = restorePose
        session.rigs.dialogueCameraState.restorePose = nil
    }

    /// Resolves this frame's framing and writes it into the view pose.
    ///
    /// Called at the end of every input frame, and directly by
    /// `setDialogueCameraFocus` so a session that renders without running the
    /// input loop — an offscreen A/B frame, a test — is framed the same way a
    /// live one is.
    public func applyDialogueCamera() {
        restorePlayerCameraPose()
        let playerPose = session.freeFlyCamera
        let shake = session.rigs.cinematicCameraState.shakeOffset
        defer {
            if session.rigs.dialogueCameraState.restorePose != nil || shake != .zero {
                session.freeFlyCamera.position += shake
                session.rigs.dialogueCameraState.restorePose = playerPose
            }
        }
        if session.cinematicSteps.applyCinematicPose() {
            session.rigs.dialogueCameraState.restorePose = playerPose
            return
        }
        guard let focus = session.rigs.dialogueCameraState.focus else { return }
        session.rigs.dialogueCameraState.restorePose = playerPose
        let pose = session.rigs.dialogueCameraState.camera.resolve(
            subject: DialogueCameraSubject(
                headPosition: focus.headPosition,
                playerEyePosition: focus.viewpoint ?? playerEyePosition,
                capsule: session.walkController.capsule
            ),
            collisionQuery: session.motion.collisionQuery ?? { _ in [] }
        )
        session.freeFlyCamera.position = pose.eye
        session.freeFlyCamera.yaw = pose.yaw
        session.freeFlyCamera.pitch = pose.pitch
    }

    /// Where the player's own eye is. In third person the camera is the orbit eye,
    /// so the capsule eye is used; in fly mode the view itself is the best answer.
    public var playerEyePosition: SIMD3<Float> {
        guard session.movementMode.isPlayerControlled else {
            return session.rigs.dialogueCameraState.restorePose?.position ?? session.freeFlyCamera
                .position
        }
        return session.walkController.feetPosition
            + SIMD3<Float>(0, 0, session.walkController.capsule.eyeHeight)
    }

    /// The pivot cross, the sightline, and the speaker's facing, for the world
    /// overlay registry. Drawn from the last resolved pose, so it matches the frame.
    public func appendDialogueCameraOverlay(
        context: WorldOverlayFrameContext,
        to list: inout WorldOverlayDrawList
    ) {
        guard context.dialogueCameraOverlayEnabled, let pose = dialogueCameraPose else {
            return
        }
        let arm = ThirdPersonCamera.collisionRadius * 2
        for axis in [SIMD3<Float>(arm, 0, 0), SIMD3(0, arm, 0), SIMD3(0, 0, arm)] {
            list.addLineSegment(
                pose.target - axis,
                pose.target + axis,
                color: Self.dialogueCameraPivotColor
            )
        }
        list.addLineSegment(
            playerEyePosition,
            pose.target,
            color: Self.dialogueCameraSightlineColor
        )
        list.addLineSegment(pose.eye, pose.target, color: Self.dialogueCameraEyeColor)
    }

    /// Yellow pivot, cyan player sightline, magenta camera axis: three hues far
    /// enough apart to tell apart over any cell art.
    private static let dialogueCameraPivotColor = SIMD4<Float>(1, 0.85, 0.2, 1)
    private static let dialogueCameraSightlineColor = SIMD4<Float>(0.2, 0.9, 1, 1)
    private static let dialogueCameraEyeColor = SIMD4<Float>(1, 0.3, 0.9, 1)
}
