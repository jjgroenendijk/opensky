// The renderer's half of the first-person arms, held outside the scene so a swap keeps
// them. The arms sit closer than the capsule radius, so they are drawn last into a
// compressed depth range `[0, FirstPersonCamera.depthSlice]`. That keeps
// self-occlusion without a second pass or depth clear (docs/engine/first-person.md).

import Metal
import OpenSkyFormatsCore
import simd

extension Renderer {
    /// Whether the arms are drawn to the camera this frame. First person only:
    /// fly and third person show the body instead.
    public var areFirstPersonArmsVisible: Bool {
        rigVisibility.drawsArms && effects.loadingCover == nil
    }

    /// The vertical field of view this frame projects with, from the driver:
    /// the first-person setting in first person, the dialogue camera's angle
    /// in a conversation, the shared world value everywhere else.
    public var activeFOVYRadians: Float {
        frameDriver?.projectionFOVYRadians ?? FirstPersonCamera.defaultFOVYRadians
    }

    /// Rebuilds `projectionMatrix` for the current mode, field of view, and
    /// drawable size. Called on resize, on a camera-mode change, and when the
    /// field-of-view control moves, so the three cannot disagree.
    public func rebuildProjection() {
        projectionMatrix = MatrixMath.perspective(
            fovYRadians: activeFOVYRadians,
            aspectRatio: drawableAspectRatio,
            nearZ: Self.nearPlane,
            farZ: Self.farPlane
        )
    }

    /// Encodes the arms into the near depth slice, then restores the full
    /// viewport so everything encoded after them (the SWF layer, the dev UI)
    /// is unaffected.
    public func encodeFirstPersonArms(
        descriptor: MTL4RenderPassDescriptor,
        state: inout ScenePassState
    ) {
        guard
            areFirstPersonArmsVisible,
            let rig = frameDriver?.firstPersonRig,
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
            morphedSkinnedPipeline: morphedSkinnedOpaquePipeline,
            state: &state
        )
        encode(
            groups: rig.render.alphaTested,
            staticPipeline: alphaTestPipeline,
            skinnedPipeline: skinnedAlphaTestPipeline,
            morphedSkinnedPipeline: morphedSkinnedAlphaTestPipeline,
            state: &state
        )
        state.encoder.setViewport(MTLViewport(
            originX: 0, originY: 0, width: width, height: height, znear: 0, zfar: 1
        ))
    }
}
