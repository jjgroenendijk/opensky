// Draws a grass group with the object and mesh stages instead of an indexed instanced
// draw. The object stage culls meshlets on the GPU. See docs/rendering/mesh-shader-grass.md.

import Metal
import OpenSkyShaderTypes
import simd

extension Renderer {
    static let meshGrassUniformStride = (MemoryLayout<GrassMeshUniforms>.size + 0xFF) & -0x100
    /// One SIMD group: the object shader compacts with SIMD prefix sums.
    static let meshGrassObjectThreads = 32
    static let meshGrassMeshThreads = 64

    public var meshShaderGrassEnabled: Bool {
        get { meshGrass.enabled }
        set {
            meshGrass.enabled = newValue
            meshGrass.pipelineFailure = nil
        }
    }

    /// Why the mesh path cannot draw; nil when it can.
    public var meshShaderGrassUnavailableReason: String? {
        MeshShaderSupport.unsupportedReason(device) ?? meshGrass.pipelineFailure
    }

    public var meshShaderGrassStatus: MeshShaderGrassStatus {
        MeshShaderGrassStatus(
            enabled: meshGrass.enabled,
            unavailableReason: meshShaderGrassUnavailableReason,
            counts: meshGrass.lastCounts
        )
    }

    /// Debug views keep the classic path, which has their pipelines.
    public var drawsGrassWithMeshShaders: Bool {
        meshGrass.enabled && meshShaderGrassUnavailableReason == nil && !isRenderDebugActive
    }

    /// Reads the counters this slot's last frame wrote, then clears them for this frame.
    func beginMeshGrassFrame(slot: Int, groupCount: Int) {
        meshGrass.submitted = MeshletCounts()
        guard
            drawsGrassWithMeshShaders, prepareMeshGrassBuffers(groupCount: groupCount),
            let counters = meshGrass.counters
        else { return }
        let values = counters.contents().bindMemory(
            to: UInt32.self, capacity: 2 * Self.maxFramesInFlight
        )
        meshGrass.lastCounts = MeshletCounts(
            tested: Int(values[slot * 2]), drawn: Int(values[slot * 2 + 1]),
            meshes: meshGrass.meshlets.count
        )
        values[slot * 2] = 0
        values[slot * 2 + 1] = 0
    }

    /// Encodes `group` through the mesh pipeline; false leaves it to the classic draw.
    func encodeMeshGrassGroup(
        _ group: GrassDrawGroup, instanceCount: Int, groupIndex: Int, state: ScenePassState
    ) -> Bool {
        guard
            drawsGrassWithMeshShaders,
            let pipeline = meshGrassPipeline(),
            let meshlets = grassMeshlets(for: group.mesh),
            let uniforms = writeMeshGrassUniforms(
                meshlets: meshlets, group: group, instanceCount: instanceCount, state: state,
                groupIndex: groupIndex
            )
        else { return false }
        state.encoder.setRenderPipelineState(pipeline)
        argumentTable.setAddress(uniforms, index: BufferIndex.grassMeshUniforms.rawValue)
        argumentTable.setAddress(meshlets.bounds.gpuAddress, index: BufferIndex.meshlets.rawValue)
        argumentTable.setAddress(
            meshlets.vertexIndices.gpuAddress, index: BufferIndex.meshletVertices.rawValue
        )
        argumentTable.setAddress(
            meshlets.triangles.gpuAddress, index: BufferIndex.meshletTriangles.rawValue
        )
        if let counters = meshGrass.counters {
            argumentTable.setAddress(
                counters.gpuAddress, index: BufferIndex.meshletCounters.rawValue
            )
        }
        let pairs = instanceCount * meshlets.count
        state.encoder.drawMeshThreadgroups(
            threadgroupsPerGrid: MTLSize(
                width: (pairs + Self.meshGrassObjectThreads - 1) / Self.meshGrassObjectThreads,
                height: 1, depth: 1
            ),
            threadsPerObjectThreadgroup: MTLSize(
                width: Self.meshGrassObjectThreads, height: 1, depth: 1
            ),
            threadsPerMeshThreadgroup: MTLSize(
                width: Self.meshGrassMeshThreads,
                height: 1,
                depth: 1
            )
        )
        meshGrass.submitted.tested += instanceCount * meshlets.count
        return true
    }

