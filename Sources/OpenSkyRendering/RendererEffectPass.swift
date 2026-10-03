// Effect models join the scene's draw lists; membranes re-draw their target's
// meshes after the alpha-tested pass. See docs/rendering/visual-effects.md.

import Metal
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// Replaces the effect models. Rings grow to fit, new allocations go resident,
    /// and the previous models retire once in-flight frames drain.
    public func setEffectPlacements(_ placements: [RenderPlacement]) throws {
        let next = RenderScene(instances: placements)
        try growRings(
            drawCount: scene.drawCount + rigDrawCount + next.drawCount,
            instanceCount: scene.instanceCount + rigInstanceCount + next.instanceCount
        )
        let retiring = effects.scene.residencyAllocations
        effects.scene = next
        let added = next.residencyAllocations
        if !added.isEmpty {
            residencySet.addAllocations(added)
            residencySet.commit()
        }
        retireAllocations(retiring)
    }

    /// Replaces the membranes and grows the rings for the draws they repeat.
    public func setMembranes(_ membranes: [MembraneDraw]) throws {
        effects.membranes = membranes
        guard !membranes.isEmpty else { return }
        let groups = membranes.prefix(EffectLayer.membraneLimit)
            .flatMap { membraneGroups(for: $0.target) }
        try growRings(
            drawCount: scene.drawCount + rigDrawCount + effects.scene.drawCount + groups.count,
            instanceCount: scene.instanceCount + rigInstanceCount + effects.scene.instanceCount
                + groups.reduce(0) { $0 + $1.instances.count }
        )
    }

    /// Draws and instances the player rigs add on top of the scene.
    var rigDrawCount: Int {
        (frameDriver?.playerBodyRig?.render.drawCount ?? 0)
            + (frameDriver?.firstPersonRig?.render.drawCount ?? 0)
    }

    var rigInstanceCount: Int {
        (frameDriver?.playerBodyRig?.render.instanceCount ?? 0)
            + (frameDriver?.firstPersonRig?.render.instanceCount ?? 0)
    }

    /// Encodes every membrane over the meshes of its target. Skipped in a debug view,
    /// which replaces the shaded surface. A membrane that would overflow the rings waits.
    func encodeMembranes(state: inout ScenePassState) {
        effects.lastMembraneDraws = 0
        guard !effects.membranes.isEmpty, !isRenderDebugActive else { return }
        state.encoder.setDepthStencilState(effects.depthState)
        state.encoder.setDepthBias(-1, slopeScale: -1, clamp: 0)
        for (index, membrane) in effects.membranes.prefix(EffectLayer.membraneLimit).enumerated() {
            let groups = membraneGroups(for: membrane.target)
            let instances = groups.reduce(0) { $0 + $1.instances.count }
            guard
                !groups.isEmpty,
                state.drawCursor + groups.count <= drawUniformSlotCapacity,
                state.instanceCursor + instances <= instanceSlotCapacity
            else { continue }
            var uniforms = MembraneUniforms(
                fill: SIMD4(membrane.fill, 0),
                edge: SIMD4(membrane.edge, membrane.edgeFalloff)
            )
            let offset = EffectLayer.uniformStride
                * (state.slot * EffectLayer.membraneLimit + index)
            effects.uniformBuffer.contents().advanced(by: offset)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<MembraneUniforms>.size)
            argumentTable.setAddress(
                effects.uniformBuffer.gpuAddress + UInt64(offset),
                index: BufferIndex.membraneUniforms.rawValue
            )
            encode(
                groups: groups,
                staticPipeline: effects.staticPipeline,
                skinnedPipeline: effects.skinnedPipeline,
                morphedSkinnedPipeline: effects.morphedPipeline,
                state: &state
            )
            effects.lastMembraneDraws += 1
        }
        state.encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        state.encoder.setDepthStencilState(depthState)
    }

    /// The draw groups of one target, cut down to its own instances.
    func membraneGroups(for target: MembraneTarget) -> [DrawGroup] {
        switch target {
        case .player:
            guard let body = frameDriver?.playerBodyRig, isPlayerBodyVisible else { return [] }
            return body.render.opaque + body.render.alphaTested
        case let .actor(owner):
            return (scene.opaque + scene.alphaTested).compactMap { group in
                guard group.layer == .actors else { return nil }
                return group.owned(by: owner)
            }
        }
    }
}

nonisolated extension DrawGroup {
    /// The same mesh and material with only `owner`'s instances, or nil when it has none.
    func owned(by owner: UInt32) -> DrawGroup? {
        let mine = instances.filter { $0.owner == owner }
        guard !mine.isEmpty else { return nil }
        return DrawGroup(mesh: mesh, material: material, faceMorph: faceMorph, instances: mine)
    }
}
