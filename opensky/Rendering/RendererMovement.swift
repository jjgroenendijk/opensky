// Renderer camera movement split from Renderer.swift for file-length limits.

import QuartzCore

extension Renderer {
    func reseedMovement(camera newCamera: SceneCamera) {
        freeFlyCamera = FreeFlyCamera(framing: newCamera)
        if movementMode == .walk, let feet = newCamera.walkFeetPosition {
            freeFlyCamera.position = feet
                + SIMD3<Float>(0, 0, walkController.capsule.eyeHeight)
        }
        walkController.reset(cameraPosition: freeFlyCamera.position)
    }

    /// Advances active movement mode by one input frame. First frame makes no
    /// move. dt clamps to 100 ms; WalkController further uses fixed substeps.
    func advanceCamera() {
        guard let input else { return }
        // Menu mode pauses the sim: dt goes to zero so the camera holds its pose
        // while the clock keeps its mark fresh (resume carries no time jump).
        let dt = cameraClock.advance(to: CACurrentMediaTime(), paused: worldSimPaused)
        if input.consumeShadowToggle() {
            sunShadowsEnabled.toggle()
        }
        let frameInput = input.makeInput(dt: dt)
        if frameInput.toggleWalkMode {
            movementMode = movementMode == .fly ? .walk : .fly
            if movementMode == .walk {
                walkController.reset(cameraPosition: freeFlyCamera.position)
            }
        }
        switch movementMode {
        case .fly:
            freeFlyCamera.update(frameInput)
        case .walk:
            walkController.update(
                camera: &freeFlyCamera,
                input: frameInput,
                sampleGround: terrainSampler ?? { _ in nil },
                collisionQuery: collisionQuery ?? { _ in [] }
            )
        }
    }
}
