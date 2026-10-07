// Mesh-shader grass: the meshlets of each grass mesh, the pipeline that culls and draws
// them, and the counts the panel shows. See docs/rendering/mesh-shader-grass.md.

import Metal
import MetalKit
import OpenSkyShaderTypes

nonisolated public enum MeshShaderSupport {
    /// Why `device` cannot run object and mesh shaders; nil when it can.
    public static func unsupportedReason(_ device: MTLDevice?) -> String? {
        guard let device, device.supportsFamily(.apple7) || device.supportsFamily(.mac2) else {
            return "This GPU has no mesh shaders"
        }
        return nil
    }
}

/// One grass mesh split into meshlets, in three GPU buffers.
final class GrassMeshlets {
    /// Held so its address, the cache key, cannot go to another mesh while cached.
    let mesh: RenderMesh
    let bounds: MTLBuffer
    let vertexIndices: MTLBuffer
    let triangles: MTLBuffer
    let count: Int

    var allocations: [MTLAllocation] {
        [bounds, vertexIndices, triangles]
    }

    /// Nil when the mesh has no triangle or a buffer cannot be made.
    init?(mesh: RenderMesh, device: MTLDevice) {
        let built = MeshletBuilder.build(
            indices: mesh.indexArray(), positions: mesh.positionArray()
        )
        guard !built.meshlets.isEmpty else { return nil }
        let records = built.meshlets.map { meshlet in
            MeshletBounds(
                centerRadius: SIMD4(meshlet.center, meshlet.radius),
                coneAxisCutoff: SIMD4(meshlet.coneAxis, meshlet.coneCutoff),
                vertexOffset: meshlet.vertexOffset, vertexCount: meshlet.vertexCount,
                triangleOffset: meshlet.triangleOffset, triangleCount: meshlet.triangleCount
            )
        }
        func buffer(_ values: [some Any], _ label: String) -> MTLBuffer? {
            let made = values.withUnsafeBytes { bytes in
                bytes.baseAddress.flatMap {
                    device.makeBuffer(
                        bytes: $0, length: max(bytes.count, 4), options: .storageModeShared
                    )
                }
            }
            made?.label = label
            return made
        }
        guard
            let bounds = buffer(records, "GrassMeshlets"),
            let vertexIndices = buffer(built.vertexIndices, "GrassMeshletVertices"),
            let triangles = buffer(built.triangleIndices, "GrassMeshletTriangles")
        else { return nil }
        self.mesh = mesh
        self.bounds = bounds
        self.vertexIndices = vertexIndices
        self.triangles = triangles
        count = built.meshlets.count
    }
}

/// The renderer's mesh-shader grass switch, pipeline, and meshlet cache.
public struct MeshShaderGrassState {
    /// Off by default: on the M1 it measured no faster than the classic path.
    public var enabled = false
    /// What the pipeline is built from when the path is first used.
    let library: MTLLibrary
    let colorFormat: MTLPixelFormat
    let sampleCount: Int
    var pipeline: MTLRenderPipelineState?
    /// Set when the pipeline failed to build; the classic path draws instead.
    var pipelineFailure: String?
    /// Keyed by the grass mesh; dropped with the scene that owned it.
    var meshlets: [ObjectIdentifier: GrassMeshlets] = [:]
    /// Two counters per frame slot, read back once the slot's frame finished.
    var counters: MTLBuffer?
    /// One `GrassMeshUniforms` per grass group per frame slot.
    var uniforms: MTLBuffer?
    var uniformCapacity = 0
    /// The last counts read back, a few frames late.
    public internal(set) var lastCounts = MeshletCounts()
    /// What the last frame sent to the object stage.
    public internal(set) var submitted = MeshletCounts()

    init(library: MTLLibrary, view: MTKView) {
        self.library = library
        colorFormat = view.colorPixelFormat
        sampleCount = view.sampleCount
    }
}

/// Meshlet counts of one frame.
nonisolated public struct MeshletCounts: Equatable, Sendable {
    /// Meshlets the object stage tested.
    public var tested = 0
    /// Meshlets the mesh stage drew.
    public var drawn = 0
    /// Grass meshes split into meshlets.
    public var meshes = 0

    public init(tested: Int = 0, drawn: Int = 0, meshes: Int = 0) {
        self.tested = tested
        self.drawn = drawn
        self.meshes = meshes
    }
}

/// What the Rendering Performance panel shows for mesh-shader grass.
nonisolated public struct MeshShaderGrassStatus: Equatable, Sendable {
    public var enabled = false
    /// Why this GPU or this run cannot use it; nil when it can.
    public var unavailableReason: String?
    /// Counts the GPU wrote, a few frames late.
    public var counts = MeshletCounts()

    public init(
        enabled: Bool = false, unavailableReason: String? = nil, counts: MeshletCounts = .init()
    ) {
        self.enabled = enabled
        self.unavailableReason = unavailableReason
        self.counts = counts
    }
}

nonisolated extension RenderPerformanceReadout {
    public static func meshShaderGrassText(_ status: MeshShaderGrassStatus) -> String {
        if let reason = status.unavailableReason {
            return "Grass path: classic\nUnavailable: \(reason)"
        }
        guard status.enabled else {
            return "Grass path: classic"
        }
        let counts = status.counts
        return """
        Grass path: mesh shader
        Meshes: \(counts.meshes)  Meshlets tested: \(counts.tested)
        Drawn: \(counts.drawn)  Culled: \(max(counts.tested - counts.drawn, 0))
        """
    }
}

nonisolated extension RenderMesh {
    /// The uint16 index list, read back from the shared index buffer.
    func indexArray() -> [UInt16] {
        guard indexBuffer.storageMode == .shared else { return [] }
        let count = min(indexCount, indexBuffer.length / MemoryLayout<UInt16>.stride)
        let base = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: count)
        return Array(UnsafeBufferPointer(start: base, count: count))
    }

    /// Vertex positions, read back from the shared interleaved vertex buffer.
    func positionArray() -> [SIMD3<Float>] {
        guard vertexBuffer.storageMode == .shared else { return [] }
        let stride = StaticVertexLayout.stride
        let count = min(vertexCount, vertexBuffer.length / stride)
        let base = vertexBuffer.contents()
        return (0 ..< count).map { index in
            let floats = base.advanced(by: index * stride + StaticVertexLayout.positionOffset)
            return SIMD3(
                floats.load(as: Float.self),
                floats.load(fromByteOffset: 4, as: Float.self),
                floats.load(fromByteOffset: 8, as: Float.self)
            )
        }
    }
}
