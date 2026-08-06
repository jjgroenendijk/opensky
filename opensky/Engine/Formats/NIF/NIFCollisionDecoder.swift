// Decode collision graphs rooted at bhkCollisionObject blocks. Rigid-body
// query metadata stays attached to clean engine geometry; MOPP code is skipped
// in favor of its child shape. Unknown reachable blocks are reported, while a
// malformed root cannot discard successfully decoded sibling roots.
//
// Reference: NifTools nif.xml bhk object inheritance + field order.
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated extension NIFFile {
    func collisionModel() -> NIFCollisionModel {
        var decoder = NIFCollisionDecoder(file: self)
        return decoder.decode()
    }
}

nonisolated struct NIFCollisionDecoder {
    static let maxShapeDepth = 64

    let file: NIFFile
    var unsupported: [String: Int] = [:]
    var failures: [NIFCollisionFailure] = []
    var shapePath: Set<Int> = []

    mutating func decode() -> NIFCollisionModel {
        let targetTransforms = sceneTransforms()
        var bodies: [NIFCollisionBody] = []
        let roots = file.blocks.enumerated().filter {
            $0.element.typeName == "bhkCollisionObject"
        }
        for (index, _) in roots {
            do {
                let decoded = try decodeCollisionObject(
                    index: index,
                    targetTransforms: targetTransforms
                )
                if let body = decoded {
                    bodies.append(body)
                }
            } catch {
                failures.append(NIFCollisionFailure(
                    block: index,
                    message: String(describing: error)
                ))
            }
        }
        return NIFCollisionModel(
            bodies: bodies,
            unsupportedReachableBlocks: unsupported,
            decodeFailures: failures
        )
    }

    private mutating func decodeCollisionObject(
        index: Int,
        targetTransforms: [Int: float4x4]
    ) throws -> NIFCollisionBody? {
        let objectBlock = file.blocks[index]
        var objectReader = BinaryReader(objectBlock.data)
        let targetRef = try objectReader.readNIFRef()
        let objectFlags = try objectReader.readUInt16()
        let bodyRef = try objectReader.readNIFRef()
        guard let (_, bodyBlock) = try resolvedBlock(bodyRef) else {
            throw NIFError.malformed("collision object \(index) has no rigid body")
        }
        guard
            bodyBlock.typeName == "bhkRigidBody"
            || bodyBlock.typeName == "bhkRigidBodyT"
        else {
            unsupported[bodyBlock.typeName, default: 0] += 1
            return nil
        }

        var reader = BinaryReader(bodyBlock.data)
        let shapeRef = try reader.readNIFRef()
        let worldFilter = try reader.readCollisionFilter()
        reader.skip(20) // bhkWorldObjectCInfo
        let entityResponse = try reader.readUInt8()
        reader.skip(3) // unused byte + callback delay

        // Skyrim bhkRigidBodyCInfo2010 prefix. Keep both serialized
        // filters/responses: either can make a body query-only.
        reader.skip(4)
        let rigidBodyFilter = try reader.readCollisionFilter()
        reader.skip(8) // padding + unknown uint
        let rigidBodyResponse = try reader.readUInt8()
        reader.skip(3)
        let rigidTransform = try reader.readHavokTransform()
        reader.skip(96) // velocities, inertia tensor, center
        reader.skip(44) // mass through penetration depth
        let motionSystem = try reader.readUInt8()

        let targetTransform = targetRef >= 0
            ? targetTransforms[Int(targetRef)] ?? matrix_identity_float4x4
            : matrix_identity_float4x4
        let bodyTransform = bodyBlock.typeName == "bhkRigidBodyT"
            ? targetTransform * rigidTransform
            : targetTransform
        shapePath.removeAll(keepingCapacity: true)
        let shapes = try decodeShape(
            ref: shapeRef,
            parent: matrix_identity_float4x4,
            depth: 0
        )
        return NIFCollisionBody(
            targetBlock: targetRef,
            collisionObjectFlags: objectFlags,
            worldFilter: worldFilter,
            rigidBodyFilter: rigidBodyFilter,
            entityResponse: entityResponse,
            rigidBodyResponse: rigidBodyResponse,
            motionSystem: motionSystem,
            transform: bodyTransform,
            shapes: shapes
        )
    }

    private mutating func decodeShape(
        ref: Int32,
        parent: float4x4,
        depth: Int
    ) throws -> [NIFCollisionShape] {
        guard let (index, block) = try resolvedBlock(ref) else { return [] }
        guard depth <= Self.maxShapeDepth else {
            throw NIFError.malformed("collision shape graph exceeds \(Self.maxShapeDepth)")
        }
        guard shapePath.insert(index).inserted else {
            throw NIFError.malformed("collision shape cycle at block \(index)")
        }
        defer { shapePath.remove(index) }

        do {
            return try decodeShapePayload(
                block: block,
                parent: parent,
                depth: depth
            )
        } catch let NIFError.unsupported(message) {
            unsupported[block.typeName, default: 0] += 1
            failures.append(NIFCollisionFailure(block: index, message: message))
            return []
        }
    }

    private mutating func decodeShapePayload(
        block: NIFFile.Block,
        parent: float4x4,
        depth: Int
    ) throws -> [NIFCollisionShape] {
        switch block.typeName {
        case "bhkMoppBvTreeShape":
            var reader = BinaryReader(block.data)
            return try decodeShape(
                ref: reader.readNIFRef(),
                parent: parent,
                depth: depth + 1
            )
        case "bhkTransformShape", "bhkConvexTransformShape":
            return try decodeTransformShape(
                block: block,
                parent: parent,
                depth: depth
            )
        case "bhkListShape":
            return try decodeListShape(block: block, parent: parent, depth: depth)
        default:
            return try decodeLeafShape(block: block, parent: parent)
        }
    }

    private mutating func decodeTransformShape(
        block: NIFFile.Block,
        parent: float4x4,
        depth: Int
    ) throws -> [NIFCollisionShape] {
        var reader = BinaryReader(block.data)
        let child = try reader.readNIFRef()
        reader.skip(16) // material, radius, eight padding bytes
        let transform = try reader.readCollisionMatrix()
        return try decodeShape(
            ref: child,
            parent: parent * transform,
            depth: depth + 1
        )
    }

    private mutating func decodeListShape(
        block: NIFFile.Block,
        parent: float4x4,
        depth: Int
    ) throws -> [NIFCollisionShape] {
        var reader = BinaryReader(block.data)
        let count = try Int(reader.readUInt32())
        guard count <= 256, count <= reader.bytesRemaining / 4 else {
            throw NIFError.malformed("bhkListShape count \(count) exceeds block size")
        }
        var refs: [Int32] = []
        refs.reserveCapacity(count)
        for _ in 0 ..< count {
            try refs.append(reader.readNIFRef())
        }
        var shapes: [NIFCollisionShape] = []
        for child in refs {
            try shapes.append(contentsOf: decodeShape(
                ref: child,
                parent: parent,
                depth: depth + 1
            ))
        }
        return shapes
    }

    func resolvedBlock(_ ref: Int32) throws -> (Int, NIFFile.Block)? {
        guard ref >= 0 else { return nil }
        let index = Int(ref)
        guard index < file.blocks.count else {
            throw NIFError.malformed(
                "collision block ref \(ref) out of range (\(file.blocks.count) blocks)"
            )
        }
        return (index, file.blocks[index])
    }

    private func sceneTransforms() -> [Int: float4x4] {
        var visitor = CollisionTargetTransformVisitor(file: file)
        for root in file.roots {
            try? visitor.visit(
                ref: root,
                parent: matrix_identity_float4x4,
                depth: 0
            )
        }
        return visitor.transforms
    }
}

nonisolated private struct CollisionTargetTransformVisitor {
    let file: NIFFile
    var transforms: [Int: float4x4] = [:]
    var path: Set<Int> = []

    mutating func visit(ref: Int32, parent: float4x4, depth: Int) throws {
        guard ref >= 0 else { return }
        let index = Int(ref)
        guard index < file.blocks.count, depth <= 64, path.insert(index).inserted else {
            return
        }
        defer { path.remove(index) }
        let block = file.blocks[index]
        if NIFNode.traversedTypes.contains(block.typeName) {
            let node = try NIFNode(data: block.data, header: file.header)
            let world = parent * node.object.localTransform
            transforms[index] = world
            for child in node.children {
                try visit(ref: child, parent: world, depth: depth + 1)
            }
        } else if block.typeName == "BSTriShape" {
            let shape = try NIFTriShape(data: block.data, header: file.header)
            transforms[index] = parent * shape.object.localTransform
        } else if block.typeName == "BSSubIndexTriShape" {
            let shape = try NIFSubIndexTriShape(data: block.data, header: file.header).shape
            transforms[index] = parent * shape.object.localTransform
        }
    }
}
