// The session's half of the first-person arms (issue #190): attaching them to
// the renderer, hanging them off the eye each input frame, and the field of
// view policy. The renderer's half, which draws them into the near depth
// slice, is `RendererFirstPersonArms.swift`.

import Metal

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

    /// The vertical field of view this frame projects with: the first-person
    /// setting in first person, the shared world value everywhere else.
    ///
    /// Vanilla applies its own first-person field of view to the whole world
    /// and not only to the arms, which is what makes it a comfort setting
    /// rather than a lens on the hands, so this returns one angle for the
    /// frame rather than two.
    ///
    /// A conversation is projected at the shared world angle whatever mode it
    /// interrupted (issue #427): the dialogue camera stands outside the
    /// player's head, so the first-person comfort setting has nothing to say
    /// about it, and every conversation is framed the same way as a result.
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
