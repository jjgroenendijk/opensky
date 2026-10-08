// Rigid shapes with a blending alpha property: stream water, foam, waterfalls.
// They draw after the cell water plane, farthest group first, and read depth
// without writing it, so a surface behind another one still shows through.

import Metal
import simd

extension Renderer {
    func encodeBlendedGroups(state: inout ScenePassState) {
        let groups = frameDrawGroups.alphaTested
        let order = Self.blendedDrawOrder(groups, eye: freeFlyCamera.position)
        guard !order.isEmpty else { return }
        let pipelines = GroupPipelines(
            staticMesh: blendedPipeline, skinned: skinnedAlphaTestPipeline,
            morphedSkinned: morphedSkinnedAlphaTestPipeline
        ).resolved(debug: isRenderDebugActive ? debugPipelines : nil)
        let layers = effectiveRenderLayers
        state.cullList = .alphaTested
        state.encoder.setDepthStencilState(waterDepthState)
        var boundPipeline: ObjectIdentifier?
        for index in order where layers.contains(groups[index].layer) {
            encode(
                group: groups[index], at: index, pipelines: pipelines,
                boundPipeline: &boundPipeline, state: &state
            )
        }
        state.cullList = nil
        state.encoder.setDepthStencilState(depthState)
    }

    /// Indices of the blended groups, farthest first, so a nearer surface blends
    /// over a farther one. The instances inside one group are not sorted.
    nonisolated static func blendedDrawOrder(_ groups: [DrawGroup], eye: SIMD3<Float>) -> [Int] {
        groups.indices
            .filter { groups[$0].drawsBlended }
            .map { (index: $0, distance: simd_distance_squared(groups[$0].lightingCenter, eye)) }
            .sorted { $0.distance != $1.distance ? $0.distance > $1.distance : $0.index < $1.index }
            .map(\.index)
    }
}
