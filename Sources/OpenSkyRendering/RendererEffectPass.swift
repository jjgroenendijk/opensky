// Effect models join the scene's draw lists; membranes re-draw their target's
// meshes after the alpha-tested pass. See docs/rendering/visual-effects.md.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
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

    /// Draws and instances the player rigs, the loading cover, and the effect particle
    /// systems add on top of the scene.
    var rigDrawCount: Int {
        (frameInput.rigs.body?.render.drawCount ?? 0)
            + (frameInput.rigs.arms?.render.drawCount ?? 0)
            + (effects.loadingCover?.drawCount ?? 0) + effects.particles.count
            + (effects.loadingCover?.particles.count ?? 0)
    }

    var rigInstanceCount: Int {
        (frameInput.rigs.body?.render.instanceCount ?? 0)
            + (frameInput.rigs.arms?.render.instanceCount ?? 0)
            + (effects.loadingCover?.instanceCount ?? 0)
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
            guard let body = frameInput.rigs.body, isPlayerBodyVisible else { return [] }
            return body.render.opaque + body.render.alphaTested
        case let .actor(owner):
            return actorGroupsByOwner[owner] ?? []
        case .playerWeapon:
            let body = isPlayerBodyVisible ? frameInput.rigs.body?.render : nil
            return [frameInput.rigs.arms?.render, body].compactMap(\.self)
                .flatMap { $0.opaque + $0.alphaTested }
                .filter { !$0.mesh.isSkinned }
        case let .actorWeapon(owner):
            return (actorGroupsByOwner[owner] ?? []).filter { !$0.mesh.isSkinned }
        }
    }
}

nonisolated extension DrawGroup {
    /// The scene's actor-layer groups split by instance owner, opaque before alpha-tested.
    static func actorGroupsByOwner(in scene: RenderScene) -> [UInt32: [DrawGroup]] {
        var byOwner: [UInt32: [DrawGroup]] = [:]
        for group in scene.opaque + scene.alphaTested where group.layer == .actors {
            var owners: [UInt32] = []
            var instancesByOwner: [UInt32: [DrawInstance]] = [:]
            for instance in group.instances {
                if instancesByOwner[instance.owner] == nil {
                    owners.append(instance.owner)
                }
                instancesByOwner[instance.owner, default: []].append(instance)
            }
            for owner in owners {
                byOwner[owner, default: []].append(DrawGroup(
                    mesh: group.mesh,
                    material: group.material,
                    faceMorph: group.faceMorph,
                    instances: instancesByOwner[owner] ?? []
                ))
            }
        }
        return byOwner
    }
}