    private func writeMeshGrassUniforms(
        meshlets: GrassMeshlets, group: GrassDrawGroup, instanceCount: Int,
        state: ScenePassState, groupIndex: Int
    ) -> UInt64? {
        let (frustum, slot) = (state.frustum, state.slot)
        guard let buffer = meshGrass.uniforms, groupIndex < meshGrass.uniformCapacity else {
            return nil
        }
        var uniforms = GrassMeshUniforms()
        withUnsafeMutableBytes(of: &uniforms.frustumPlanes) { planes in
            let values = [
                frustum.left, frustum.right, frustum.bottom, frustum.top, frustum.near, frustum.far
            ]
            for (index, plane) in values.enumerated() {
                planes.storeBytes(
                    of: plane, toByteOffset: index * MemoryLayout<SIMD4<Float>>.stride,
                    as: SIMD4<Float>.self
                )
            }
        }
        uniforms.meshletCount = UInt32(meshlets.count)
        uniforms.instanceCount = UInt32(instanceCount)
        uniforms.cullBackfaces = group.material.doubleSided ? 0 : 1
        uniforms.swayPadding = GrassRenderPolicy.maximumSwayDisplacement
        uniforms.counterBase = UInt32(slot * 2)
        uniforms.vertexCount = UInt32(meshlets.mesh.vertexCount)
        let offset = Self.meshGrassUniformStride
            * (slot * meshGrass.uniformCapacity + groupIndex)
        buffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<GrassMeshUniforms>.size)
        return buffer.gpuAddress + UInt64(offset)
    }

    /// The uniform ring (one entry per grass group per slot) and the counters.
    private func prepareMeshGrassBuffers(groupCount: Int) -> Bool {
        if meshGrass.counters == nil {
            meshGrass.counters = makeMeshGrassBuffer(
                length: 2 * Self.maxFramesInFlight * MemoryLayout<UInt32>.stride,
                label: "GrassMeshletCounters"
            )
            meshGrass.counters?.contents().initializeMemory(
                as: UInt8.self, repeating: 0, count: 2 * Self.maxFramesInFlight * 4
            )
        }
        if groupCount > meshGrass.uniformCapacity {
            if let old = meshGrass.uniforms {
                retireAllocations([old])
            }
            let capacity = max(groupCount, 2 * meshGrass.uniformCapacity, 16)
            meshGrass.uniforms = makeMeshGrassBuffer(
                length: Self.meshGrassUniformStride * capacity * Self.maxFramesInFlight,
                label: "GrassMeshUniforms"
            )
            meshGrass.uniformCapacity = meshGrass.uniforms == nil ? 0 : capacity
        }
        return meshGrass.counters != nil && meshGrass.uniforms != nil
    }

    private func makeMeshGrassBuffer(length: Int, label: String) -> MTLBuffer? {
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            return nil
        }
        buffer.label = label
        residencySet.addAllocation(buffer)
        residencySet.commit()
        return buffer
    }

    private func grassMeshlets(for mesh: RenderMesh) -> GrassMeshlets? {
        let key = ObjectIdentifier(mesh)
        if let cached = meshGrass.meshlets[key] {
            return cached
        }
        guard let built = GrassMeshlets(mesh: mesh, device: device) else { return nil }
        meshGrass.meshlets[key] = built
        residencySet.addAllocations(built.allocations)
        residencySet.commit()
        return built
    }

    /// Drops the meshlets of meshes the new scene no longer draws.
    func pruneGrassMeshlets(keeping groups: [GrassDrawGroup]) {
        let live = Set(groups.map { ObjectIdentifier($0.mesh) })
        let stale = meshGrass.meshlets.filter { !live.contains($0.key) }
        guard !stale.isEmpty else { return }
        retireAllocations(stale.values.flatMap(\.allocations))
        for key in stale.keys {
            meshGrass.meshlets[key] = nil
        }
    }

    /// Built on first use, so a run that never turns the path on compiles nothing.
    private func meshGrassPipeline() -> MTLRenderPipelineState? {
        if let pipeline = meshGrass.pipeline {
            return pipeline
        }
        do {
            let pipeline = try Self.makeMeshGrassPipeline(
                library: meshGrass.library, compiler: pipelineCache,
                colorFormat: meshGrass.colorFormat, sampleCount: meshGrass.sampleCount
            )
            meshGrass.pipeline = pipeline
            return pipeline
        } catch {
            meshGrass.pipelineFailure = "The mesh pipeline failed to build: \(error)"
            return nil
        }
    }
}
