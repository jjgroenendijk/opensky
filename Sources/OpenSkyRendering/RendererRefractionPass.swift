// Refraction shapes, such as the heat haze over a fire: after the blended groups the
// scene pass splits on a colour copy, and each refraction shape draws that copy, bent
// by its normal map (docs/rendering/surface-shading.md).

import Metal
import OpenSkyRenderResources
import OpenSkyShaderTypes

/// The colour copy refraction shapes read, and whether this frame splits for it.
struct RefractionState {
    var splits = false
    var copy: MTLTexture?
}

extension Renderer {
    /// Indices into the alpha-tested list of the refraction groups this frame draws.
    private func refractionGroupIndices() -> [Int] {
        let layers = effectiveRenderLayers
        return frameDrawGroups.alphaTested.indices.filter {
            let group = frameDrawGroups.alphaTested[$0]
            return group.drawsRefraction && layers.contains(group.layer)
        }
    }

    /// True when a refraction shape is in view, so the pass must store its depth.
    func refractionSplits() -> Bool {
        shadingTerms.contains(.refraction) && !isRenderDebugActive
            && frameDrawGroups.alphaTested.contains(where: \.drawsRefraction)
    }

    /// False when the split cannot open its second encoder; the frame is then dropped.
    func encodeRefraction(
        descriptor: MTL4RenderPassDescriptor,
        frameOffset: Int,
        state: inout ScenePassState
    ) -> Bool {
        let indices = refractionGroupIndices()
        guard refraction.splits, !indices.isEmpty else { return true }
        guard let colour = descriptor.colorAttachments[0].texture else {
            state.encoder.endEncoding()
            return false
        }
        guard
            let split = splitScenePass(
                descriptor: descriptor, state: state, frameOffset: frameOffset,
                copy: ScenePassCopy(source: colour, target: \.refraction.copy, label: "Refraction")
            )
        else { return false }
        state = split
        let pipelines = GroupPipelines(
            staticMesh: opaquePipeline, skinned: skinnedOpaquePipeline,
            morphedSkinned: morphedSkinnedOpaquePipeline
        )
        state.cullList = .alphaTested
        state.materialDepth = .readOnly
        var boundPipeline: ObjectIdentifier?
        for index in indices {
            encode(
                group: frameDrawGroups.alphaTested[index], at: index, pipelines: pipelines,
                boundPipeline: &boundPipeline, state: &state
            )
        }
        state.cullList = nil
        endMaterialDrawState(state: &state)
        return true
    }
}
