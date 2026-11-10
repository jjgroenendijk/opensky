// GPU frustum culling for the scene's static draw groups. One compute pass tests each
// instance once per view and counts the survivors into the group's indirect draw, so
// the CPU encodes one draw per group and never touches an instance. A group that holds
// a reference physics moves stays on the CPU path. See docs/rendering/gpu-culling.md.

public import Metal
public import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources
public import OpenSkyShaderTypes
import simd

/// Instances one culling path kept and dropped in a frame.
nonisolated public struct CullCounts: Equatable, Sendable {
    public var cameraVisible = 0
    public var cameraCulled = 0
    /// Summed over the shadow cascades.
    public var shadowVisible = 0
    public var shadowCulled = 0
    /// Camera instances in a room the camera cannot see, inside `cameraCulled`.
    public var cameraRoomCulled = 0

    public init(
        cameraVisible: Int = 0,
        cameraCulled: Int = 0,
        shadowVisible: Int = 0,
        shadowCulled: Int = 0,
        cameraRoomCulled: Int = 0
    ) {
        self.cameraVisible = cameraVisible
        self.cameraCulled = cameraCulled
        self.shadowVisible = shadowVisible
        self.shadowCulled = shadowCulled
        self.cameraRoomCulled = cameraRoomCulled
    }
}

/// The cull kernel and its binding table, built once with the renderer.
struct GPUCullingResources {
    let pipeline: any MTLComputePipelineState
    let argumentTable: any MTL4ArgumentTable

    init(library: any MTLLibrary, compiler: PipelineCache) throws {
        let function = MTL4LibraryFunctionDescriptor()
        function.name = "cullInstances"
        function.library = library
        let descriptor = MTL4ComputePipelineDescriptor()
        descriptor.computeFunctionDescriptor = function
        descriptor.label = "Cull Instances"
        pipeline = try compiler.makeComputePipelineState(descriptor: descriptor)
        let table = MTL4ArgumentTableDescriptor()
        table.maxBufferBindCount = CullBufferIndex.fadeStates.rawValue + 1
        argumentTable = try compiler.device.makeArgumentTable(descriptor: table)
    }
}

/// One draw group the GPU culls.
struct GPUCullGroup {
    let firstInstance: Int
    let instanceCount: Int
    /// Union of the instance bounds; nil when an instance has none.
    let bounds: ModelBounds?
}

/// Which scene list a draw group index refers to.
enum GPUCullList {
    case opaque
    case alphaTested
}

/// One scene's cull inputs and per-frame outputs, built when the scene changes.
public final class GPUCullScene {
    /// Views per frame: the camera, then each shadow cascade.
    static let viewCount = 1 + ShadowConstant.cascadeCount.rawValue
    static let argumentStride = MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride
    static let transformStride = MemoryLayout<InstanceTransform>.stride

    let instances: any MTLBuffer
    let parameters: any MTLBuffer
    let output: any MTLBuffer
    let arguments: any MTLBuffer
    /// Per frame slot: the room-culled counter, then `roomWordCount` bitset words.
    let rooms: any MTLBuffer
    let roomWordCount: Int
    /// One fade state per instance, shared by every frame slot: the GPU runs frames in order.
    let fadeStates: any MTLBuffer
    /// The reference fade the next `encode` writes into each view's parameters.
    var fade = CullFade(distances: .off, viewer: .zero, seconds: 0)
    let instanceCount: Int
    let groups: [GPUCullGroup]
    /// The GPU group of each `scene.opaque` group, nil for a CPU group.
    let opaqueGroups: [Int?]
    let alphaTestedGroups: [Int?]
    /// The reset value of each group's indirect arguments.
    private let argumentTemplate: [MTLDrawIndexedPrimitivesIndirectArguments]
    /// Groups each view counted, per frame slot, for the stats readback.
    private var countedGroups: [[[Int]]]

    var allocations: [any MTLAllocation] {
        [instances, parameters, output, arguments, rooms, fadeStates]
    }

