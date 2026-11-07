// Decals and the particle systems of effect models, the two effect lists the
// world hands the renderer when they change rather than every frame. See
// docs/rendering/decals.md and docs/rendering/visual-effects.md.

import Metal
import OpenSkyRenderResources
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
    /// Replaces the effect models' particle systems. Each may take a draw-ring slot for
    /// its point lights, so the rings grow to fit.
    public func setEffectParticles(_ playbacks: [ParticlePlayback]) throws {
        let retiring = effects.particleAllocations
        effects.particles = playbacks
        try growRings(
            drawCount: scene.drawCount + rigDrawCount + effects.scene.drawCount,
            instanceCount: scene.instanceCount + rigInstanceCount + effects.scene.instanceCount
        )
        addResident(effects.particleAllocations)
        retireAllocations(retiring)
    }

    private func addResident(_ allocations: [MTLAllocation]) {
        guard !allocations.isEmpty else { return }
        residencySet.addAllocations(allocations)
        residencySet.commit()
    }

    var decalsDraw: Bool {
        effects.decalBuffer != nil && !effects.decalBatches.isEmpty && !isRenderDebugActive
            && effectiveRenderLayers.contains(.particles)
    }

    /// Projected decals need the scene depth copy, so they ask the frame to make one.
    var projectedDecalsDraw: Bool {
        decalsDraw && effects.decalBatches.contains(where: \.projected)
    }

    /// The flat decals, one instanced six-vertex draw per texture. A projected batch
    /// draws flat here too when the frame has no depth copy. Skipped in a debug view,
    /// which shows the surface under it.
    func encodeDecals(state: inout ScenePassState) {
        effects.lastDecalDraws = 0
        guard decalsDraw else { return }
        state.encoder.setRenderPipelineState(effects.decalPipeline)
        state.encoder.setDepthStencilState(effects.depthState)
        state.encoder.setDepthBias(-1, slopeScale: -1, clamp: 0)
        state.encoder.setCullMode(.back)
        encodeDecalBatches(vertexCount: 6, state: &state) {
            !$0.projected || !waterDepth.copies
        }
        state.encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        state.encoder.setDepthStencilState(depthState)
    }

    /// The projected decals, one 36-vertex box per decal, after the depth split.
    func encodeProjectedDecals(state: inout ScenePassState) {
        guard projectedDecalsDraw, waterDepth.copies else { return }
        state.encoder.setRenderPipelineState(effects.projectedDecalPipeline)
        state.encoder.setDepthStencilState(effects.projectedDecalDepthState)
        state.encoder.setStencilReferenceValue(MaterialDepthStates.skinStencilBit)
        state.encoder.setCullMode(.none)
        encodeDecalBatches(vertexCount: 36, state: &state, \.projected)
        state.encoder.setDepthStencilState(depthState)
    }

    private func encodeDecalBatches(
        vertexCount: Int,
        state: inout ScenePassState,
        _ include: (DecalBatch) -> Bool
    ) {
        guard let buffer = effects.decalBuffer else { return }
        var first = 0
        for batch in effects.decalBatches {
            defer { first += batch.instances.count }
            guard include(batch) else { continue }
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
                vertexCount: vertexCount,
                instanceCount: batch.instances.count
            )
            state.stats.drawCalls += 1
            state.stats.drawnInstances += batch.instances.count
            effects.lastDecalDraws += batch.instances.count
        }
    }
}

extension EffectLayer {
    var decalAllocations: [MTLAllocation] {
        (decalBuffer.map { [$0] } ?? []) + decalBatches.map(\.texture)
    }

    var particleAllocations: [MTLAllocation] {
        particles.flatMap(\.residencyAllocations)
    }
}
