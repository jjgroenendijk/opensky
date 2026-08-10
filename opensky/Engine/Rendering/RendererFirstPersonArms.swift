// The renderer's half of the first-person arms (issue #190).
//
// Held here rather than in the scene for the same reason the body is
// (`RendererPlayerBody.swift`): the arms are streaming-independent, so a scene
// swap must not take them with it.
//
// **Why they are encoded apart from every other draw group.** The arms sit
// 15 to 45 units in front of the eye, and the capsule's own radius is 24, so a
// player standing against a wall has world geometry closer to the camera than
// their own hands. Depth-tested like ordinary geometry, the arms would push
// through that wall. Vanilla's own answer to this is in its renderer and is
// not observable from the install, so what OpenSky does is a deliberate
// deviation, recorded as one in docs/engine/behavior-runtime.md:
//
// The arms are encoded last, with the same projection and the same pipelines
// as everything else, into a viewport whose depth range is compressed to
// `[0, FirstPersonCamera.depthSlice]`. The viewport transform is linear and
// monotonic, so within the arms depth ordering is untouched and a hand behind
// a forearm is still behind it. Against the world, every arm fragment lands
// nearer than any world fragment further than `nearPlane / (1 - depthSlice)`
// — about 10.2 units with the 10-unit near plane — which is well inside the
// capsule and therefore unreachable by world geometry.
//
// The alternative, a second render pass with a cleared depth attachment, costs
// an encoder and a full-target depth clear per frame for the same result.
// The alternative of simply disabling the depth test costs correct
// self-occlusion, which is the one thing the arms genuinely need.

import Metal
import simd

extension Renderer {
    /// Attaches the assembled arms, sizing the draw rings for their groups and
    /// making their buffers resident, exactly as `setPlayerBody` does.
    func setPlayerFirstPersonRig(_ rig: PlayerFirstPersonRig?) throws {
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
    func updatePlayerFirstPersonPose() {
        guard let playerFirstPersonRig, movementMode == .walk else { return }
        playerFirstPersonRig.place(
            eyePosition: freeFlyCamera.position,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch
        )
    }

    /// The arms' contribution to the per-frame animation pass, mirroring
    /// `updatePlayerBodyAnimation`.
    func updatePlayerFirstPersonAnimation(enabled: Bool) -> Int {
        guard let playerFirstPersonRig else { return 0 }
        return enabled
            ? playerFirstPersonRig.animation.update(at: 0)
            : playerFirstPersonRig.animation.resetToBindPose()
    }

    /// Whether the arms are drawn to the camera this frame. First person only:
    /// fly and third person show the body instead.
    var areFirstPersonArmsVisible: Bool {
        rigVisibility.drawsArms
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
    var activeFOVYRadians: Float {
        isDialogueCameraEngaged
            ? DialogueCamera.fovYRadians
            : dialogueCameraRestoreFOVYRadians
    }

    /// Rebuilds `projectionMatrix` for the current mode, field of view, and
    /// drawable size. Called on resize, on a camera-mode change, and when the
    /// field-of-view control moves, so the three cannot disagree.
    func rebuildProjection() {
        projectionMatrix = MatrixMath.perspective(
            fovYRadians: activeFOVYRadians,
            aspectRatio: drawableAspectRatio,
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
    }

    /// Sets the first-person field of view and re-projects.
    func setFirstPersonFOVY(radians: Float) {
        firstPersonCamera.setFOVY(radians: radians)
        rebuildProjection()
    }

    /// Encodes the arms into the near depth slice, then restores the full
    /// viewport so everything encoded after them (the SWF layer, the dev UI)
    /// is unaffected.
    func encodeFirstPersonArms(
        descriptor: MTL4RenderPassDescriptor,
        state: inout ScenePassState
    ) {
        guard
            areFirstPersonArmsVisible,
            let rig = playerFirstPersonRig,
            let target = descriptor.colorAttachments[0].texture
        else { return }
        let width = Double(target.width)
        let height = Double(target.height)
        state.encoder.setViewport(MTLViewport(
            originX: 0, originY: 0, width: width, height: height,
            znear: 0, zfar: Double(FirstPersonCamera.depthSlice)
        ))
        encode(
            groups: rig.render.opaque,
            staticPipeline: opaquePipeline,
            skinnedPipeline: skinnedOpaquePipeline,
            state: &state
        )
        encode(
            groups: rig.render.alphaTested,
            staticPipeline: alphaTestPipeline,
            skinnedPipeline: skinnedAlphaTestPipeline,
            state: &state
        )
        state.encoder.setViewport(MTLViewport(
            originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1
        ))
    }
}
