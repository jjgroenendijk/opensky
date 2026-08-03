// The renderer's half of the third-person player body (issue #189).
//
// The body is held here rather than in the scene because it is
// streaming-independent: `setScene` replaces every cell-owned draw list several
// times a minute, and the player is not owned by a cell. So its draw groups are
// appended to the scene's at encode time (`opaqueDrawGroups`,
// `alphaTestedDrawGroups`), which both the scene pass and the shadow pass read,
// and its GPU allocations join the residency set once and stay.
//
// See docs/engine/behavior-runtime.md for the clock split: the pose the body
// draws comes from the behavior graph stepped on the simulation clock, and this
// file only publishes it.

import Metal
import simd

extension Renderer {
    /// Attaches the assembled body, sizing the draw rings for its groups and
    /// making its buffers resident. Replacing an attached body (a new equipped
    /// set) retires the old one's allocations the same way a scene swap does.
    func setPlayerBody(_ body: PlayerBody?) throws {
        let retiring = playerBody?.residencyAllocations ?? []
        playerBody = body
        updatePlayerBodyPose()
        if let body {
            try growRingsForPlayerBody(body)
            residencySet.addAllocations(body.residencyAllocations)
            residencySet.commit()
        }
        retireAllocations(retiring)
    }

    /// Moves the body onto the capsule and refreshes its palettes.
    ///
    /// Called once per input frame, after the controller has resolved this
    /// frame's position, so the body and the camera never disagree by a frame.
    /// In fly mode the body is left exactly where the player last stood: fly is
    /// a developer view of the same world, not a different world.
    func updatePlayerBodyPose() {
        guard let playerBody, movementMode.isPlayerControlled else { return }
        playerBody.place(
            feetPosition: walkController.feetPosition,
            yaw: freeFlyCamera.yaw
        )
    }

    /// The player's contribution to the per-frame animation pass. Mirrors what
    /// `RenderScene.updateAnimations` does for cell-owned actors, including the
    /// `World > Environment` animation A/B toggle.
    func updatePlayerBodyAnimation(enabled: Bool) -> Int {
        guard let playerBody else { return 0 }
        return enabled
            ? playerBody.animation.update(at: 0)
            : playerBody.animation.resetToBindPose()
    }

    /// Scene opaque groups plus the player's, so one list feeds both passes and
    /// neither can forget the body.
    ///
    /// The player draws last within its own list. Order between groups is a
    /// draw-call ordering only — depth testing decides what is visible — so this
    /// is about keeping the scene's grouping stable across frames rather than
    /// about correctness.
    var opaqueDrawGroups: [DrawGroup] {
        guard let playerBody, isPlayerBodyVisible else { return scene.opaque }
        return scene.opaque + playerBody.render.opaque
    }

    var alphaTestedDrawGroups: [DrawGroup] {
        guard let playerBody, isPlayerBodyVisible else { return scene.alphaTested }
        return scene.alphaTested + playerBody.render.alphaTested
    }

    /// Whether the body is drawn this frame.
    ///
    /// First person deliberately does not draw it: the M14 body is the
    /// third-person one, and drawing it with the eye inside its head would fill
    /// the frame with the inside of a skull. The first-person body and arms are
    /// item 14.7 (#190), which is where that gets its own answer. Fly mode draws
    /// it, so a developer can fly around the character and look at it.
    var isPlayerBodyVisible: Bool {
        movementMode != .walk
    }

    /// Grows the draw and instance rings to cover the scene plus the body. The
    /// scene's own sizing runs in `setScene` and knows nothing about the player,
    /// so a body attached over a large scene has to ask for its own headroom.
    private func growRingsForPlayerBody(_ body: PlayerBody) throws {
        try growRings(
            drawCount: scene.drawCount + body.render.drawCount,
            instanceCount: scene.instanceCount + body.render.instanceCount
        )
    }
}
