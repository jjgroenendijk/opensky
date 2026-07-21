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
        let now = CACurrentMediaTime()
        let dt = lastUpdateTime.map { Float(min(now - $0, 0.1)) } ?? 0
        lastUpdateTime = now
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
