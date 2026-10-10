// Decals and the particle systems of effect models, the two effect lists the
// world hands the renderer when they change rather than every frame. See
// docs/rendering/decals.md and docs/rendering/visual-effects.md.

import Metal
import OpenSkyShaderTypes

extension Renderer {
    /// Replaces the decals. Their instances go into one fresh buffer, and the
    /// previous one retires once in-flight frames drain.
    public func setDecals(_ batches: [DecalBatch]) throws {
        let instances = batches.flatMap(\.instances)
        var buffer: MTLBuffer?
        if !instances.isEmpty {
            guard
                let made = device.makeBuffer(
                    bytes: instances,
                    length: instances.count * MemoryLayout<DecalInstance>.stride,
                    options: .storageModeShared
                )
            else { throw RendererError.bufferAllocationFailed }
            made.label = "Decals"
            buffer = made
        }
        let retiring = effects.decalAllocations
        effects.decalBatches = instances.isEmpty ? [] : batches.filter { !$0.instances.isEmpty }
        effects.decalBuffer = buffer
        addResident(effects.decalAllocations)
        retireAllocations(retiring)
    }

    /// Replaces the effect models' particle systems.
    public func setEffectParticles(_ playbacks: [ParticlePlayback]) {
        let retiring = effects.particleAllocations
        effects.particles = playbacks
        addResident(effects.particleAllocations)
        retireAllocations(retiring)
    }

    private func addResident(_ allocations: [MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        residencySet.addAllocations(allocations)
        residencySet.commit()
    }

    /// One instanced six-vertex draw per decal texture. Skipped in a debug view,
    /// which shows the surface under it.
    func encodeDecals(state: inout ScenePassState) {
        effects.lastDecalDraws = 0
        guard
            let buffer = effects.decalBuffer, !effects.decalBatches.isEmpty,
            !isRenderDebugActive, effectiveRenderLayers.contains(.particles)
        else { return }
        state.encoder.setRenderPipelineState(effects.decalPipeline)
        state.encoder.setDepthStencilState(effects.depthState)
        state.encoder.setDepthBias(-1, slopeScale: -1, clamp: 0)
        state.encoder.setCullMode(.back)
        var first = 0
        for batch in effects.decalBatches {
            argumentTable.setAddress(
                buffer.gpuAddress + UInt64(first * MemoryLayout<DecalInstance>.stride),
                index: BufferIndex.particleInstances.rawValue
            )
            argumentTable.setTexture(
                streamedBinding(batch.texture),
                index: TextureIndex.diffuse.rawValue
            )
            state.encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: batch.instances.count
            )
            first += batch.instances.count
            state.stats.drawCalls += 1
            state.stats.drawnInstances += batch.instances.count
            effects.lastDecalDraws += batch.instances.count
        }
        state.encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        state.encoder.setDepthStencilState(depthState)
    }
}

extension EffectLayer {
    var decalAllocations: [MTLAllocation] {
        (decalBuffer.map { [$0] } ?? []) + decalBatches.map(\.texture)
    }

    var particleAllocations: [MTLAllocation] {
        particles.flatMap { [$0.instanceBuffer, $0.texture] as [MTLAllocation] }
    }
}
