// Resolves NiNode local transforms into one bind-pose hierarchy. Skinned
// shapes reference bone blocks by index; this map supplies each bone's
// current transform relative to the skeleton root parent.
//
// Reference: NifTools nif.xml (NiNode children + NiAVObject transform).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml

import Foundation
import simd

nonisolated struct NIFNodeHierarchy {
    let worldTransforms: [Int: float4x4]
    let parentTransforms: [Int: float4x4]
    let names: [Int: String]

    init(file: NIFFile) throws {
        var builder = Builder(file: file)
        for root in file.roots {
            try builder.visit(
                ref: root,
                parent: matrix_identity_float4x4,
                depth: 0
            )
        }
        worldTransforms = builder.worldTransforms
        parentTransforms = builder.parentTransforms
        names = builder.names
    }

    private struct Builder {
        let file: NIFFile
        var worldTransforms: [Int: float4x4] = [:]
        var parentTransforms: [Int: float4x4] = [:]
        var names: [Int: String] = [:]
        var path: Set<Int> = []

        mutating func visit(ref: Int32, parent: float4x4, depth: Int) throws {
            guard ref >= 0 else { return }
            let index = Int(ref)
            guard index < file.blocks.count else {
                throw NIFError.malformed(
                    "block ref \(ref) out of range (\(file.blocks.count) blocks)"
                )
            }
            guard depth <= 64 else {
                throw NIFError.malformed("scene graph deeper than 64")
            }
            let block = file.blocks[index]
            guard NIFNode.traversedTypes.contains(block.typeName) else { return }
            guard path.insert(index).inserted else {
                throw NIFError.malformed("node hierarchy cycle at block \(index)")
            }
            defer { path.remove(index) }

            // A shared node has no unique parent-space bind transform. Keep
            // first occurrence; scene flatten may still draw shared subtrees.
            guard worldTransforms[index] == nil else { return }
            let node = try Self.decodeNode(block, header: file.header)
            let world = parent * node.object.localTransform
            parentTransforms[index] = parent
            worldTransforms[index] = world
            if let name = node.object.name {
                names[index] = name
            }
            for child in node.children {
                try visit(ref: child, parent: world, depth: depth + 1)
            }
        }

        private static func decodeNode(
            _ block: NIFFile.Block,
            header: NIFHeader
        ) throws -> NIFNode {
            if block.typeName == "BSMultiBoundNode" {
                let multi = try NIFMultiBoundNode(data: block.data, header: header)
                return NIFNode(object: multi.object, children: multi.children)
            }
            return try NIFNode(data: block.data, header: header)
        }
    }
}

/// Bind-pose bone tree decoded from a skeleton NIF. Skin instances refer to
/// dummy nodes in their own file; names connect those refs to full skeleton
/// world transforms, including translations omitted by vanilla body dummies.
nonisolated struct NIFSkeleton {
    let boneTransforms: [String: float4x4]

    init(file: NIFFile) throws {
        let hierarchy = try NIFNodeHierarchy(file: file)
        var transforms: [String: float4x4] = [:]
        for (index, name) in hierarchy.names where transforms[name] == nil {
            if let transform = hierarchy.worldTransforms[index] {
                transforms[name] = transform
            }
        }
        boneTransforms = transforms
    }
}
