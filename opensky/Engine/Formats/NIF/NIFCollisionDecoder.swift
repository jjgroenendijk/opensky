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
        let shapes = try decodeShapeGraph(root: record.shapeRef)
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

    /// Walks one rigid body's shape graph into a flat list of leaf shapes, in
    /// the pre-order a recursive descent would produce.
    private mutating func decodeShapeGraph(root: Int32) throws -> [NIFCollisionShape] {
        var shapes: [NIFCollisionShape] = []
        var stack = NIFGraphStack(root: root)
        while let visit = stack.next() {
            guard let (index, block) = try resolvedBlock(visit.ref) else { continue }
            guard visit.depth <= Self.maxShapeDepth else {
                throw NIFError.malformed(
                    "collision shape graph exceeds \(Self.maxShapeDepth)"
                )
            }
            guard stack.enter(index) else {
                throw NIFError.malformed("collision shape cycle at block \(index)")
            }
            do {
                try shapes.append(contentsOf: expandShape(
                    block: block,
                    visit: visit,
                    stack: &stack
                ))
            } catch let NIFError.unsupported(message) {
                unsupported[block.typeName, default: 0] += 1
                failures.append(NIFCollisionFailure(block: index, message: message))
            }
        }
        return shapes
    }

    /// Decodes one shape block: a leaf yields geometry, a container queues its
    /// children on `stack` and yields nothing itself.
    private mutating func expandShape(
        block: NIFFile.Block,
        visit: NIFGraphStack.Pending,
        stack: inout NIFGraphStack
    ) throws -> [NIFCollisionShape] {
        let childDepth = visit.depth + 1
        switch block.typeName {
        case "bhkMoppBvTreeShape":
            var reader = BinaryReader(block.data)
            let child = try reader.readNIFRef()
            stack.push(children: [child], parent: visit.parent, depth: childDepth)
        case "bhkTransformShape", "bhkConvexTransformShape":
            var reader = BinaryReader(block.data)
            let child = try reader.readNIFRef()
            reader.skip(16) // material, radius, eight padding bytes
            let transform = try reader.readCollisionMatrix()
            stack.push(
                children: [child],
                parent: visit.parent * transform,
                depth: childDepth
            )
        case "bhkListShape":
            let children = try listShapeRefs(block)
            stack.push(children: children, parent: visit.parent, depth: childDepth)
        default:
            return try decodeLeafShape(block: block, parent: visit.parent)
        }
        return []
    }

    private func listShapeRefs(_ block: NIFFile.Block) throws -> [Int32] {
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
        return refs
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
            try? visitor.walk(from: root)
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

    mutating func walk(from root: Int32) throws {
        var stack = NIFGraphStack(root: root)
        while let visit = stack.next() {
            try step(visit, stack: &stack)
        }
    }

    private mutating func step(
        _ visit: NIFGraphStack.Pending,
        stack: inout NIFGraphStack
    ) throws {
        guard visit.ref >= 0 else { return }
        let index = Int(visit.ref)
        guard index < file.blocks.count, visit.depth <= 64, stack.enter(index) else {
            return
        }
        let parent = visit.parent
        let block = file.blocks[index]
        if NIFNode.traversedTypes.contains(block.typeName) {
            let node = try NIFNode(data: block.data, header: file.header)
            let world = parent * node.object.localTransform
            transforms[index] = world
            names[index] = node.object.name
            stack.push(
                children: node.children,
                parent: world,
                depth: visit.depth + 1
            )
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
