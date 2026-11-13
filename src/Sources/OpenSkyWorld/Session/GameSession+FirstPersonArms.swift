// The session's half of the first-person arms: attach, place on the eye each frame, and
// the FOV policy. The renderer's half is `RendererFirstPersonArms.swift`.

import Metal
public import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering

extension GameSession.RigSteps {
    /// Attaches the assembled arms, sizing the draw rings for their groups and
    /// making their buffers resident, exactly as `setPlayerBody` does.
    public func setPlayerFirstPersonRig(_ rig: PlayerFirstPersonRig?) throws {
        let retiring = session.rigs.playerFirstPersonRig?.residencyAllocations ?? []
        session.rigs.playerFirstPersonRig = rig
        updatePlayerFirstPersonPose()
        if let rig {
            try session.renderer.growRings(
                drawCount: session.renderer.scene
                    .drawCount + (session.rigs.playerBody?.render.drawCount ?? 0)
                    + rig.render.drawCount,
                instanceCount: session.renderer.scene
                    .instanceCount + (session.rigs.playerBody?.render.instanceCount ?? 0)
                    + rig.render.instanceCount
            )
            session.renderer.residencySet.addAllocations(rig.residencyAllocations)
            session.renderer.residencySet.commit()
        }
        session.renderer.retireAllocations(retiring)
    }

    /// Hangs the arms off this frame's eye.
    ///
    /// In third person and in fly mode the eye is not where the player is
    /// looking from, so the arms are left where they were rather than being
    /// dragged out to the orbit camera: they are not drawn there, and moving
    /// them would rebuild their draw groups every frame for nothing.
    public func updatePlayerFirstPersonPose() {
        guard
            let playerFirstPersonRig = session.rigs.playerFirstPersonRig,
            session.movementMode == .walk else { return }
        playerFirstPersonRig.place(
            eyePosition: session.freeFlyCamera.position,
            yaw: session.freeFlyCamera.yaw,
            pitch: session.freeFlyCamera.pitch
        )
    }

    /// This frame's vertical FOV: the first-person setting in first person, else the world
    /// value. Vanilla applies it to the whole world, so it is one angle. A conversation
    /// always uses the world angle, because the dialogue camera is outside the head.
    public var sessionFOVYRadians: Float {
        session.dialogueCameraSteps.isDialogueCameraEngaged
            ? DialogueCamera.fovYRadians
            : session.dialogueCameraSteps.dialogueCameraRestoreFOVYRadians
    }

    /// Sets the first-person field of view and re-projects.
    public func setFirstPersonFOVY(radians: Float) {
        session.rigs.firstPersonCamera.setFOVY(radians: radians)
    }
}
