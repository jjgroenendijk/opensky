// Renderer camera movement split from Renderer.swift for file-length limits.

import QuartzCore

extension Renderer {
    /// Seeds the walk controller from the camera pose during `init`, before
    /// `super.init()` runs, which is why it is a static factory rather than a
    /// method. Lives here rather than in `Renderer.swift` for the file cap.
    static func makeMovement(
        _ camera: FreeFlyCamera,
        _ configuration: PlayerMovementConfiguration
    ) -> (WalkController, LocomotionBridge) {
        (
            WalkController(cameraPosition: camera.position, configuration: configuration),
            LocomotionBridge(configuration: configuration)
        )
    }

    func reseedMovement(camera newCamera: SceneCamera) {
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

    /// Advances active movement mode by one input frame. First frame makes no
    /// move. dt clamps to 100 ms; WalkController further uses fixed substeps.
    func advanceCamera() {
        guard let input else { return }
        // Menu mode pauses the sim: dt goes to zero so the camera holds its pose
        // while the clock keeps its mark fresh (resume carries no time jump).
        let dt = cameraClock.advance(to: CACurrentMediaTime(), paused: worldSimPaused)
        let frameInput = input.makeInput(dt: dt)
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
    }

    /// Switches camera mode, re-seating the capsule under the current eye when
    /// the new mode simulates a player. Shared by the camera key and the
    /// `World > Camera` selector so the two cannot drift apart.
    func setMovementMode(_ mode: CameraMovementMode) {
        guard mode != movementMode else { return }
        let wasPlayerControlled = movementMode.isPlayerControlled
        movementMode = mode
        thirdPersonCamera.reset()
        // The field of view is per mode (issue #190), so the projection has to
        // follow the mode rather than wait for the next resize.
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

    /// One input frame of simulated player movement, shared by `.walk` and
    /// `.thirdPerson`: the same capsule, the same locomotion bridge, and the
    /// same behavior graph. Only where the eye ends up differs.
    private func advancePlayer(_ frameInput: CameraInput) {
        locomotion.acceptFrame(frameInput)
        walkController.update(
            camera: &freeFlyCamera,
            input: frameInput,
            sampleGround: terrainSampler ?? { _ in nil },
            collisionQuery: collisionQuery ?? { _ in [] },
            plan: { [locomotion] state in locomotion.plan(state) }
        )
        guard movementMode == .thirdPerson else { return }
        // `WalkController.update` has just put the eye at the capsule's own eye
        // height; third person pulls it back out to the orbit position from
        // there, so the look angles it integrated are the ones used here.
        freeFlyCamera.position = thirdPersonCamera.resolve(
            feetPosition: walkController.feetPosition,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch,
            collisionQuery: collisionQuery ?? { _ in [] }
        )
    }
}
