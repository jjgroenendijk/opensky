// A mesh's billboard node in cache bytes: a flag, then the pivot, the rotation, and the mode.

import OpenSkyFormatsCore
import simd

nonisolated extension ModelCacheCodec {
    static func encode(_ billboard: MeshBillboard?, into out: inout CachePayloadWriter) {
        out.bool(billboard != nil)
        guard let billboard else { return }
        out.value(billboard.pivot)
        out.value(billboard.rotation.vector)
        out.int(Int(billboard.mode))
    }

    static func billboard(_ input: inout CachePayloadReader) throws -> MeshBillboard? {
        guard try input.bool() else { return nil }
        let pivot = try input.value(SIMD3<Float>.self)
        let rotation = try input.value(SIMD4<Float>.self)
        let mode = try input.int()
        guard (0 ... Int(UInt16.max)).contains(mode) else {
            throw CachePayloadError.badCount(mode)
        }
        return MeshBillboard(
            pivot: pivot,
            rotation: simd_quatf(vector: rotation),
            mode: UInt16(mode)
        )
    }
}
