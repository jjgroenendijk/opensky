// The session's half of the first-person arms: attach, place on the eye each frame, and
// the FOV policy. The renderer's half is `RendererFirstPersonArms.swift`.

import Metal
import OpenSkyRendering

extension Renderer {
    /// Attaches the assembled arms, sizing the draw rings for their groups and
    /// making their buffers resident, exactly as `setPlayerBody` does.
    public func setPlayerFirstPersonRig(_ rig: PlayerFirstPersonRig?) throws {
        let retiring = playerFirstPersonRig?.residencyAllocations ?? []
        playerFirstPersonRig = rig
        updatePlayerFirstPersonPose()
        if let rig {
            try growRings(
                drawCount: scene.drawCount + (playerBody?.render.drawCount ?? 0)
                    + rig.render.drawCount,
                instanceCount: scene.instanceCount + (playerBody?.render.instanceCount ?? 0)
                    + rig.render.instanceCount
            )
            residencySet.addAllocations(rig.residencyAllocations)
            residencySet.commit()
        }
        retireAllocations(retiring)
    }

    /// Hangs the arms off this frame's eye.
    ///
    /// In third person and in fly mode the eye is not where the player is
    /// looking from, so the arms are left where they were rather than being
    /// dragged out to the orbit camera: they are not drawn there, and moving
    /// them would rebuild their draw groups every frame for nothing.
    public func updatePlayerFirstPersonPose() {
        guard let playerFirstPersonRig, movementMode == .walk else { return }
        playerFirstPersonRig.place(
            eyePosition: freeFlyCamera.position,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch
        )
    }

    /// This frame's vertical FOV: the first-person setting in first person, else the world
    /// value. Vanilla applies it to the whole world, so it is one angle. A conversation
    /// always uses the world angle, because the dialogue camera is outside the head.
    public var sessionFOVYRadians: Float {
        isDialogueCameraEngaged
            ? DialogueCamera.fovYRadians
            : dialogueCameraRestoreFOVYRadians
    }

    /// Sets the first-person field of view and re-projects.
    public func setFirstPersonFOVY(radians: Float) {
        firstPersonCamera.setFOVY(radians: radians)
        rebuildProjection()
    }
}
