// Bethesda multi-bound blocks used by terrain/object LOD containers.
// Reference: NifTools nif.xml (BSMultiBoundNode, BSMultiBound,
// BSMultiBoundAABB), Skyrim BS stream 100.

import Foundation
import simd

nonisolated struct NIFMultiBoundNode {
    let object: NIFObjectPrefix
    let children: [Int32]
    let multiBoundRef: Int32
    let cullingMode: UInt32

    init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)
        children = try Self.readRefs(&reader, label: "child")
        _ = try Self.readRefs(&reader, label: "effect")
        multiBoundRef = try Int32(bitPattern: reader.readUInt32())
        // BSCPCullingType is uint in Skyrim's nif.xml enum storage.
        cullingMode = try reader.readUInt32()
    }

    private static func readRefs(
        _ reader: inout BinaryReader,
        label: String
    ) throws -> [Int32] {
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 4 else {
            throw NIFError.malformed("\(label) count \(count) exceeds block size")
        }
        var refs: [Int32] = []
        refs.reserveCapacity(count)
        for _ in 0 ..< count {
            try refs.append(Int32(bitPattern: reader.readUInt32()))
        }
        return refs
    }
}

nonisolated struct NIFMultiBound {
    let dataRef: Int32

    init(data: Data) throws {
        var reader = BinaryReader(data)
        dataRef = try Int32(bitPattern: reader.readUInt32())
    }
}

nonisolated struct NIFMultiBoundAABB {
    let center: SIMD3<Float>
    let extent: SIMD3<Float>

    init(data: Data) throws {
        var reader = BinaryReader(data)
        center = try reader.readVector3()
        extent = try reader.readVector3()
        guard extent.x >= 0, extent.y >= 0, extent.z >= 0 else {
            throw NIFError.malformed("multi-bound AABB carries a negative extent")
        }
    }
}
