// Detail levels of `BSLODTriShape` meshes: each visible instance picks a level by its
// distance from the camera, the transforms are written grouped by level, and each level
// draws its own share of the index list.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// The group's visible transforms, full detail first; nil when none survive.
    func writeVisibleLevels(
        of group: DrawGroup,
        state: inout ScenePassState
    ) -> VisibleInstances? {
        var levels: [[InstanceTransform]] = [[], [], []]
        let viewer = frameInput.view.position
        for placed in group.instances {
            guard let transform = visibleTransform(of: placed, state: &state) else { continue }
            let origin = transform.modelMatrix.columns.3
            let level = meshLODDistances.level(
                distance: simd_distance(SIMD3(origin.x, origin.y, origin.z), viewer)
            )
            levels[level].append(transform)
        }
        let written = levels.reduce(0) { $0 + $1.count }
        guard written > 0 else { return nil }
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = state.slot * instanceSlotCapacity + state.instanceCursor
        var cursor = base
        for level in levels {
            level.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                instanceTransformBuffer.contents().advanced(by: cursor * stride)
                    .copyMemory(from: source, byteCount: bytes.count)
            }
            cursor += level.count
        }
        state.instanceCursor += written
        state.stats.drawnInstances += written
        return .levels(
            counts: levels.map(\.count),
            address: instanceTransformBuffer.gpuAddress + UInt64(base * stride)
        )
    }

    /// One draw per non-empty level, each with that level's index count.
    func drawVisible(_ mesh: RenderMesh, _ visible: VisibleInstances, state: ScenePassState) {
        guard
            case let .levels(counts, address) = visible,
            mesh.lodIndexCounts.count == counts.count
        else {
            state.encoder.drawInstances(of: mesh, visible)
            return
        }
        let stride = UInt64(MemoryLayout<InstanceTransform>.stride)
        var first: UInt64 = 0
        for (level, count) in counts.enumerated() where count > 0 {
            argumentTable.setAddress(
                address + first * stride, index: BufferIndex.instanceTransforms.rawValue
            )
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: mesh.lodIndexCounts[level],
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer.gpuAddress,
                indexBufferLength: mesh.indexBuffer.length,
                instanceCount: count
            )
            first += UInt64(count)
        }
    }
}