    /// Nil when the scene has no group the GPU can cull.
    init?(scene: RenderScene, device: any MTLDevice, framesInFlight: Int) throws {
        var builder = GPUCullSceneBuilder()
        opaqueGroups = scene.opaque.map { builder.add($0) }
        alphaTestedGroups = scene.alphaTested.map { builder.add($0) }
        guard !builder.instances.isEmpty else { return nil }
        instanceCount = builder.instances.count
        groups = builder.groups
        argumentTemplate = builder.arguments
        countedGroups = Array(
            repeating: Array(repeating: [], count: Self.viewCount), count: framesInFlight
        )
        roomWordCount = scene.rooms.map { ($0.rooms.count + 31) / 32 } ?? 0
        rooms = try GPUFactory.makeUniformBuffer(
            device: device,
            length: MemoryLayout<UInt32>.stride * (1 + roomWordCount) * framesInFlight,
            label: "CullRooms"
        )
        let views = Self.viewCount * framesInFlight
        instances = try GPUFactory.makeUniformBuffer(
            device: device,
            length: MemoryLayout<CullInstance>.stride * instanceCount,
            label: "CullInstances"
        )
        parameters = try GPUFactory.makeUniformBuffer(
            device: device, length: MemoryLayout<CullParameters>.stride * views,
            label: "CullParameters"
        )
        output = try GPUFactory.makeUniformBuffer(
            device: device, length: Self.transformStride * instanceCount * views,
            label: "CulledInstanceTransforms"
        )
        arguments = try GPUFactory.makeUniformBuffer(
            device: device, length: Self.argumentStride * groups.count * views,
            label: "CullDrawArguments"
        )
        fadeStates = try GPUFactory.makeUniformBuffer(
            device: device, length: MemoryLayout<SIMD2<Float>>.stride * instanceCount,
            label: "CullFadeStates"
        )
        let unseen = [SIMD2<Float>](repeating: SIMD2(-1, 0), count: instanceCount)
        unseen.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            unsafe fadeStates.contents().copyMemory(from: base, byteCount: bytes.count)
        }
        let contents = unsafe instances.contents()
        builder.instances.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            unsafe contents.copyMemory(from: base, byteCount: bytes.count)
        }
    }

    func group(_ list: GPUCullList, at index: Int) -> Int? {
        let slots = list == .opaque ? opaqueGroups : alphaTestedGroups
        return index < slots.count ? slots[index] : nil
    }

    private func viewSlot(view: Int, slot: Int) -> Int {
        slot * Self.viewCount + view
    }

    /// Where the group's surviving transforms start for one view.
    func outputAddress(group: Int, view: Int, slot: Int) -> UInt64 {
        let first = viewSlot(view: view, slot: slot) * instanceCount + groups[group].firstInstance
        return output.gpuAddress + UInt64(first * Self.transformStride)
    }

    private func roomOffset(slot: Int) -> Int {
        MemoryLayout<UInt32>.stride * (1 + roomWordCount) * slot
    }

    func argumentAddress(group: Int, view: Int, slot: Int) -> UInt64 {
        let entry = viewSlot(view: view, slot: slot) * groups.count + group
        return arguments.gpuAddress + UInt64(entry * Self.argumentStride)
    }

    /// Records that a view drew or skipped the group this frame, so its instances count.
    func count(group: Int, view: Int, slot: Int) {
        countedGroups[slot][view].append(group)
    }

    /// The counts of the frame this slot last encoded. Valid only after that frame's GPU
    /// work completed.
    func counts(slot: Int) -> CullCounts {
        var counts = CullCounts()
        counts.cameraRoomCulled = unsafe Int(
            rooms.contents().advanced(by: roomOffset(slot: slot)).load(as: UInt32.self)
        )
        for view in 0 ..< Self.viewCount {
            for group in countedGroups[slot][view] {
                let visible = unsafe Int(arguments.contents()
                    .advanced(by: Int(argumentAddress(group: group, view: view, slot: slot)
                            - arguments.gpuAddress))
                    .load(as: MTLDrawIndexedPrimitivesIndirectArguments.self).instanceCount)
                let culled = groups[group].instanceCount - visible
                if view == 0 {
                    counts.cameraVisible += visible
                    counts.cameraCulled += culled
                } else {
                    counts.shadowVisible += visible
                    counts.shadowCulled += culled
                }
            }
        }
        return counts
    }

    /// Resets the slot's draw arguments and encodes one cull dispatch per view. Rooms
    /// cull only the camera view: a hidden room still casts shadows into a seen one.
    func encode(
        frustums: [Frustum],
        roomVisibility: RoomVisibility?,
        slot: Int,
        resources: GPUCullingResources,
        commandBuffer: any MTL4CommandBuffer
    ) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        countedGroups[slot] = Array(repeating: [], count: Self.viewCount)
        encoder.label = "GPU Culling"
        encoder.setComputePipelineState(resources.pipeline)
        encoder.setArgumentTable(resources.argumentTable)
        let table = resources.argumentTable
        table.setAddress(instances.gpuAddress, index: CullBufferIndex.instances.rawValue)
        table.setAddress(fadeStates.gpuAddress, index: CullBufferIndex.fadeStates.rawValue)
        let roomWords = writeRooms(roomVisibility, slot: slot)
        table.setAddress(
            rooms.gpuAddress + UInt64(roomOffset(slot: slot)), index: CullBufferIndex.rooms.rawValue
        )
        let width = CullConstant.threadgroupWidth.rawValue
        for (view, frustum) in frustums.enumerated() {
            let parameterAddress = writeParameters(
                frustum, roomWords: view == 0 ? roomWords : 0, view: view, slot: slot
            )
            resetArguments(view: view, slot: slot)
            table.setAddress(parameterAddress, index: CullBufferIndex.parameters.rawValue)
            table.setAddress(
                outputAddress(group: 0, view: view, slot: slot),
                index: CullBufferIndex.output.rawValue
            )
            table.setAddress(
                argumentAddress(group: 0, view: view, slot: slot),
                index: CullBufferIndex.arguments.rawValue
            )
            encoder.dispatchThreads(
                threadsPerGrid: MTLSize(width: instanceCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
            )
            if view == 0 {
                // The shadow views read the fades the camera view just stepped.
                encoder.barrier(
                    afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch,
                    visibilityOptions: .device
                )
            }
        }
        // The draws read the counts and transforms in their vertex stage.
        encoder.barrier(
            afterStages: .dispatch,
            beforeQueueStages: .vertex,
            visibilityOptions: .device
        )
        encoder.endEncoding()
        return true
    }

    /// Zeroes the slot's counter and writes the bitset; returns the words the kernel reads.
    private func writeRooms(_ visibility: RoomVisibility?, slot: Int) -> Int {
        let base = unsafe rooms.contents().advanced(by: roomOffset(slot: slot))
        unsafe base.storeBytes(of: UInt32(0), as: UInt32.self)
        guard let visibility, roomWordCount > 0, visibility.words.count == roomWordCount
        else { return 0 }
        visibility.words.withUnsafeBytes { bytes in
            guard let words = bytes.baseAddress else { return }
            unsafe base.advanced(by: MemoryLayout<UInt32>.stride).copyMemory(
                from: words, byteCount: bytes.count
            )
        }
        return roomWordCount
    }

    private func writeParameters(
        _ frustum: Frustum,
        roomWords: Int,
        view: Int,
        slot: Int
    ) -> UInt64 {
        var parameters = CullParameters(
            planes: (
                frustum.left, frustum.right, frustum.bottom,
                frustum.top, frustum.near, frustum.far
            ),
            fadeViewer: SIMD4(
                fade.viewer, fade.distances.isOn ? 1 : 0
            ),
            fadeScales: fade.distances.shaderScales,
            instanceCount: UInt32(instanceCount),
            roomWordCount: UInt32(roomWords),
            fadeSeconds: view == 0 ? fade.seconds : 0,
            advancesFades: view == 0 ? 1 : 0
        )
        let offset = viewSlot(view: view, slot: slot) * MemoryLayout<CullParameters>.stride
        unsafe self.parameters.contents().advanced(by: offset)
            .copyMemory(from: &parameters, byteCount: MemoryLayout<CullParameters>.size)
        return self.parameters.gpuAddress + UInt64(offset)
    }

    private func resetArguments(view: Int, slot: Int) {
        let offset = Int(argumentAddress(group: 0, view: view, slot: slot) - arguments.gpuAddress)
        argumentTemplate.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            unsafe arguments.contents().advanced(by: offset).copyMemory(
                from: base,
                byteCount: bytes.count
            )
        }
    }
}

