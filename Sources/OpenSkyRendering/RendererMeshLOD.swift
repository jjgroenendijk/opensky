// Detail levels of `BSLODTriShape` meshes: each visible instance picks a level by its
// distance from the camera, the transforms are written grouped by level, and each level
// draws its own share of the index list. A level change cross-fades over one second.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// The finer and the coarser level of a running change: (0, 1), (0, 2), or (1, 2).
enum MeshLODLevelPair {
    static let count = 3

    static func index(finer: Int, coarser: Int) -> Int {
        finer + coarser - 1
    }

    static func levels(at index: Int) -> (finer: Int, coarser: Int) {
        index == 2 ? (1, 2) : (0, index + 1)
    }
}

extension Renderer {
    /// The group's visible transforms, full detail first; nil when none survive.
    func writeVisibleLevels(
        of group: DrawGroup,
        state: inout ScenePassState
    ) -> VisibleInstances? {
        var levels: [[InstanceTransform]] = [[], [], []]
        var fading: [[InstanceTransform]] = Array(repeating: [], count: MeshLODLevelPair.count)
        let viewer = frameInput.view.position
        for placed in group.instances {
            guard let transform = visibleTransform(of: placed, state: &state) else { continue }
            let origin = transform.modelMatrix.columns.3
            let position = SIMD3(origin.x, origin.y, origin.z)
            let fade = meshLODFade(
                formID: placed.referenceFormID, position: position,
                target: meshLODDistances.level(distance: simd_distance(position, viewer))
            )
            levels[fade.drawnLevel].append(transform)
            if let change = fade.fading {
                var copy = transform
                copy.grassParameters.w = max(copy.grassParameters.w, change.dissolve)
                fading[MeshLODLevelPair.index(finer: change.finer, coarser: fade.drawnLevel)]
                    .append(copy)
            }
        }
        let written = levels.reduce(0) { $0 + $1.count }
        guard written > 0 else { return nil }
        // The ring holds the scene's instances once; a change that does not fit pops.
        let extra = fading.reduce(0) { $0 + $1.count }
        if state.instanceCursor + written + extra > instanceSlotCapacity {
            fading = Array(repeating: [], count: MeshLODLevelPair.count)
        }
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = state.slot * instanceSlotCapacity + state.instanceCursor
        var cursor = base
        for level in levels + fading {
            level.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                instanceTransformBuffer.contents().advanced(by: cursor * stride)
                    .copyMemory(from: source, byteCount: bytes.count)
            }
            cursor += level.count
        }
        state.instanceCursor = cursor - state.slot * instanceSlotCapacity
        state.stats.drawnInstances += written
        return .levels(
            counts: levels.map(\.count), fading: fading.map(\.count),
            address: instanceTransformBuffer.gpuAddress + UInt64(base * stride)
        )
    }

    private func meshLODFade(formID: UInt32, position: SIMD3<Float>, target: Int) -> MeshLODFade {
        let key = FadeTimers<MeshLODFade>.Key(
            formID: formID, place: SIMD3<Int32>(position.rounded(.down))
        )
        let fade = fadeTimers.meshLOD.state(
            for: key, forgetAfter: MeshLODFade.unseenFramesToSnap
        ) { state, seconds in
            state?.stepped(toward: target, seconds: seconds) ?? MeshLODFade(level: target)
        }
        return fade ?? MeshLODFade(level: target)
    }

    /// One draw per non-empty level, each with that level's index count, then one draw per
    /// running change with only the finer level's extra triangles.
    func drawVisible(_ mesh: RenderMesh, _ visible: VisibleInstances, state: ScenePassState) {
        guard
            case let .levels(counts, fading, address) = visible,
            mesh.lodIndexCounts.count == counts.count
        else {
            state.encoder.drawInstances(of: mesh, visible)
            return
        }
        let stride = UInt64(MemoryLayout<InstanceTransform>.stride)
        var first: UInt64 = 0
        for (level, count) in counts.enumerated() where count > 0 {
            draw(
                mesh, indices: 0 ..< mesh.lodIndexCounts[level], instances: count,
                at: address + first * stride, encoder: state.encoder
            )
            first += UInt64(count)
        }
        for (pair, count) in fading.enumerated() where count > 0 {
            let levels = MeshLODLevelPair.levels(at: pair)
            let extra = mesh.lodIndexCounts[levels.coarser] ..< mesh.lodIndexCounts[levels.finer]
            if !extra.isEmpty {
                draw(
                    mesh, indices: extra, instances: count,
                    at: address + first * stride, encoder: state.encoder
                )
            }
            first += UInt64(count)
        }
    }

    private func draw(
        _ mesh: RenderMesh,
        indices: Range<Int>,
        instances: Int,
        at address: UInt64,
        encoder: any MTL4RenderCommandEncoder
    ) {
        argumentTable.setAddress(address, index: BufferIndex.instanceTransforms.rawValue)
        let offset = indices.lowerBound * MemoryLayout<UInt16>.stride
        encoder.drawIndexedPrimitives(
            primitiveType: .triangle,
            indexCount: indices.count,
            indexType: .uint16,
            indexBuffer: mesh.indexBuffer.gpuAddress + UInt64(offset),
            indexBufferLength: mesh.indexBuffer.length - offset,
            instanceCount: instances
        )
    }
}
