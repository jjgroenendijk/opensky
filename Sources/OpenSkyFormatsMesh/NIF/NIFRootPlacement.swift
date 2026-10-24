// The game places a model by putting the reference's transform in place of the
// root node's own transform. See docs/formats/nif.md "Scene graph -> engine mesh".

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension NIFFile {
    /// The parent transform a scene walk starts from at `root`. It cancels the
    /// root's own transform, so the root lands at the identity. A bone attachment
    /// keeps the root's transform and passes `keepingRoot`.
    public func walkParent(ofRoot root: Int32, keepingRoot: Bool = false) -> float4x4 {
        guard
            !keepingRoot, root >= 0, Int(root) < blocks.count,
            Self.placedRootTypes.contains(blocks[Int(root)].typeName)
        else { return matrix_identity_float4x4 }
        var reader = BinaryReader(blocks[Int(root)].data)
        guard
            let object = try? NIFObjectPrefix(reader: &reader, header: header),
            object.scale != 0
        else { return matrix_identity_float4x4 }
        return object.localTransform.inverse
    }

    /// Root types that start with the `NiAVObject` transform.
    private static var placedRootTypes: Set<String> {
        NIFNode.traversedTypes.union([NIFSwitchNode.typeName])
            .union(NIFFile.Flattener.shapeTypes)
    }
}
