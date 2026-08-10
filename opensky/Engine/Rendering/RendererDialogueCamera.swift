// The renderer half of the dialogue camera (issue #427, roadmap item 17.4):
// engaging the override, resolving it once per input frame, and putting the
// player's own view back when the conversation ends.
//
// ## Why the pose is swapped rather than the mode
//
// `freeFlyCamera` is the one pose every pass reads — the scene pass, the shadow
// cascade fit, grass, precipitation and the audio listener all take their view
// from it — so an override that produced a second camera would have to be
// threaded through all of them, and a pass that missed the thread would draw
// the frame from the wrong place. Instead the override writes that one pose and
// remembers what was there.
//
// The swap is undone at the top of the next input frame, before anything
// simulates, and re-applied at the bottom of it. That ordering is the whole
// trick: `WalkController` integrates the player's facing out of this same pose,
// and the body is placed from its yaw, so a frame that simulated against the
// dialogue pose would turn the player to face themselves. Between frames the
// dialogue pose is what stands, which is what the passes want and also what the
// audio listener wants — a conversation is heard from where it is watched.
//
// Nothing here changes `movementMode`. The player is still in whatever mode
// they chose; disengaging restores the pose and re-projects, and the mode was
// never touched to need restoring.

import simd

/// What the app publishes each frame while a conversation is open. Sampled by
/// the session — the renderer knows nothing about speakers, rigs or menus.
nonisolated struct DialogueCameraFocus: Equatable, Sendable {
    /// Who is being talked to. Carried so the panel can name them and so a
    /// focus that silently changed actor is visible rather than invisible.
    let speaker: ReferenceKey
    /// The speaker's head, world space.
    let headPosition: SIMD3<Float>
}

/// Everything the override owns, in one value: extensions cannot add stored
/// properties, and these three are one thing.
struct RendererDialogueCameraState {
    /// The live focus, or nil when no conversation is framing anybody.
    var focus: DialogueCameraFocus?
    /// The framing math and its collision readout.
    var camera = DialogueCamera()
    /// The player's own view pose, held while the override stands in for it.
    /// Non-nil exactly while the swap is applied.
    var restorePose: FreeFlyCamera?
}

extension Renderer {
    /// True while a conversation owns the view.
    var isDialogueCameraEngaged: Bool {
        dialogueCameraState.focus != nil
    }

    /// The pose the last resolve settled on, or nil when none has run.
    var dialogueCameraPose: DialogueCameraPose? {
        dialogueCameraState.camera.pose
    }

    /// The camera mode that is still live underneath the override and that the
    /// view returns to when the conversation ends.
    var dialogueCameraRestoreMode: CameraMovementMode {
        movementMode
    }

    /// The field of view that mode projects with, which is what releasing the
    /// override re-projects to. The one statement of the per-mode rule;
    /// `activeFOVYRadians` reads it rather than repeating it.
    var dialogueCameraRestoreFOVYRadians: Float {
        movementMode == .walk
            ? firstPersonCamera.fovYRadians
            : FirstPersonCamera.defaultFOVYRadians
    }

    /// Engages, re-aims, or releases the override.
    ///
    /// One entry point for all three because they are one decision — who, if
    /// anybody, the view is framing — and because engaging and releasing both
    /// have to re-project: the field of view a conversation is watched at is
    /// the shared world angle, which is not the angle first person projects
    /// with.
    func setDialogueCameraFocus(_ focus: DialogueCameraFocus?) {
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
    func restorePlayerCameraPose() {
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
    func applyDialogueCamera() {
        restorePlayerCameraPose()
        guard let focus = dialogueCameraState.focus else { return }
        dialogueCameraState.restorePose = freeFlyCamera
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

    /// Where the player's own eye is, whatever the view is currently doing.
    ///
    /// In third person `freeFlyCamera.position` is the orbit eye rather than
    /// the player, and framing a conversation from the orbit eye would stand
    /// the dialogue camera off from a point that is already stood off. In fly
    /// mode there is no capsule under the view, so the view is the best answer
    /// available.
    var playerEyePosition: SIMD3<Float> {
        guard movementMode.isPlayerControlled else {
            return dialogueCameraState.restorePose?.position ?? freeFlyCamera.position
        }
        return walkController.feetPosition
            + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
    }

    /// The pivot cross, the sightline and the speaker's facing, for the M16
    /// world-overlay registry (issue #422).
    ///
    /// Drawn from the last resolved pose rather than from a second resolve, so
    /// the gizmo can never disagree with the frame it is drawn over. While the
    /// camera is engaged the eye *is* the viewpoint, so the useful half of the
    /// gizmo is the pivot and the line the player's own eye looks along.
    func appendDialogueCameraOverlay(
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