/// Gathers the cull inputs of the groups the GPU can cull.
private struct GPUCullSceneBuilder {
    var instances: [CullInstance] = []
    var groups: [GPUCullGroup] = []
    var arguments: [MTLDrawIndexedPrimitivesIndirectArguments] = []

    /// Adds the group and returns its GPU index, or nil when it stays on the CPU.
    mutating func add(_ group: DrawGroup) -> Int? {
        guard
            !group.instances.isEmpty,
            // A LOD mesh picks its detail level per instance on the CPU.
            group.mesh.lodIndexCounts.isEmpty,
            // A region's emittance changes with the hour, so it is written every frame.
            group.instances.allSatisfy({ $0.referenceFormID == 0 && $0.emittance?.region == nil })
        else { return nil }
        let index = groups.count
        let first = instances.count
        var bounds = group.instances.first?.bounds
        for instance in group.instances {
            bounds = instance.bounds.flatMap { own in bounds.map { $0.union(own) } }
            instances.append(Self.cullInstance(instance, group: index, outputBase: first))
        }
        groups.append(GPUCullGroup(
            firstInstance: first, instanceCount: group.instances.count, bounds: bounds
        ))
        arguments.append(MTLDrawIndexedPrimitivesIndirectArguments(
            indexCount: UInt32(group.mesh.indexCount),
            instanceCount: 0, indexStart: 0, baseVertex: 0, baseInstance: 0
        ))
        return index
    }

    private static func cullInstance(
        _ instance: DrawInstance,
        group: Int,
        outputBase: Int
    ) -> CullInstance {
        let bounds = instance.bounds
        return CullInstance(
            transform: InstanceTransform(
                modelMatrix: instance.modelMatrix,
                normalMatrix: instance.normalMatrix,
                instanceColor: instance.instanceColor(regions: [:]),
                grassParameters: .zero
            ),
            boundsMin: SIMD4(bounds?.min ?? .zero, Float(instance.fadeCategory.rawValue)),
            boundsMax: SIMD4(bounds?.max ?? .zero, bounds == nil ? 0 : 1),
            group: UInt32(group),
            outputBase: UInt32(outputBase),
            room: instance.room,
            padding0: 0
        )
    }
}
