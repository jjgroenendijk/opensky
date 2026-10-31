// The flattened model of one branch of a NIF. An AMMO model holds the quiver under
// the node `ArrowQuiver` and the arrow on the string beside it; a worn quiver draws
// only the branch. See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFFile {
    /// The shapes below the node named `node`, any case, at their places in the
    /// whole model. No such node gives a model with no meshes.
    public func model(
        skeleton: NIFSkeleton?, keepingRoot: Bool, below node: String
    ) throws -> Model {
        var flattener = try Flattener(file: self, skeleton: skeleton, keepingRoot: keepingRoot)
        for root in roots {
            try flattener.walk(from: root)
        }
        let parents = nodeParents()
        let names = flattener.hierarchy.names
        let wanted = node.lowercased()
        let meshes = zip(flattener.meshes, flattener.meshBlocks).compactMap { mesh, block in
            Self.hasAncestor(named: wanted, of: block, parents: parents, names: names)
                ? mesh : nil
        }
        return Model(
            meshes: meshes,
            materials: flattener.materials,
            skippedShapeCount: flattener.skippedShapeCount,
            editorMarkerShapeCount: flattener.editorMarkerShapeCount
        )
    }

    /// The step limit stops a cyclic file.
    private static func hasAncestor(
        named name: String, of block: Int, parents: [Int: Int], names: [Int: String]
    ) -> Bool {
        var current = parents[block]
        var steps = 0
        while let index = current, steps < 64 {
            if names[index]?.lowercased() == name {
                return true
            }
            current = parents[index]
            steps += 1
        }
        return false
    }
}
