// The session's half of the third-person body: attach, and place on the capsule each
// frame. The renderer's half is `RendererPlayerBody.swift`.

import Metal
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering

extension GameSession {
    /// Attaches the assembled body, sizing the draw rings for its groups and
    /// making its buffers resident. Replacing an attached body (a new equipped
    /// set) retires the old one's allocations the same way a scene swap does.
    public func setPlayerBody(_ body: PlayerBody?) throws {
        let retiring = playerBody?.residencyAllocations ?? []
        playerBody = body
        updatePlayerBodyPose()
        if let body {
            try renderer.growRingsForPlayerBody(body)
            renderer.residencySet.addAllocations(body.residencyAllocations)
            renderer.residencySet.commit()
        }
        renderer.retireAllocations(retiring)
    }

    /// Moves the body onto the capsule and refreshes its palettes.
    ///
    /// Called once per input frame, after the controller has resolved this
    /// frame's position, so the body and the camera never disagree by a frame.
    /// In fly mode the body is left exactly where the player last stood: fly is
    /// a developer view of the same world, not a different world.
    public func updatePlayerBodyPose() {
        guard let playerBody, movementMode.isPlayerControlled else { return }
        // A seat clip poses the body from the vehicle's root, as it does a rider's.
        if let playerSeat {
            playerBody.place(at: playerSeat)
            return
        }
        playerBody.place(
            feetPosition: walkController.drawnFeetPosition,
            yaw: freeFlyCamera.yaw
        )
    }
}
