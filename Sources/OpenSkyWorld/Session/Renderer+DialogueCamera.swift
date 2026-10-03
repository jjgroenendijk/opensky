// The renderer half of the dialogue camera: engage the override, resolve it per
// input frame, and restore the player's view afterwards. The override writes
// `freeFlyCamera`, the one pose every pass reads, and remembers the old pose.
// It is undone before simulation each frame and re-applied after, so
// `WalkController` never turns the player to the dialogue pose.
// `movementMode` never changes.

import OpenSkyDiagnostics
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

/// What the app publishes each frame while a conversation is open. Sampled by
/// the session — the renderer knows nothing about speakers, rigs or menus.
nonisolated public struct DialogueCameraFocus: Equatable, Sendable {
    /// The speaker's head, world space.
    public let headPosition: SIMD3<Float>

    public init(headPosition: SIMD3<Float>) {
        self.headPosition = headPosition
    }
}

/// Everything the override owns, in one value: extensions cannot add stored
/// properties, and these three are one thing.
public struct RendererDialogueCameraState {
    /// The live focus, or nil when no conversation is framing anybody.
    public var focus: DialogueCameraFocus?
    /// The framing math and its collision readout.
    public var camera = DialogueCamera()
    /// The player's own view pose, held while the override stands in for it.
    /// Non-nil exactly while the swap is applied.
    public var restorePose: FreeFlyCamera?
}

extension Renderer {
    /// True while a conversation owns the view.
    public var isDialogueCameraEngaged: Bool {
        dialogueCameraState.focus != nil
    }

    /// The pose the last resolve settled on, or nil when none has run.
    public var dialogueCameraPose: DialogueCameraPose? {
        dialogueCameraState.camera.pose
    }

    /// The camera mode that is still live underneath the override and that the
    /// view returns to when the conversation ends.
    public var dialogueCameraRestoreMode: CameraMovementMode {
        movementMode
    }

    /// The field of view that mode projects with, which is what releasing the
    /// override re-projects to. The one statement of the per-mode rule;
    /// `activeFOVYRadians` reads it rather than repeating it.
    public var dialogueCameraRestoreFOVYRadians: Float {
        movementMode == .walk
            ? firstPersonCamera.fovYRadians
            : FirstPersonCamera.defaultFOVYRadians
    }

    /// Engages, re-aims, or releases the override: one decision about who the view
    /// frames. Engaging and releasing both re-project, because the dialogue field of
    /// view differs from first person.
    public func setDialogueCameraFocus(_ focus: DialogueCameraFocus?) {
        let wasEngaged = isDialogueCameraEngaged
        restorePlayerCameraPose()
        dialogueCameraState.focus = focus
        if focus == nil {
            dialogueCameraState.camera.reset()
        }
        applyDialogueCamera()
        guard wasEngaged != isDialogueCameraEngaged else { return }
        rebuildProjection()
    }

    /// Puts the player's own pose back. Safe to call when nothing is applied,
    /// which is what lets the input frame start with it unconditionally.
    public func restorePlayerCameraPose() {
        guard let restorePose = dialogueCameraState.restorePose else { return }
        freeFlyCamera = restorePose
        dialogueCameraState.restorePose = nil
    }

    /// Resolves this frame's framing and writes it into the view pose.
    ///
    /// Called at the end of every input frame, and directly by
    /// `setDialogueCameraFocus` so a session that renders without running the
    /// input loop — an offscreen A/B frame, a test — is framed the same way a
    /// live one is.
    public func applyDialogueCamera() {
        restorePlayerCameraPose()
        let playerPose = freeFlyCamera
        let shake = cinematicCameraState.shakeOffset
        defer {
            if dialogueCameraState.restorePose != nil || shake != .zero {
                freeFlyCamera.position += shake
                dialogueCameraState.restorePose = playerPose
            }
        }
        if applyCinematicPose() {
            dialogueCameraState.restorePose = playerPose
            return
        }
        guard let focus = dialogueCameraState.focus else { return }
        dialogueCameraState.restorePose = playerPose
        let pose = dialogueCameraState.camera.resolve(
            subject: DialogueCameraSubject(
                headPosition: focus.headPosition,
                playerEyePosition: playerEyePosition,
                capsule: walkController.capsule
            ),
            collisionQuery: collisionQuery ?? { _ in [] }
        )
        freeFlyCamera.position = pose.eye
        freeFlyCamera.yaw = pose.yaw
        freeFlyCamera.pitch = pose.pitch
    }

    /// Where the player's own eye is. In third person the camera is the orbit eye,
    /// so the capsule eye is used; in fly mode the view itself is the best answer.
    public var playerEyePosition: SIMD3<Float> {
        guard movementMode.isPlayerControlled else {
            return dialogueCameraState.restorePose?.position ?? freeFlyCamera.position
        }
        return walkController.feetPosition
            + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
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
