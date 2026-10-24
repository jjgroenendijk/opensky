// Renderer camera movement split from Renderer.swift for file-length limits.

import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import simd

extension GameSession {
    /// Seeds the walk controller from the camera pose during `init`, before every
    /// stored property is set, which is why it is a static factory rather than a method.
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
    /// Third person keeps its orbit around the new feet.
    public func placePlayerFeet(at feet: SIMD3<Float>) {
        guard movementMode.isPlayerControlled else { return }
        let eye = feet + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
        walkController.reset(cameraPosition: eye)
        freeFlyCamera.position = movementMode == .thirdPerson
            ? thirdPersonCamera.resolve(
                feetPosition: feet,
                yaw: freeFlyCamera.yaw,
                pitch: freeFlyCamera.pitch,
                collisionQuery: collisionQuery ?? { _ in [] }
            )
            : eye
    }

    /// Puts the body's root on a seat and the eye on the seat idle's `head` bone, in
    /// the root's space, so the view sits in the seat. The seat holds without a head
    /// bone too: a walking step there would drop the player out of the seat state.
    public func seatPlayer(at root: float4x4, head: SIMD3<Float>?) {
        playerSeat = root
        seatedHead = head ?? seatedHead
        guard let head = seatedHead else {
            let origin = root.columns.3
            placePlayerFeet(at: SIMD3(origin.x, origin.y, origin.z))
            return
        }
        let eye = root * SIMD4(head, 1)
        placePlayerFeet(at: SIMD3(eye.x, eye.y, eye.z - walkController.capsule.eyeHeight))
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
        let dt = cameraClock.advance(to: renderer.wallClock.now, paused: worldSimPaused)
            * playerTimeScale * bowZoomTimeScale
        lastCameraDelta = min(max(dt, 0), WalkController.maximumFrameTime)
        var frameInput = input.makeInput(dt: dt)
        if isPlayerParalysed, movementMode.isPlayerControlled {
            frameInput = frameInput.holdingStill
        }
        steerPlayerWalk(&frameInput)
        if frameInput.cycleCameraMode {
            setMovementMode(movementMode.next)
        }
        switch movementMode {
        case .fly:
            freeFlyCamera.update(frameInput)
        case .walk where playerMount?.isMountActive == true,
             .thirdPerson where playerMount?.isMountActive == true:
            advanceMounted(frameInput)
        case .walk where playerSeat != nil, .thirdPerson where playerSeat != nil:
            // The vehicle or the furniture places a seated player; only the view turns.
            freeFlyCamera.applyLook(lookRight: frameInput.lookRight, lookUp: frameInput.lookUp)
            locomotion.advanceSeated(
                deltaTime: lastCameraDelta, feet: walkController.feetPosition
            )
            if frameInput.moveForward != 0 || frameInput.moveRight != 0 || frameInput.jump {
                playerFurniture?.playerAskedToStand()
            }
        case .walk, .thirdPerson:
            advancePlayer(frameInput)
        }
        updatePlayerBodyPose()
        updatePlayerFirstPersonPose()
        applyDialogueCamera()
    }

    /// Switches camera mode, re-seating the capsule under the current eye when
    /// the new mode simulates a player. Shared by the camera key and the
    /// camera selector so the two cannot drift apart.
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

    /// One input frame on a mount: the view turns, the mount moves, and the rider's
    /// graph follows. The vehicle pass places the rider on the saddle.
    private func advanceMounted(_ frameInput: CameraInput) {
        freeFlyCamera.applyLook(lookRight: frameInput.lookRight, lookUp: frameInput.lookUp)
        if let limit = playerMount?.maximumLookDown {
            freeFlyCamera.pitch = max(freeFlyCamera.pitch, -limit)
        }
        locomotion.actorState.setCamera(
            position: freeFlyCamera.position,
            forward: freeFlyCamera.forward,
            pitch: freeFlyCamera.pitch
        )
        let rider = MountRules.riderInput(
            frameInput, rightHandType: locomotion.actorState.rightHandType
        )
        locomotion.acceptFrame(rider)
        let world = MountStepWorld(
            sampleGround: terrainSampler ?? { _ in nil },
            collisionQuery: collisionQuery ?? { _ in [] }
        )
        let step = playerMount?.advanceMount(
            input: frameInput, cameraYaw: freeFlyCamera.yaw,
            weaponDrawn: locomotion.actorState.weaponDrawn, world: world
        )
        locomotion.advanceRiding(
            deltaTime: lastCameraDelta, feet: walkController.feetPosition,
            yaw: step?.yaw ?? freeFlyCamera.yaw, mount: step?.motion ?? .still
        )
    }

    /// One input frame of simulated player movement, shared by `.walk` and
    /// `.thirdPerson`: the same capsule, the same locomotion bridge, and the
    /// same behavior graph. Only where the eye ends up differs.
    private func advancePlayer(_ frameInput: CameraInput) {
        locomotion.actorState.riding = nil
        locomotion.actorState.setCamera(
            position: freeFlyCamera.position,
            forward: freeFlyCamera.forward,
            pitch: freeFlyCamera.pitch
        )
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
