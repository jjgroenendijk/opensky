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
        let scene = sceneTargets()
        var bodies: [NIFCollisionBody] = []
        let roots = file.blocks.enumerated().compactMap { index, block in
            NIFCollisionCarrier(rawValue: block.typeName).map { (index, $0) }
        }
        for (index, carrier) in roots {
            do {
                let decoded = try decodeCollisionObject(
                    index: index,
                    carrier: carrier,
                    scene: scene
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
        carrier: NIFCollisionCarrier,
        scene: SceneTargets
    ) throws -> NIFCollisionBody? {
        var objectReader = BinaryReader(file.blocks[index].data)
        let targetRef = try objectReader.readNIFRef()
        let objectFlags = try objectReader.readUInt16()
        let bodyRef = try objectReader.readNIFRef()
        guard let (bodyIndex, bodyBlock) = try resolvedBlock(bodyRef) else {
            throw NIFError.malformed("collision object \(index) has no rigid body")
        }
        guard NIFRigidBodyRecord.bodyTypeNames.contains(bodyBlock.typeName) else {
            unsupported[bodyBlock.typeName, default: 0] += 1
            return nil
        }

        let record = try NIFRigidBodyRecord(data: bodyBlock.data)
        let targetTransform = targetRef >= 0
            ? scene.transforms[Int(targetRef)] ?? matrix_identity_float4x4
            : matrix_identity_float4x4
        // Only the "T" subclass applies its serialized translation and
        // rotation; a plain bhkRigidBody stores the same fields and ignores
        // them (nif.xml bhkRigidBodyT).
        let bodyTransform = bodyBlock.typeName == "bhkRigidBodyT"
            ? targetTransform * record.localTransform
            : targetTransform
        shapePath.removeAll(keepingCapacity: true)
        let shapes = try decodeShape(
            ref: record.shapeRef,
            parent: matrix_identity_float4x4,
            depth: 0
        )
        return NIFCollisionBody(
            targetBlock: targetRef,
            targetName: targetRef >= 0 ? scene.names[Int(targetRef)] : nil,
            bodyBlock: bodyIndex,
            carrier: carrier,
            collisionObjectFlags: objectFlags,
            worldFilter: record.worldFilter,
            rigidBodyFilter: record.rigidBodyFilter,
            entityResponse: record.entityResponse,
            rigidBodyResponse: record.rigidBodyResponse,
            dynamics: record.dynamics,
            constraints: decodeConstraints(record.constraintRefs),
            bodyFlags: record.bodyFlags,
            transform: bodyTransform,
            shapes: shapes
        )
    }

    /// A joint that fails to decode is tallied and dropped; the body and its
    /// sibling joints survive, because a ragdoll missing one limb is more
    /// useful than no ragdoll.
    private mutating func decodeConstraints(_ refs: [Int32]) -> [NIFCollisionConstraint] {
        var constraints: [NIFCollisionConstraint] = []
        for ref in refs {
            guard let (index, block) = try? resolvedBlock(ref) else {
                failures.append(NIFCollisionFailure(
                    block: Int(ref),
                    message: "constraint ref \(ref) out of range"
                ))
                continue
            }
            do {
                try constraints.append(
                    NIFConstraintDecoder.decode(block: block, index: index)
                )
            } catch let NIFError.unsupported(message) {
                // A constraint class this decoder does not read at all, which
                // is coverage the census should surface. Malformed bytes in a
                // class it does read are a failure, not missing coverage, so
                // they fall to the catch below and leave the tally alone.
                unsupported[block.typeName, default: 0] += 1
                failures.append(NIFCollisionFailure(block: index, message: message))
            } catch {
                failures.append(NIFCollisionFailure(
                    block: index,
                    message: String(describing: error)
                ))
            }
        }
        return constraints
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

    private func sceneTargets() -> SceneTargets {
        var visitor = CollisionTargetTransformVisitor(file: file)
        for root in file.roots {
            try? visitor.visit(
                ref: root,
                parent: matrix_identity_float4x4,
                depth: 0
            )
        }
        return SceneTargets(transforms: visitor.transforms, names: visitor.names)
    }
}

/// What scene traversal knows about every block a collision object can target:
/// where it is, and what it is called.
nonisolated struct SceneTargets {
    let transforms: [Int: float4x4]
    let names: [Int: String]
}

nonisolated private struct CollisionTargetTransformVisitor {
    let file: NIFFile
    var transforms: [Int: float4x4] = [:]
    /// Block index -> node name. The bone name on a character skeleton.
    var names: [Int: String] = [:]
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
            names[index] = node.object.name
            for child in node.children {
                try visit(ref: child, parent: world, depth: depth + 1)
            }
        } else if block.typeName == "BSTriShape" {
            let shape = try NIFTriShape(data: block.data, header: file.header)
            transforms[index] = parent * shape.object.localTransform
            names[index] = shape.object.name
        } else if block.typeName == "BSSubIndexTriShape" {
            let shape = try NIFSubIndexTriShape(data: block.data, header: file.header).shape
            transforms[index] = parent * shape.object.localTransform
            names[index] = shape.object.name
        }
    }
}
