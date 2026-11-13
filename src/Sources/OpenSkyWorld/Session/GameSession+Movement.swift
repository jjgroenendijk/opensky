// Renderer camera movement split from Renderer.swift for file-length limits.

import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

extension GameSession.MovementSteps {
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
        session.dialogueCameraSteps.restorePlayerCameraPose()
        session.rigs.dialogueCameraState.camera.reset()
        session.freeFlyCamera = FreeFlyCamera(framing: newCamera)
        // Fly mode looks from eye height too, so a later switch to walk puts the feet
        // on the spot rather than an eye height below its floor.
        if let feet = newCamera.walkFeetPosition {
            session.freeFlyCamera.position = feet
                + SIMD3<Float>(0, 0, session.walkController.capsule.eyeHeight)
        }
        session.walkController.reset(cameraPosition: session.freeFlyCamera.position)
        // A reseed is a teleport: the bridge's edge state describes a place the
        // player is no longer in, so it must not raise a landing or a swim exit
        // on the next step.
        session.locomotion.reset()
        session.rigs.thirdPersonCamera.reset()
    }

    /// Puts the player's feet at `feet` and keeps the view, as a vehicle seat does.
    /// Third person keeps its orbit around the new feet.
    public func placePlayerFeet(at feet: SIMD3<Float>) {
        guard session.movementMode.isPlayerControlled else { return }
        let eye = feet + SIMD3<Float>(0, 0, session.walkController.capsule.eyeHeight)
        session.walkController.reset(cameraPosition: eye)
        session.freeFlyCamera.position = session.movementMode == .thirdPerson
            ? session.rigs.thirdPersonCamera.resolve(
                feetPosition: feet,
                yaw: session.freeFlyCamera.yaw,
                pitch: session.freeFlyCamera.pitch,
                collisionQuery: session.motion.collisionQuery ?? { _ in [] }
            )
            : eye
    }

    /// Puts the body's root on a seat and the eye on the seat idle's `head` bone, in
    /// the root's space, so the view sits in the seat. The seat holds without a head
    /// bone too: a walking step there would drop the player out of the seat state.
    public func seatPlayer(at root: float4x4, head: SIMD3<Float>?) {
        session.motion.playerSeat = root
        session.motion.seatedHead = head ?? session.motion.seatedHead
        guard let head = session.motion.seatedHead else {
            let origin = root.columns.3
            placePlayerFeet(at: SIMD3(origin.x, origin.y, origin.z))
            return
        }
        let eye = root * SIMD4(head, 1)
        placePlayerFeet(at: SIMD3(eye.x, eye.y, eye.z - session.walkController.capsule.eyeHeight))
    }

    /// Advances active movement mode by one input frame. First frame makes no
    /// move. dt clamps to 100 ms; WalkController further uses fixed substeps.
    public func advanceCamera() {
        guard let input = session.input else { return }
        // The dialogue camera stands in for the player's view between frames
        // (RendererDialogueCamera.swift). Everything below simulates the
        // player, and simulating against a pose that is looking at somebody
        // else would turn the player to face them, so the player's own pose
        // goes back first and the override is re-applied at the end.
        session.dialogueCameraSteps.restorePlayerCameraPose()
        // Menu mode pauses the sim: dt goes to zero so the camera holds its pose
        // while the clock keeps its mark fresh (resume carries no time jump).
        let dt = session.cameraClock.advance(
            to: session.renderer.wallClock.now,
            paused: session.worldSimPaused
        )
            * session.playerTimeScale * session.bowZoomTimeScale
        session.lastCameraDelta = min(max(dt, 0), WalkController.maximumFrameTime)
        var frameInput = input.makeInput(dt: dt)
        if session.motion.isPlayerParalysed, session.movementMode.isPlayerControlled {
            frameInput = frameInput.holdingStill
        }
        steerPlayerWalk(&frameInput)
        if frameInput.cycleCameraMode {
            setMovementMode(session.movementMode.next)
        }
        switch session.movementMode {
        case .fly:
            session.freeFlyCamera.update(frameInput)
        case .walk where session.motion.playerMount?.isMountActive == true,
             .thirdPerson where session.motion.playerMount?.isMountActive == true:
            advanceMounted(frameInput)
        case .walk where session.motion.playerSeat != nil,
             .thirdPerson where session.motion.playerSeat != nil:
            // The vehicle or the furniture places a seated player; only the view turns.
            session.freeFlyCamera.applyLook(
                lookRight: frameInput.lookRight,
                lookUp: frameInput.lookUp
            )
            session.locomotion.advanceSeated(
                deltaTime: session.lastCameraDelta, feet: session.walkController.feetPosition
            )
            if frameInput.moveForward != 0 || frameInput.moveRight != 0 || frameInput.jump {
                session.motion.playerFurniture?.playerAskedToStand()
            }
        case .walk, .thirdPerson:
            advancePlayer(frameInput)
        }
        session.rigSteps.updatePlayerBodyPose()
        session.rigSteps.updatePlayerFirstPersonPose()
        session.dialogueCameraSteps.applyDialogueCamera()
    }

    /// Switches camera mode, re-seating the capsule under the current eye when
    /// the new mode simulates a player. Shared by the camera key and the
    /// camera selector so the two cannot drift apart.
    public func setMovementMode(_ mode: CameraMovementMode) {
        guard mode != session.movementMode else { return }
        // Re-seating the capsule reads the view pose, which a live conversation
        // is standing in for; the mode change happens to the player's own pose
        // and the override goes back on top of the result.
        session.dialogueCameraSteps.restorePlayerCameraPose()
        defer { session.dialogueCameraSteps.applyDialogueCamera() }
        let wasPlayerControlled = session.movementMode.isPlayerControlled
        session.movementMode = mode
        session.rigs.thirdPersonCamera.reset()
        // The field of view is per mode, so the projection follows the mode now.
        guard mode.isPlayerControlled else { return }
        // Coming from fly, the eye is wherever the developer left it and the
        // capsule has to be placed under it. Switching between the two player
        // modes must not move the capsule at all: the body is already standing
        // somewhere, and re-seating it would teleport the player by the orbit
        // distance every time the camera key is pressed.
        guard !wasPlayerControlled else { return }
        session.walkController.reset(cameraPosition: session.freeFlyCamera.position)
        settlePlayerOnGround()
        session.locomotion.reset()
    }

    /// Stands the player's feet on the ground under them, as `coc` does, so a placement
    /// from any height does not end in a fall. False while nothing under the spot is loaded.
    @discardableResult
    public func settlePlayerOnGround() -> Bool {
        guard
            session.movementMode.isPlayerControlled, session.motion.playerSeat == nil,
            session.motion.playerMount?.isMountActive != true
        else { return false }
        var probe = session.walkController
        guard probe.standOnGround(
            sampleGround: session.motion.terrainSampler ?? { _ in nil },
            query: session.motion.collisionQuery ?? { _ in [] }
        ) else { return false }
        placePlayerFeet(at: probe.feetPosition)
        return true
    }

    private var walkCollisionQuery: CapsuleWorldCollider.CandidateQuery {
        guard session.motion.playerWalkIgnoresStatics, !session.motion.playerWalkPath.isEmpty else {
            return session.motion.collisionQuery ?? { _ in [] }
        }
        return { _ in [] }
    }

    /// Turns the view to the package walk's next waypoint and holds forward, until
    /// the last one is reached.
    private func steerPlayerWalk(_ frameInput: inout CameraInput) {
        guard
            !session.motion.playerWalkPath.isEmpty,
            session.movementMode.isPlayerControlled else { return }
        let feet = session.walkController.feetPosition
        let remaining = PlayerPackageWalk.remainingPath(session.motion.playerWalkPath, feet: feet)
        session.motion.playerWalkPath = remaining
        guard
            let next = remaining.first,
            let yaw = PlayerPackageWalk.steeringYaw(feet: feet, target: next)
        else {
            session.motion.onPlayerWalkArrived?()
            return
        }
        session.freeFlyCamera.yaw = yaw
        frameInput.moveForward = 1
        frameInput.moveRight = 0
        frameInput.lookRight = 0
    }

    /// One input frame on a mount: the view turns, the mount moves, and the rider's
    /// graph follows. The vehicle pass places the rider on the saddle.
    private func advanceMounted(_ frameInput: CameraInput) {
        session.freeFlyCamera.applyLook(lookRight: frameInput.lookRight, lookUp: frameInput.lookUp)
        if let limit = session.motion.playerMount?.maximumLookDown {
            session.freeFlyCamera.pitch = max(session.freeFlyCamera.pitch, -limit)
        }
        session.locomotion.actorState.setCamera(
            position: session.freeFlyCamera.position,
            forward: session.freeFlyCamera.forward,
            pitch: session.freeFlyCamera.pitch
        )
        let rider = MountRules.riderInput(
            frameInput, rightHandType: session.locomotion.actorState.rightHandType,
            kind: session.motion.playerMount?.mountKind ?? .horse
        )
        session.locomotion.acceptFrame(rider)
        let world = MountStepWorld(
            sampleGround: session.motion.terrainSampler ?? { _ in nil },
            collisionQuery: session.motion.collisionQuery ?? { _ in [] }
        )
        let step = session.motion.playerMount?.advanceMount(
            input: frameInput, cameraYaw: session.freeFlyCamera.yaw,
            weaponDrawn: session.locomotion.actorState.weaponDrawn, world: world
        )
        session.locomotion.advanceRiding(
            deltaTime: session.lastCameraDelta, feet: session.walkController.feetPosition,
            yaw: step?.yaw ?? session.freeFlyCamera.yaw, mount: step?.motion ?? .still
        )
    }

    /// One input frame of simulated player movement, shared by `.walk` and
    /// `.thirdPerson`: the same capsule, the same locomotion bridge, and the
    /// same behavior graph. Only where the eye ends up differs.
    private func advancePlayer(_ frameInput: CameraInput) {
        session.locomotion.actorState.riding = nil
        session.locomotion.actorState.setCamera(
            position: session.freeFlyCamera.position,
            forward: session.freeFlyCamera.forward,
            pitch: session.freeFlyCamera.pitch
        )
        session.locomotion.acceptFrame(frameInput)
        session.locomotion.speedScale = session.motion.playerSpeedScale?() ?? 1
        session.walkController.carryVelocity = session.motion.characterCarry?(
            session.walkController.capsule, session.walkController.feetPosition
        ) ?? .zero
        session.walkController.update(
            camera: &session.freeFlyCamera,
            input: frameInput,
            sampleGround: session.motion.terrainSampler ?? { _ in nil },
            collisionQuery: walkCollisionQuery,
            plan: { [locomotion = session.locomotion] state in locomotion.plan(state) }
        )
        // The view follows the drawn capsule, blended between steps.
        session.freeFlyCamera.position = session.walkController.drawnCameraPosition
        guard session.movementMode == .thirdPerson else { return }
        // Third person pulls the eye back out to the orbit position, so the
        // look angles `WalkController.update` integrated are the ones used here.
        session.freeFlyCamera.position = session.rigs.thirdPersonCamera.resolve(
            feetPosition: session.walkController.drawnFeetPosition,
            yaw: session.freeFlyCamera.yaw,
            pitch: session.freeFlyCamera.pitch,
            collisionQuery: session.motion.collisionQuery ?? { _ in [] }
        )
    }
}
