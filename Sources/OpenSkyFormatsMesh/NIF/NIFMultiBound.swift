// Bethesda multi-bound blocks: a `BSMultiBoundNode` names a `BSMultiBound`, whose
// data is a box around the node's subtree. Terrain and object LOD and many
// interiors use them. Layout: docs/formats/nif.md#multi-bounds.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFMultiBoundNode: Sendable {
    public let object: NIFObjectPrefix
    public let children: [Int32]
    public let multiBoundRef: Int32
    public let cullingMode: UInt32

    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)
        children = try NIFNode.readRefs(&reader, label: "child")
        _ = try NIFNode.readRefs(&reader, label: "effect")
        multiBoundRef = try Int32(bitPattern: reader.readUInt32())
        // BSCPCullingType is uint in Skyrim's nif.xml enum storage.
        cullingMode = try reader.readUInt32()
    }
}

nonisolated public struct NIFMultiBound: Sendable {
    public static let typeName = "BSMultiBound"

    public let dataRef: Int32

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        dataRef = try reader.readNIFRef()
    }
}

/// `BSMultiBoundAABB` or `BSMultiBoundOBB`: a box in the node's space.
nonisolated public struct NIFMultiBoundBox: Equatable, Sendable {
    public static let alignedType = "BSMultiBoundAABB"
    public static let orientedType = "BSMultiBoundOBB"

    public let center: SIMD3<Float>
    /// Half the box's size along each of its axes.
    public let extent: SIMD3<Float>
    /// The box's axes; identity for an axis-aligned box.
    public let rotation: simd_float3x3

    public init(reader: inout BinaryReader, oriented: Bool) throws {
        center = try reader.readVector3()
        extent = try reader.readVector3()
        guard extent.x >= 0, extent.y >= 0, extent.z >= 0 else {
            throw NIFError.malformed("multi-bound box carries a negative extent")
        }
        // Row-vector storage, read as rows for the column-vector transpose.
        rotation = oriented
            ? try simd_float3x3(rows: [
                reader.readVector3(),
                reader.readVector3(),
                reader.readVector3()
            ])
            : matrix_identity_float3x3
    }

    /// The eight corners after `transform`.
    public func corners(transform: float4x4) -> [SIMD3<Float>] {
        (0 ..< 8).map { index in
            let sign = SIMD3<Float>(
                index & 1 == 0 ? -1 : 1, index & 2 == 0 ? -1 : 1, index & 4 == 0 ? -1 : 1
            )
            let local = center + rotation * (extent * sign)
            let point = transform * SIMD4(local, 1)
            return SIMD3(point.x, point.y, point.z)
        }
    }
}

nonisolated extension NIFBlockDecoders {
    static let bounds: [String: Decode] = [
        NIFMultiBound.typeName: { reader, _ in try reader.readNIFRef() },
        NIFMultiBoundBox.alignedType: { reader, _ in
            try NIFMultiBoundBox(reader: &reader, oriented: false)
        },
        NIFMultiBoundBox.orientedType: { reader, _ in
            try NIFMultiBoundBox(reader: &reader, oriented: true)
        }
    ]
}
