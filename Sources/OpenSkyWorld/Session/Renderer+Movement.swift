// Renderer camera movement split from Renderer.swift for file-length limits.

import OpenSkyPhysics
import OpenSkyRendering

extension Renderer {
    /// Seeds the walk controller from the camera pose during `init`, before
    /// `super.init()` runs, which is why it is a static factory rather than a
    /// method. Lives here rather than in `Renderer.swift` for the file cap.
    public static func makeMovement(
        _ camera: FreeFlyCamera,
        _ configuration: PlayerMovementConfiguration
    ) -> (WalkController, LocomotionBridge) {
        (
            WalkController(cameraPosition: camera.position, configuration: configuration),
            LocomotionBridge(configuration: configuration)
        )
    }

    public func reseedMovement(camera newCamera: SceneCamera) {
        // A held dialogue pose describes a place the player is no longer in,
        // and restoring it after the reseed would undo the teleport.
        restorePlayerCameraPose()
        dialogueCameraState.camera.reset()
        freeFlyCamera = FreeFlyCamera(framing: newCamera)
        if movementMode.isPlayerControlled, let feet = newCamera.walkFeetPosition {
            freeFlyCamera.position = feet
                + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
        }
        walkController.reset(cameraPosition: freeFlyCamera.position)
        // A reseed is a teleport: the bridge's edge state describes a place the
        // player is no longer in, so it must not raise a landing or a swim exit
        // on the next step.
        locomotion.reset()
        thirdPersonCamera.reset()
    }

    /// Puts the player's feet at `feet` and keeps the view, as a vehicle seat does.
    public func placePlayerFeet(at feet: SIMD3<Float>) {
        guard movementMode.isPlayerControlled else { return }
        freeFlyCamera.position = feet + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
        walkController.reset(cameraPosition: freeFlyCamera.position)
    }

    /// Advances active movement mode by one input frame. First frame makes no
    /// move. dt clamps to 100 ms; WalkController further uses fixed substeps.
    public func advanceCamera() {
        guard let input else { return }
        // The dialogue camera stands in for the player's view between frames
        // (RendererDialogueCamera.swift). Everything below simulates the
        // player, and simulating against a pose that is looking at somebody
        // else would turn the player to face them, so the player's own pose
        // goes back first and the override is re-applied at the end.
        restorePlayerCameraPose()
        // Menu mode pauses the sim: dt goes to zero so the camera holds its pose
        // while the clock keeps its mark fresh (resume carries no time jump).
        let dt = cameraClock.advance(to: wallClock.now, paused: worldSimPaused)
        lastCameraDelta = min(max(dt, 0), WalkController.maximumFrameTime)
        var frameInput = input.makeInput(dt: dt)
        steerPlayerWalk(&frameInput)
        if frameInput.cycleCameraMode {
            setMovementMode(movementMode.next)
        }
        switch movementMode {
        case .fly:
            freeFlyCamera.update(frameInput)
        case .walk, .thirdPerson:
            advancePlayer(frameInput)
        }
        updatePlayerBodyPose()
        updatePlayerFirstPersonPose()
        applyDialogueCamera()
    }

    /// Switches camera mode, re-seating the capsule under the current eye when
    /// the new mode simulates a player. Shared by the camera key and the
    /// `World > Camera` selector so the two cannot drift apart.
    public func setMovementMode(_ mode: CameraMovementMode) {
        guard mode != movementMode else { return }
        // Re-seating the capsule reads the view pose, which a live conversation
        // is standing in for; the mode change happens to the player's own pose
        // and the override goes back on top of the result.
        restorePlayerCameraPose()
        defer { applyDialogueCamera() }
        let wasPlayerControlled = movementMode.isPlayerControlled
        movementMode = mode
        thirdPersonCamera.reset()
        // The field of view is per mode, so the projection follows the mode now.
        rebuildProjection()
        guard mode.isPlayerControlled else { return }
        // Coming from fly, the eye is wherever the developer left it and the
        // capsule has to be placed under it. Switching between the two player
        // modes must not move the capsule at all: the body is already standing
        // somewhere, and re-seating it would teleport the player by the orbit
        // distance every time the camera key is pressed.
        guard !wasPlayerControlled else { return }
        walkController.reset(cameraPosition: freeFlyCamera.position)
        locomotion.reset()
    }

    private var walkCollisionQuery: CapsuleWorldCollider.CandidateQuery {
        guard playerWalkIgnoresStatics, !playerWalkPath.isEmpty else {
            return collisionQuery ?? { _ in [] }
        }
        return { _ in [] }
    }

    /// Turns the view to the package walk's next waypoint and holds forward, until
    /// the last one is reached.
    private func steerPlayerWalk(_ frameInput: inout CameraInput) {
        guard !playerWalkPath.isEmpty, movementMode.isPlayerControlled else { return }
        let feet = walkController.feetPosition
        let remaining = PlayerPackageWalk.remainingPath(playerWalkPath, feet: feet)
        playerWalkPath = remaining
        guard
            let next = remaining.first,
            let yaw = PlayerPackageWalk.steeringYaw(feet: feet, target: next)
        else {
            onPlayerWalkArrived?()
            return
        }
        freeFlyCamera.yaw = yaw
        frameInput.moveForward = 1
        frameInput.moveRight = 0
        frameInput.lookRight = 0
    }

    /// One input frame of simulated player movement, shared by `.walk` and
    /// `.thirdPerson`: the same capsule, the same locomotion bridge, and the
    /// same behavior graph. Only where the eye ends up differs.
    private func advancePlayer(_ frameInput: CameraInput) {
        locomotion.acceptFrame(frameInput)
        walkController.update(
            camera: &freeFlyCamera,
            input: frameInput,
            sampleGround: terrainSampler ?? { _ in nil },
            collisionQuery: walkCollisionQuery,
            plan: { [locomotion] state in locomotion.plan(state) }
        )
        // The view follows the drawn capsule, blended between steps.
        freeFlyCamera.position = walkController.drawnCameraPosition
        guard movementMode == .thirdPerson else { return }
        // Third person pulls the eye back out to the orbit position, so the
        // look angles `WalkController.update` integrated are the ones used here.
        freeFlyCamera.position = thirdPersonCamera.resolve(
            feetPosition: walkController.drawnFeetPosition,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch,
            collisionQuery: collisionQuery ?? { _ in [] }
        )
    }
}
