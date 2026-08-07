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
            try builder.walk(from: root)
        }
        worldTransforms = builder.worldTransforms
        parentTransforms = builder.parentTransforms
        names = builder.names
    }

    private struct Builder {
        /// Plausibility limit on how deeply a real skeleton nests. Depth costs
        /// heap rather than call frames, so this stays a policy choice instead
        /// of standing in for the thread's stack budget (issue #388).
        static let maxDepth = 64

        let file: NIFFile
        var worldTransforms: [Int: float4x4] = [:]
        var parentTransforms: [Int: float4x4] = [:]
        var names: [Int: String] = [:]

        mutating func walk(from root: Int32) throws {
            var stack = NIFGraphStack(root: root)
            while let visit = stack.next() {
                guard visit.ref >= 0 else { continue }
                let index = Int(visit.ref)
                guard index < file.blocks.count else {
                    throw NIFError.malformed(
                        "block ref \(visit.ref) out of range (\(file.blocks.count) blocks)"
                    )
                }
                guard visit.depth <= Self.maxDepth else {
                    throw NIFError.malformed("scene graph deeper than \(Self.maxDepth)")
                }
                let block = file.blocks[index]
                guard NIFNode.traversedTypes.contains(block.typeName) else { continue }
                guard stack.enter(index) else {
                    throw NIFError.malformed("node hierarchy cycle at block \(index)")
                }

                // A shared node has no unique parent-space bind transform. Keep
                // first occurrence; scene flatten may still draw shared subtrees.
                guard worldTransforms[index] == nil else { continue }
                let node = try Self.decodeNode(block, header: file.header)
                let world = visit.parent * node.object.localTransform
                parentTransforms[index] = visit.parent
                worldTransforms[index] = world
                if let name = node.object.name {
                    names[index] = name
                }
                stack.push(
                    children: node.children,
                    parent: world,
                    depth: visit.depth + 1
                )
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

    /// Direct construction, for tests and for a caller that already has a bone
    /// table (the rigid-attachment bind lookup, issue #178).
    init(boneTransforms: [String: float4x4]) {
        self.boneTransforms = boneTransforms
    }

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

    /// `name`'s bind transform, falling back to a case-insensitive match.
    ///
    /// The fallback exists because the two skeleton files disagree on case for
    /// the attachment nodes: the Havok rig names the drawn-weapon node
    /// `Weapon` and the NIF names the same node `WEAPON` (observed with
    /// `openskycli skeleton --nif`, recorded in docs/formats/actors.md). Skin
    /// bone names match exactly and take the fast path.
    func transform(forBoneNamed name: String) -> float4x4? {
        if let exact = boneTransforms[name] {
            return exact
        }
        let folded = name.lowercased()
        return boneTransforms.first { $0.key.lowercased() == folded }?.value
    }
}
