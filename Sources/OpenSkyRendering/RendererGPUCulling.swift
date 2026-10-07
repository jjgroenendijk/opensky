// Drives GPU culling each frame: builds the scene's cull buffers when the scene
// changes, and encodes the cull dispatches before the shadow and scene passes.

import Metal
import simd

/// The renderer's GPU culling state.
public struct GPUCullState {
    let resources: GPUCullingResources
    /// Off draws every group through the CPU path.
    public var enabled = false
    var scene: GPUCullScene?
    /// False after a scene swap, until `scene` is rebuilt.
    var isCurrent = false
    /// This frame's cull, when the GPU path draws.
    var active: GPUCullScene?
    /// The GPU path's counts, a few frames old because they are read after the GPU ran.
    public internal(set) var lastCounts = CullCounts()

    init(resources: GPUCullingResources) {
        self.resources = resources
    }
}

extension Renderer {
    public var gpuCullingEnabled: Bool {
        get { gpuCull.enabled }
        set { gpuCull.enabled = newValue }
    }

    public var lastGPUCullCounts: CullCounts {
        gpuCull.lastCounts
    }

    /// Culls the camera view and each cascade on the GPU. Leaves the CPU path drawing
    /// when culling is off or the scene has nothing to cull.
    func encodeGPUCulling(slot: Int, viewProjections: [float4x4]) {
        gpuCull.active = nil
        guard gpuCull.enabled, let cullScene = currentGPUCullScene() else {
            gpuCull.lastCounts = CullCounts()
            return
        }
        gpuCull.lastCounts = cullScene.counts(slot: slot)
        guard
            cullScene.encode(
                frustums: viewProjections.map(Frustum.init(viewProjection:)),
                slot: slot,
                resources: gpuCull.resources,
                commandBuffer: commandBuffer
            )
        else { return }
        gpuCull.active = cullScene
    }

    /// The counts of the last encoded frame, for a caller that waited for its GPU work.
    public func lastFrameGPUCullCounts() -> CullCounts {
        gpuCull.scene?.counts(slot: (frameIndex - 1) % Self.maxFramesInFlight) ?? CullCounts()
    }

    private func currentGPUCullScene() -> GPUCullScene? {
        guard !gpuCull.isCurrent else { return gpuCull.scene }
        gpuCull.isCurrent = true
        if let old = gpuCull.scene {
            retireAllocations(old.allocations)
        }
        // A failed allocation leaves the CPU path drawing this scene.
        gpuCull.scene = try? GPUCullScene(
            scene: scene, device: device, framesInFlight: Self.maxFramesInFlight
        )
        if let fresh = gpuCull.scene {
            residencySet.addAllocations(fresh.allocations)
            residencySet.commit()
        }
        return gpuCull.scene
    }
}

/// Where a group's surviving instances are, and who counted them.
enum VisibleInstances {
    /// The CPU wrote `count` transforms at `address`.
    case packed(count: Int, address: UInt64)
    /// The cull pass wrote them; the count sits in the indirect arguments.
    case indirect(arguments: UInt64, address: UInt64)

    var address: UInt64 {
        switch self {
        case let .packed(_, address), let .indirect(_, address): address
        }
    }
}

/// How one view draws a scene group this frame.
enum GPUGroupVisibility {
    /// The CPU path culls and draws it.
    case cpu
    /// Its bounds miss the view, so no draw is encoded.
    case skipped
    case drawn(VisibleInstances)
}

extension Renderer {
    /// `view` 0 is the camera, `1 + i` shadow cascade `i`.
    func gpuVisibility(
        of index: Int,
        in list: GPUCullList?,
        view: Int,
        slot: Int,
        frustum: Frustum
    ) -> GPUGroupVisibility {
        guard
            let list,
            let cull = gpuCull.active,
            let group = cull.group(list, at: index)
        else { return .cpu }
        cull.count(group: group, view: view, slot: slot)
        if let bounds = cull.groups[group].bounds, !frustum.intersects(bounds) {
            return .skipped
        }
        return .drawn(.indirect(
            arguments: cull.argumentAddress(group: group, view: view, slot: slot),
            address: cull.outputAddress(group: group, view: view, slot: slot)
        ))
    }
}

extension MTL4RenderCommandEncoder {
    func drawInstances(of mesh: RenderMesh, _ visible: VisibleInstances) {
        switch visible {
        case let .packed(count, _):
            drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer.gpuAddress,
                indexBufferLength: mesh.indexBuffer.length,
                instanceCount: count
            )
        case let .indirect(arguments, _):
            drawIndexedPrimitives(
                primitiveType: .triangle,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer.gpuAddress,
                indexBufferLength: mesh.indexBuffer.length,
                indirectBuffer: arguments
            )
        }
    }
}
