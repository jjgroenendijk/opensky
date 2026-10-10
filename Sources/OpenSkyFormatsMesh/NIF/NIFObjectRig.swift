// An animated object mesh: each mesh below a node the Havok rig names is skinned
// to that node, so the object's behaviour graph moves it. The rest stays still.
// See docs/engine/object-animation.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension NIFFile {
    /// Bone names are matched without case. A mesh under no rig bone, or already
    /// skinned, is left as authored.
    public func nodeSkinnedModel(bones: Set<String>) throws -> Model {
        var flattener = try Flattener(file: self, skeleton: nil)
        for root in roots {
            try flattener.walk(from: root)
        }
        let parents = nodeParents()
        let wanted = Dictionary(
            bones.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first }
        )
        let hierarchy = flattener.hierarchy
        let meshes = zip(flattener.meshes, flattener.meshBlocks).map { mesh, block in
            guard
                let node = Self.rigAncestor(
                    of: block, parents: parents, names: hierarchy.names, wanted: wanted
                ),
                let rest = hierarchy.worldTransforms[node.index]
            else { return mesh }
            return RigidAttachment.skinned(mesh, toNode: node.bone, nodeRest: rest)
        }
        return Model(
            meshes: meshes,
            materials: flattener.materials,
            skippedShapeCount: flattener.skippedShapeCount,
            editorMarkerShapeCount: flattener.editorMarkerShapeCount
        )
    }

    /// Child block to parent block, over every node block that decodes.
    public func nodeParents() -> [Int: Int] {
        var parents: [Int: Int] = [:]
        for (index, block) in blocks.enumerated() {
            for child in nodeChildren(block) where child >= 0 && parents[Int(child)] == nil {
                parents[Int(child)] = index
            }
        }
        return parents
    }

    private func nodeChildren(_ block: Block) -> [Int32] {
        if block.typeName == NIFSwitchNode.typeName {
            return (try? NIFSwitchNode(data: block.data, header: header).children) ?? []
        }
        if block.typeName == "BSMultiBoundNode" {
            return (try? NIFMultiBoundNode(data: block.data, header: header).children) ?? []
        }
        guard NIFNode.traversedTypes.contains(block.typeName) else { return [] }
        return (try? NIFNode(data: block.data, header: header).children) ?? []
    }

    /// The nearest ancestor node the rig names. The step limit stops a cyclic file.
    private static func rigAncestor(
        of block: Int,
        parents: [Int: Int],
        names: [Int: String],
        wanted: [String: String]
    ) -> (index: Int, bone: String)? {
        var current = parents[block]
        var steps = 0
        while let index = current, steps < 64 {
            if let name = names[index], let bone = wanted[name.lowercased()] {
                return (index, bone)
            }
            current = parents[index]
            steps += 1
        }
        return nil
    }
}
