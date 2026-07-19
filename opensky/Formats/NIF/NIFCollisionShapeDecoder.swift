// Leaf collision-shape payloads split from graph traversal for bounded,
// independently readable decoders. Layout references + policy:
// docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated extension NIFCollisionDecoder {
    mutating func decodeLeafShape(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> [NIFCollisionShape] {
        switch block.typeName {
        case "bhkCompressedMeshShape":
            return try decodeCompressedShape(block: block, parent: parent)
        case "bhkPackedNiTriStripsShape":
            return try decodePackedShape(block: block, parent: parent)
        case "bhkNiTriStripsShape":
            return try decodeNiTriStripsShape(block: block, parent: parent)
        case "bhkConvexVerticesShape":
            return try [decodeConvexVertices(block: block, parent: parent)]
        case "bhkBoxShape":
            return try [decodeBox(block: block, parent: parent)]
        case "bhkSphereShape":
            return try [decodeSphere(block: block, parent: parent)]
        case "bhkCapsuleShape":
            return try [decodeCapsule(block: block, parent: parent)]
        default:
            unsupported[block.typeName, default: 0] += 1
            return []
        }
    }

    private func decodeCompressedShape(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> [NIFCollisionShape] {
        var reader = BinaryReader(block.data)
        reader.skip(16) // target, user data, radius, unknown float
        let scale = try reader.readVector4().xyz
        reader.skip(20) // radius copy + scale copy
        let dataRef = try reader.readNIFRef()
        guard
            let (_, dataBlock) = try resolvedBlock(dataRef),
            dataBlock.typeName == "bhkCompressedMeshShapeData"
        else {
            throw NIFError.malformed("compressed shape data ref is missing or wrong type")
        }
        return try NIFCompressedCollisionMesh.decode(
            data: dataBlock.data,
            shapeScale: scale
        ).map {
            NIFCollisionShape(
                transform: parent,
                geometry: .triangleSoup(vertices: $0.vertices, indices: $0.indices)
            )
        }
    }

    private func decodePackedShape(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> [NIFCollisionShape] {
        var reader = BinaryReader(block.data)
        reader.skip(16) // user data, padding, radius, padding
        let scale = try reader.readVector4().xyz
        reader.skip(20) // radius copy + scale copy
        let dataRef = try reader.readNIFRef()
        guard
            let (_, dataBlock) = try resolvedBlock(dataRef),
            dataBlock.typeName == "hkPackedNiTriStripsData"
        else {
            throw NIFError.malformed("packed strips data ref is missing or wrong type")
        }
        let soup = try NIFCollisionTriangleCollections.decodePacked(
            data: dataBlock.data,
            scale: scale
        )
        return [NIFCollisionShape(
            transform: parent,
            geometry: .triangleSoup(vertices: soup.vertices, indices: soup.indices)
        )]
    }

    private func decodeNiTriStripsShape(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> [NIFCollisionShape] {
        var reader = BinaryReader(block.data)
        reader.skip(32) // material, radius, padding, grow-by
        let scale = try reader.readVector4().xyz
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 4 else {
            throw NIFError.malformed("NiTriStrips data count \(count) exceeds block size")
        }
        var shapes: [NIFCollisionShape] = []
        shapes.reserveCapacity(count)
        for _ in 0 ..< count {
            let dataRef = try reader.readNIFRef()
            guard
                let (_, dataBlock) = try resolvedBlock(dataRef),
                dataBlock.typeName == "NiTriStripsData"
            else {
                throw NIFError.malformed("NiTriStrips data ref is missing or wrong type")
            }
            let soup = try NIFCollisionTriangleCollections.decodeTriStrips(
                data: dataBlock.data,
                scale: scale
            )
            shapes.append(NIFCollisionShape(
                transform: parent,
                geometry: .triangleSoup(vertices: soup.vertices, indices: soup.indices)
            ))
        }
        return shapes
    }

    private func decodeConvexVertices(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> NIFCollisionShape {
        var reader = BinaryReader(block.data)
        reader.skip(32) // material, radius, vertex/normal properties
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 16 else {
            throw NIFError.malformed("convex vertex count \(count) exceeds block size")
        }
        let scale = NIFCollisionModel.havokToEngineScale
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for _ in 0 ..< count {
            try vertices.append(reader.readVector4().xyz * scale)
        }
        return NIFCollisionShape(transform: parent, geometry: .convexVertices(vertices))
    }

    private func decodeBox(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> NIFCollisionShape {
        var reader = BinaryReader(block.data)
        reader.skip(16) // material, shell radius, padding
        let halfExtents = try reader.readVector3() * NIFCollisionModel.havokToEngineScale
        return NIFCollisionShape(transform: parent, geometry: .box(halfExtents: halfExtents))
    }

    private func decodeSphere(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> NIFCollisionShape {
        var reader = BinaryReader(block.data)
        reader.skip(4) // material
        let radius = try reader.readFloat32() * NIFCollisionModel.havokToEngineScale
        return NIFCollisionShape(transform: parent, geometry: .sphere(radius: radius))
    }

    private func decodeCapsule(
        block: NIFFile.Block,
        parent: float4x4
    ) throws -> NIFCollisionShape {
        var reader = BinaryReader(block.data)
        reader.skip(16) // material, shell radius, padding
        let scale = NIFCollisionModel.havokToEngineScale
        let first = try reader.readVector3() * scale
        let radius1 = try reader.readFloat32() * scale
        let second = try reader.readVector3() * scale
        let radius2 = try reader.readFloat32() * scale
        return NIFCollisionShape(
            transform: parent,
            geometry: .capsule(
                first: first,
                second: second,
                radius: max(radius1, radius2)
            )
        )
    }
}
