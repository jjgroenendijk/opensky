// `NiTriShape` and `BSLODTriShape`, the older geometry some Skyrim meshes still
// use, with the `NiTriShapeData` that holds their vertices. The flatten turns them
// into the same `NIFTriShape` a `BSTriShape` gives. Layout: docs/formats/nif.md#nitrishape.

import Foundation
import OpenSkyFormatsCore
import simd

/// nif.xml `NiGeometry` at stream 100: the shape's refs, without vertices.
nonisolated public struct NIFLegacyTriShape: Sendable {
    public static let typeName = "NiTriShape"
    public static let lodTypeName = "BSLODTriShape"

    public let object: NIFObjectPrefix
    public let dataRef: Int32
    public let skinRef: Int32
    /// nif.xml `MaterialData` names; vanilla shapes carry none.
    public let materialNames: [String?]
    public let shaderPropertyRef: Int32
    public let alphaPropertyRef: Int32
    /// `BSLODTriShape`: the triangle count of each of its three detail levels.
    public let lodSizes: [UInt32]

    public init(reader: inout BinaryReader, header: NIFHeader, isLOD: Bool) throws {
        object = try NIFObjectPrefix(reader: &reader, header: header)
        dataRef = try reader.readNIFRef()
        skinRef = try reader.readNIFRef()
        let materials = try reader.readNIFCount(stride: 8, label: "material")
        materialNames = try (0 ..< materials).map { _ in try reader.readNIFString(header) }
        reader.skip(materials * 4) // material extra data
        reader.skip(4 + 1) // active material, material needs update
        shaderPropertyRef = try reader.readNIFRef()
        alphaPropertyRef = try reader.readNIFRef()
        lodSizes = isLOD ? try (0 ..< 3).map { _ in try reader.readUInt32() } : []
    }
}

/// nif.xml `NiTriShapeData` at stream 100: vertex arrays and a triangle list.
nonisolated public struct NIFTriShapeData: Sendable {
    public static let typeName = "NiTriShapeData"

    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let tangents: [SIMD3<Float>]
    public let bitangents: [SIMD3<Float>]
    public let colors: [SIMD4<Float>]
    /// The first UV set; nif.xml `BSGeometryDataFlags` bit 0 says whether it exists.
    public let uvs: [SIMD2<Float>]
    public let boundingSphere: SIMD4<Float>
    public let indices: [UInt16]

    public init(reader: inout BinaryReader) throws {
        reader.skip(4) // group ID
        let count = try Int(reader.readUInt16())
        reader.skip(2) // keep and compress flags
        positions = try Self.vectors(&reader, count: count, present: reader.readUInt8() != 0)
        let flags = try reader.readUInt16()
        reader.skip(4) // material CRC
        let hasNormals = try reader.readUInt8() != 0
        normals = try Self.vectors(&reader, count: count, present: hasNormals)
        let hasTangents = hasNormals && flags & 0x1000 != 0
        // As in BSTriShape, the bitangents follow U (docs/formats/nif.md#nitrishape).
        tangents = try Self.vectors(&reader, count: count, present: hasTangents)
        bitangents = try Self.vectors(&reader, count: count, present: hasTangents)
        boundingSphere = try reader.readVector4()
        let hasColors = try reader.readUInt8() != 0
        _ = try reader.checkNIFCount(hasColors ? count : 0, stride: 16, label: "colour")
        colors = try (0 ..< (hasColors ? count : 0)).map { _ in try reader.readVector4() }
        let uvSets = Int(flags & 1)
        _ = try reader.checkNIFCount(count * uvSets, stride: 8, label: "UV")
        uvs = try (0 ..< count * uvSets).map { _ in
            try SIMD2(reader.readFloat32(), reader.readFloat32())
        }
        reader.skip(2 + 4) // consistency flags, additional data ref
        indices = try Self.triangles(&reader, vertexCount: count)
    }

    /// `NiTriBasedGeomData` triangle count, then the `NiTriShapeData` list and match
    /// groups, which the flatten does not need.
    private static func triangles(
        _ reader: inout BinaryReader,
        vertexCount: Int
    ) throws -> [UInt16] {
        let triangles = try Int(reader.readUInt16())
        reader.skip(4) // triangle point count
        let hasTriangles = try reader.readUInt8() != 0
        let count = try reader.checkNIFCount(
            hasTriangles ? triangles * 3 : 0,
            stride: 2,
            label: "index"
        )
        let indices = try (0 ..< count).map { _ in try reader.readUInt16() }
        guard indices.allSatisfy({ Int($0) < vertexCount }) else {
            throw NIFError.malformed("NiTriShapeData index past \(vertexCount) vertices")
        }
        let groups = try reader.readNIFShortCount(stride: 2, label: "match group")
        for _ in 0 ..< groups {
            let members = try reader.readNIFShortCount(stride: 2, label: "match group vertex")
            reader.skip(members * 2)
        }
        return indices
    }

    private static func vectors(
        _ reader: inout BinaryReader, count: Int, present: Bool
    ) throws -> [SIMD3<Float>] {
        guard present else { return [] }
        _ = try reader.checkNIFCount(count, stride: 12, label: "vertex")
        return try (0 ..< count).map { _ in try reader.readVector3() }
    }
}

