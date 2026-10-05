// A model's GPU buffers as raw bytes: per mesh the interleaved vertices, the
// indices, and the skin stream when skinned. Loading it skips the NIF parse
// and the flatten step. Materials are small and are not part of the payload.

import Foundation
import Metal
import OpenSkyFormatsCore

nonisolated public struct ReadyMeshPayload: Sendable {
    public let packed: PackedBlobs

    /// Packs the buffers `RenderMesh` would build for `model`, in the same order.
    public init(model: Model) {
        packed = PackedBlobs(model.meshes.flatMap { mesh in
            var blobs = [
                PackedBlobs.blob(StaticVertexLayout.interleave(mesh)),
                PackedBlobs.blob(mesh.indices)
            ]
            if let skinning = mesh.skinning {
                blobs.append(PackedBlobs.blob(
                    zip(skinning.weights, skinning.boneIndices).map(SkinVertex.init)
                ))
            }
            return blobs
        })
    }

    /// The bytes of every GPU buffer of `model`, in payload order, to check a load.
    public static func bufferBytes(of model: RenderModel) -> [Data] {
        model.meshes.flatMap { mesh in
            [mesh.vertexBuffer, mesh.indexBuffer, mesh.skinningBuffer].compactMap { buffer in
                buffer.map { Data(bytes: $0.contents(), count: $0.length) }
            }
        }
    }

    /// Empty shared buffers sized for each range, for the MTLIO path.
    public func makeEmptyBuffers(device: MTLDevice) throws -> [MTLBuffer] {
        try packed.ranges.map { range in
            guard
                let buffer = device.makeBuffer(length: range.length, options: .storageModeShared)
            else { throw RenderMeshError.bufferAllocationFailed }
            return buffer
        }
    }

    /// The CPU path: one buffer per range, copied from `source`.
    public func upload(device: MTLDevice, source: Data) throws -> [MTLBuffer] {
        try source.withUnsafeBytes { raw in
            try packed.ranges.map { range in
                guard
                    let base = raw.baseAddress,
                    range.offset + range.length <= raw.count,
                    let buffer = device.makeBuffer(
                        bytes: base + range.offset,
                        length: range.length,
                        options: .storageModeShared
                    )
                else { throw RenderMeshError.bufferAllocationFailed }
                return buffer
            }
        }
    }
}
