// SSE skin block decode: NiSkinInstance/BSDismemberSkinInstance links one
// shape to NiSkinData bind transforms + NiSkinPartition hardware geometry.
// Every count is bounded by its size-sliced block before allocation/read.
//
// Reference: NifTools nif.xml (NiSkinInstance, BSDismemberSkinInstance,
// NiSkinData, BoneData, NiSkinPartition, SkinPartition, BSVertexDataSSE).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation
import simd

nonisolated struct NIFTransform: Equatable {
    let rotation: simd_float3x3
    let translation: SIMD3<Float>
    let scale: Float

    var matrix: float4x4 {
        float4x4(columns: (
            SIMD4(rotation.columns.0 * scale, 0),
            SIMD4(rotation.columns.1 * scale, 0),
            SIMD4(rotation.columns.2 * scale, 0),
            SIMD4(translation, 1)
        ))
    }

    init(reader: inout BinaryReader) throws {
        rotation = try simd_float3x3(columns: (
            reader.readVector3(), reader.readVector3(), reader.readVector3()
        ))
        translation = try reader.readVector3()
        scale = try reader.readFloat32()
        guard
            scale.isFinite,
            translation.x.isFinite, translation.y.isFinite, translation.z.isFinite
        else {
            throw NIFError.malformed("skin transform contains a non-finite value")
        }
    }
}

nonisolated struct NIFSkinInstance {
    struct BodyPartition: Equatable {
        let flags: UInt16
        let bodyPart: UInt16
    }

    let dataRef: Int32
    let skinPartitionRef: Int32
    let skeletonRootRef: Int32
    let boneRefs: [Int32]
    let bodyPartitions: [BodyPartition]

    init(data: Data, isDismember: Bool) throws {
        var reader = BinaryReader(data)
        dataRef = try Int32(bitPattern: reader.readUInt32())
        skinPartitionRef = try Int32(bitPattern: reader.readUInt32())
        skeletonRootRef = try Int32(bitPattern: reader.readUInt32())
        let boneCount = try Int(reader.readUInt32())
        guard boneCount * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin instance bone count exceeds block size")
        }
        var boneRefs: [Int32] = []
        boneRefs.reserveCapacity(boneCount)
        for _ in 0 ..< boneCount {
            try boneRefs.append(Int32(bitPattern: reader.readUInt32()))
        }
        self.boneRefs = boneRefs

        if isDismember {
            let partitionCount = try Int(reader.readUInt32())
            guard partitionCount * 4 <= reader.bytesRemaining else {
                throw NIFError.malformed("dismember partition count exceeds block size")
            }
            var bodyPartitions: [BodyPartition] = []
            bodyPartitions.reserveCapacity(partitionCount)
            for _ in 0 ..< partitionCount {
                try bodyPartitions.append(BodyPartition(
                    flags: reader.readUInt16(),
                    bodyPart: reader.readUInt16()
                ))
            }
            self.bodyPartitions = bodyPartitions
        } else {
            bodyPartitions = []
        }
    }
}

nonisolated struct NIFSkinData {
    struct VertexWeight: Equatable {
        let vertex: UInt16
        let weight: Float
    }

    struct Bone: Equatable {
        let skinToBone: NIFTransform
        let boundingSphereCenter: SIMD3<Float>
        let boundingSphereRadius: Float
        let vertexWeights: [VertexWeight]
    }

    let rootParentToSkin: NIFTransform
    let bones: [Bone]

    init(data: Data) throws {
        var reader = BinaryReader(data)
        rootParentToSkin = try NIFTransform(reader: &reader)
        let boneCount = try Int(reader.readUInt32())
        let hasVertexWeights = try reader.readUInt8() != 0
        // BoneData fixed prefix = transform 52 + bound 16 + count 2.
        guard boneCount <= reader.bytesRemaining / 70 else {
            throw NIFError.malformed("skin data bone count exceeds block size")
        }
        var bones: [Bone] = []
        bones.reserveCapacity(boneCount)
        for _ in 0 ..< boneCount {
            let transform = try NIFTransform(reader: &reader)
            let center = try reader.readVector3()
            let radius = try reader.readFloat32()
            guard
                center.x.isFinite, center.y.isFinite, center.z.isFinite,
                radius.isFinite, radius >= 0
            else {
                throw NIFError.malformed("skin bone bound is invalid")
            }
            let vertexCount = try Int(reader.readUInt16())
            let storedCount = hasVertexWeights ? vertexCount : 0
            guard storedCount * 6 <= reader.bytesRemaining else {
                throw NIFError.malformed("skin bone vertex weights exceed block size")
            }
            var weights: [VertexWeight] = []
            weights.reserveCapacity(storedCount)
            for _ in 0 ..< storedCount {
                let vertex = try reader.readUInt16()
                let weight = try reader.readFloat32()
                guard weight.isFinite, weight >= 0 else {
                    throw NIFError.malformed("skin bone weight is invalid")
                }
                weights.append(VertexWeight(vertex: vertex, weight: weight))
            }
            bones.append(Bone(
                skinToBone: transform,
                boundingSphereCenter: center,
                boundingSphereRadius: radius,
                vertexWeights: weights
            ))
        }
        self.bones = bones
    }
}