nonisolated extension NIFTriShape {
    /// The engine shape of an `NiTriShape` and its data. Vanilla legacy shapes are
    /// never skinned, so a skinned one keeps its skin ref for the flatten to reject.
    public init(legacy shape: NIFLegacyTriShape, data: NIFTriShapeData) {
        self.init(
            object: shape.object,
            sphere: data.boundingSphere,
            refs: SIMD3(shape.skinRef, shape.shaderPropertyRef, shape.alphaPropertyRef),
            arrays: VertexArrays(
                positions: data.positions, uvs: data.uvs, normals: data.normals,
                tangents: data.tangents, bitangents: data.bitangents, colors: data.colors,
                boneWeights: [], boneIndices: []
            ),
            indices: data.indices
        )
    }

    /// The `NIFTriShape` behind any geometry block, or nil for a type that holds none.
    public static func decode(_ block: NIFFile.Block, in file: NIFFile) throws -> NIFTriShape? {
        switch block.typeName {
        case "BSTriShape":
            return try NIFTriShape(data: block.data, header: file.header)
        case "BSSubIndexTriShape":
            return try NIFSubIndexTriShape(data: block.data, header: file.header).shape
        case "BSDynamicTriShape":
            return try NIFDynamicTriShape(data: block.data, header: file.header).shape
        case NIFLegacyTriShape.typeName, NIFLegacyTriShape.lodTypeName:
            var reader = BinaryReader(block.data)
            let shape = try NIFLegacyTriShape(
                reader: &reader, header: file.header,
                isLOD: block.typeName == NIFLegacyTriShape.lodTypeName
            )
            guard shape.dataRef >= 0, Int(shape.dataRef) < file.blocks.count else {
                throw NIFError.malformed("\(block.typeName) has no NiTriShapeData")
            }
            let dataBlock = file.blocks[Int(shape.dataRef)]
            guard dataBlock.typeName == NIFTriShapeData.typeName else {
                throw NIFError.malformed("\(block.typeName) data is \(dataBlock.typeName)")
            }
            var dataReader = BinaryReader(dataBlock.data)
            return try NIFTriShape(legacy: shape, data: NIFTriShapeData(reader: &dataReader))
        default:
            return nil
        }
    }
}

nonisolated extension NIFBlockDecoders {
    static let geometry: [String: Decode] = [
        NIFLegacyTriShape.typeName: {
            try NIFLegacyTriShape(reader: &$0, header: $1, isLOD: false)
        },
        NIFLegacyTriShape.lodTypeName: {
            try NIFLegacyTriShape(reader: &$0, header: $1, isLOD: true)
        },
        NIFTriShapeData.typeName: { reader, _ in try NIFTriShapeData(reader: &reader) }
    ]
}
