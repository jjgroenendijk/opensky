// The acceleration structures the ray-traced shadows trace against: one primitive
// structure per mesh, and one instance structure that places them in the world.
// See docs/rendering/ray-traced-shadows.md.

import Metal
import simd

/// One mesh placed in the world.
struct RayTracedInstance {
    let mesh: RenderMesh
    let transform: float4x4
}

/// The size of the built structures.
nonisolated public struct RayTracedShadowStats: Equatable, Sendable {
    public var meshes = 0
    public var instances = 0
    public var bytes = 0

    public init() {}
}

final class RayTracedShadowScene {
    let instanceStructure: MTLAccelerationStructure
    let allocations: [MTLAllocation]
    let stats: RayTracedShadowStats

    private init(
        instanceStructure: MTLAccelerationStructure, allocations: [MTLAllocation],
        stats: RayTracedShadowStats
    ) {
        self.instanceStructure = instanceStructure
        self.allocations = allocations
        self.stats = stats
    }

    /// Encodes the builds into `encoder`, which must end with a barrier before the
    /// passes that trace. Nil when there is nothing to trace or memory runs out.
    static func build(
        _ instances: [RayTracedInstance], device: MTLDevice,
        encoder: MTL4ComputeCommandEncoder
    ) -> RayTracedShadowScene? {
        var builder = Builder(device: device)
        var meshStructures: [ObjectIdentifier: MTLAccelerationStructure] = [:]
        for instance in instances where meshStructures[ObjectIdentifier(instance.mesh)] == nil {
            guard let structure = builder.add(primitive: Self.descriptor(for: instance.mesh)) else {
                return nil
            }
            meshStructures[ObjectIdentifier(instance.mesh)] = structure
        }
        guard
            !instances.isEmpty,
            let instanceBuffer = Self.instanceBuffer(
                instances,
                structures: meshStructures,
                device: device
            )
        else { return nil }
        let top = MTL4InstanceAccelerationStructureDescriptor()
        top.instanceDescriptorBuffer = MTL4BufferRangeMake(
            instanceBuffer.gpuAddress, UInt64(instanceBuffer.length)
        )
        top
            .instanceDescriptorStride =
            MemoryLayout<MTLIndirectAccelerationStructureInstanceDescriptor>.stride
        top.instanceCount = instances.count
        top.instanceDescriptorType = .indirect
        guard let instanceStructure = builder.add(instance: top) else { return nil }
        guard builder.encode(into: encoder) else { return nil }
        let structures = Array(meshStructures.values) + [instanceStructure]
        var stats = RayTracedShadowStats()
        stats.meshes = meshStructures.count
        stats.instances = instances.count
        stats.bytes = structures.reduce(instanceBuffer.length) { $0 + $1.size }
        return RayTracedShadowScene(
            instanceStructure: instanceStructure,
            allocations: structures + [instanceBuffer] + builder.scratchBuffers,
            stats: stats
        )
    }

    private static func descriptor(for mesh: RenderMesh)
        -> MTL4PrimitiveAccelerationStructureDescriptor
    {
        let geometry = MTL4AccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = MTL4BufferRangeMake(
            mesh.vertexBuffer.gpuAddress, UInt64(mesh.vertexBuffer.length)
        )
        geometry.vertexFormat = .float3
        geometry.vertexStride = StaticVertexLayout.stride
        geometry.indexBuffer = MTL4BufferRangeMake(
            mesh.indexBuffer.gpuAddress, UInt64(mesh.indexBuffer.length)
        )
        geometry.indexType = .uint16
        geometry.triangleCount = mesh.indexCount / 3
        geometry.opaque = true
        let descriptor = MTL4PrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        return descriptor
    }

    private static func instanceBuffer(
        _ instances: [RayTracedInstance],
        structures: [ObjectIdentifier: MTLAccelerationStructure], device: MTLDevice
    ) -> MTLBuffer? {
        let records = instances.compactMap { instance in
            structures[ObjectIdentifier(instance.mesh)].map { structure in
                var record = MTLIndirectAccelerationStructureInstanceDescriptor()
                record.transformationMatrix = Self.packed(instance.transform)
                record.options = [.opaque, .disableTriangleCulling]
                record.mask = 0xFF
                record.accelerationStructureID = structure.gpuResourceID
                return record
            }
        }
        let buffer = records.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap {
                device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared)
            }
        }
        buffer?.label = "Ray-traced shadow instances"
        return buffer
    }

    private static func packed(_ matrix: float4x4) -> MTLPackedFloat4x3 {
        func column(_ value: SIMD4<Float>) -> MTLPackedFloat3 {
            MTLPackedFloat3Make(value.x, value.y, value.z)
        }
        return MTLPackedFloat4x3(columns: (
            column(matrix.columns.0), column(matrix.columns.1),
            column(matrix.columns.2), column(matrix.columns.3)
        ))
    }
}

/// Collects builds, then encodes the mesh builds, a barrier, and the instance build.
private struct Builder {
    let device: MTLDevice
    private var primitives: [(MTLAccelerationStructure, MTL4AccelerationStructureDescriptor)] = []
    private var top: (MTLAccelerationStructure, MTL4AccelerationStructureDescriptor)?
    private(set) var scratchBuffers: [MTLBuffer] = []

    init(device: MTLDevice) {
        self.device = device
    }

    mutating func add(primitive descriptor: MTL4AccelerationStructureDescriptor)
        -> MTLAccelerationStructure?
    {
        guard let structure = make(descriptor) else { return nil }
        primitives.append((structure, descriptor))
        return structure
    }

    mutating func add(instance descriptor: MTL4AccelerationStructureDescriptor)
        -> MTLAccelerationStructure?
    {
        guard let structure = make(descriptor) else { return nil }
        top = (structure, descriptor)
        return structure
    }

    private func make(_ descriptor: MTL4AccelerationStructureDescriptor)
        -> MTLAccelerationStructure?
    {
        device.makeAccelerationStructure(
            size: device.accelerationStructureSizes(descriptor: descriptor)
                .accelerationStructureSize
        )
    }

    /// Each build gets its own scratch range, so the mesh builds may overlap.
    mutating func encode(into encoder: MTL4ComputeCommandEncoder) -> Bool {
        guard let top else { return false }
        let builds = primitives + [top]
        let sizes = builds
            .map { device.accelerationStructureSizes(descriptor: $0.1).buildScratchBufferSize }
        let aligned = sizes.map { ($0 + 255) & ~255 }
        guard
            let scratch = device.makeBuffer(
                length: max(aligned.reduce(0, +), 256), options: .storageModePrivate
            ) else { return false }
        scratch.label = "Ray-traced shadow scratch"
        scratchBuffers = [scratch]
        var offset = 0
        for (index, build) in builds.enumerated() {
            if index == primitives.count {
                encoder.barrier(
                    afterEncoderStages: .accelerationStructure,
                    beforeEncoderStages: .accelerationStructure, visibilityOptions: .device
                )
            }
            encoder.build(
                destinationAccelerationStructure: build.0, descriptor: build.1,
                scratchBuffer: MTL4BufferRangeMake(
                    scratch.gpuAddress + UInt64(offset), UInt64(sizes[index])
                )
            )
            offset += aligned[index]
        }
        return true
    }
}