nonisolated struct NIFSkinPartition {
    struct Partition {
        let bonePalette: [UInt16]
        let vertexMap: [UInt16]
        let vertexWeights: [SIMD4<Float>]
        let boneIndices: [SIMD4<UInt16>]
        /// Global vertex indices in SSE's mandatory triangle-copy field.
        let triangleIndices: [UInt16]
    }

    let attributes: NIFTriShape.VertexAttributes
    let vertices: NIFTriShape.VertexArrays
    let partitions: [Partition]

    init(data: Data, header: NIFHeader) throws {
        guard header.bsStream?.version == 100 else {
            throw NIFError.unsupported("NiSkinPartition outside an SSE stream (BS 100)")
        }
        var reader = BinaryReader(data)
        let partitionCount = try Int(reader.readUInt32())
        let dataSize = try Int(reader.readUInt32())
        let vertexSize = try Int(reader.readUInt32())
        let desc = try reader.readUInt64()
        attributes = NIFTriShape.VertexAttributes(
            rawValue: UInt16((desc >> 44) & 0x7FF)
        )
        let expectedStride = NIFTriShape.stride(for: attributes)
        guard vertexSize == expectedStride, vertexSize > 0 else {
            throw NIFError.malformed(
                "skin vertex size \(vertexSize) != descriptor stride \(expectedStride)"
            )
        }
        guard dataSize % vertexSize == 0, dataSize <= reader.bytesRemaining else {
            throw NIFError.malformed("skin vertex data size exceeds block or stride")
        }
        vertices = try NIFTriShape.readVertexRecords(
            &reader,
            attributes: attributes,
            count: dataSize / vertexSize
        )

        // Every partition has a 24-byte fixed tail after its variable arrays;
        // use that minimum to reject hostile counts before reserving.
        guard partitionCount <= reader.bytesRemaining / 24 else {
            throw NIFError.malformed("skin partition count exceeds block size")
        }
        var partitions: [Partition] = []
        partitions.reserveCapacity(partitionCount)
        for _ in 0 ..< partitionCount {
            try partitions.append(Self.readPartition(
                &reader,
                vertexCount: vertices.positions.count,
                expectedDesc: desc
            ))
        }
        self.partitions = partitions
    }

    private static func readPartition(
        _ reader: inout BinaryReader,
        vertexCount totalVertexCount: Int,
        expectedDesc: UInt64
    ) throws -> Partition {
        let vertexCount = try Int(reader.readUInt16())
        let triangleCount = try Int(reader.readUInt16())
        let boneCount = try Int(reader.readUInt16())
        let stripCount = try Int(reader.readUInt16())
        let weightsPerVertex = try Int(reader.readUInt16())
        guard (1 ... 4).contains(weightsPerVertex) else {
            throw NIFError.unsupported(
                "skin partition has \(weightsPerVertex) weights per vertex"
            )
        }
        let palette = try readPalette(reader: &reader, count: boneCount)
        let vertexMap = try readVertexMap(reader: &reader, count: vertexCount)
        guard vertexMap.allSatisfy({ Int($0) < totalVertexCount }) else {
            throw NIFError.malformed("skin partition vertex map index out of range")
        }

        let hasVertexWeights = try reader.readUInt8() != 0
        let storedWeights = try readWeights(
            reader: &reader,
            vertexCount: vertexCount,
            influenceCount: weightsPerVertex,
            present: hasVertexWeights
        )

        try skipFaces(
            reader: &reader,
            triangleCount: triangleCount,
            stripCount: stripCount
        )

        let hasBoneIndices = try reader.readUInt8() != 0
        let storedIndices = try readBoneIndices(
            reader: &reader,
            vertexCount: vertexCount,
            influenceCount: weightsPerVertex,
            present: hasBoneIndices
        )
        _ = try reader.readUInt8() // LOD level
        _ = try reader.readUInt8() // global-VB flag
        let partitionDesc = try reader.readUInt64()
        guard partitionDesc == expectedDesc else {
            throw NIFError.unsupported("skin partition vertex descriptors differ")
        }

        let triangles = try readTriangles(
            reader: &reader,
            count: triangleCount,
            vertexCount: totalVertexCount
        )
        return Partition(
            bonePalette: palette,
            vertexMap: vertexMap,
            vertexWeights: storedWeights,
            boneIndices: storedIndices,
            triangleIndices: triangles
        )
    }

    private static func readPalette(
        reader: inout BinaryReader,
        count: Int
    ) throws -> [UInt16] {
        guard count * 2 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin partition bone palette exceeds block size")
        }
        var result: [UInt16] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            try result.append(reader.readUInt16())
        }
        return result
    }

    private static func readVertexMap(
        reader: inout BinaryReader,
        count: Int
    ) throws -> [UInt16] {
        guard try reader.readUInt8() != 0 else {
            guard count <= Int(UInt16.max) + 1 else {
                throw NIFError.malformed("implicit skin vertex map exceeds uint16")
            }
            return (0 ..< count).map(UInt16.init)
        }
        guard count * 2 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin partition vertex map exceeds block size")
        }
        var result: [UInt16] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            try result.append(reader.readUInt16())
        }
        return result
    }

    private static func skipFaces(
        reader: inout BinaryReader,
        triangleCount: Int,
        stripCount: Int
    ) throws {
        guard stripCount * 2 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin strip lengths exceed block size")
        }
        var stripIndexCount = 0
        for _ in 0 ..< stripCount {
            stripIndexCount += try Int(reader.readUInt16())
        }
        guard try reader.readUInt8() != 0 else { return }
        let faceIndexCount = stripCount == 0 ? triangleCount * 3 : stripIndexCount
        guard faceIndexCount * 2 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin partition faces exceed block size")
        }
        // Vanilla later body partitions violate nif.xml's local range here.
        // Mandatory global triangle copy below is renderer source of truth.
        reader.skip(faceIndexCount * 2)
    }

    private static func readTriangles(
        reader: inout BinaryReader,
        count: Int,
        vertexCount: Int
    ) throws -> [UInt16] {
        guard count * 6 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin triangle copy exceeds block size")
        }
        var result: [UInt16] = []
        result.reserveCapacity(count * 3)
        for _ in 0 ..< count * 3 {
            let index = try reader.readUInt16()
            guard Int(index) < vertexCount else {
                throw NIFError.malformed("skin triangle-copy index out of range")
            }
            result.append(index)
        }
        return result
    }

    private static func readWeights(
        reader: inout BinaryReader,
        vertexCount: Int,
        influenceCount: Int,
        present: Bool
    ) throws -> [SIMD4<Float>] {
        guard present else { return [] }
        guard vertexCount * influenceCount * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed("skin partition weights exceed block size")
        }
        var result: [SIMD4<Float>] = []
        result.reserveCapacity(vertexCount)
        for _ in 0 ..< vertexCount {
            var weights = SIMD4<Float>.zero
            for influence in 0 ..< influenceCount {
                let weight = try reader.readFloat32()
                guard weight.isFinite, weight >= 0 else {
                    throw NIFError.malformed("skin partition weight is invalid")
                }
                weights[influence] = weight
            }
            result.append(weights)
        }
        return result
    }

    private static func readBoneIndices(
        reader: inout BinaryReader,
        vertexCount: Int,
        influenceCount: Int,
        present: Bool
    ) throws -> [SIMD4<UInt16>] {
        guard present else { return [] }
        guard vertexCount * influenceCount <= reader.bytesRemaining else {
            throw NIFError.malformed("skin partition bone indices exceed block size")
        }
        var result: [SIMD4<UInt16>] = []
        result.reserveCapacity(vertexCount)
        for _ in 0 ..< vertexCount {
            var indices = SIMD4<UInt16>.zero
            for influence in 0 ..< influenceCount {
                indices[influence] = try UInt16(reader.readUInt8())
            }
            result.append(indices)
        }
        return result
    }
}
