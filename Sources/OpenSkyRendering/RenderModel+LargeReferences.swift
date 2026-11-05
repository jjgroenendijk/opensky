// Object LOD keeps its large references apart, so the ring that draws their full models
// can hide them (docs/engine/distant-lod.md).

import OpenSkyRenderResources

nonisolated extension RenderModel {
    /// The suffix of the merged shapes that hold an object LOD block's large references.
    public static let largeReferenceShapeSuffix = "-largeref"

    /// The model without the large-reference pieces whose segment `hides` names. A
    /// large-reference shape without segments goes whole.
    public func withoutLargeReferences(hidingSegment hides: (Int) -> Bool) -> RenderModel {
        let kept = meshes.filter { mesh in
            guard Self.isLargeReference(mesh) else { return true }
            return mesh.objectLODSegment.map { !hides($0) } ?? false
        }
        guard kept.count != meshes.count else { return self }
        return RenderModel(meshes: kept, renderMaterials: materials)
    }

    /// True when a large-reference shape has no segments, so it can only hide whole.
    public var hasUnsegmentedLargeReferences: Bool {
        meshes.contains { Self.isLargeReference($0) && $0.objectLODSegment == nil }
    }

    private static func isLargeReference(_ mesh: RenderMesh) -> Bool {
        mesh.name?.lowercased().hasSuffix(largeReferenceShapeSuffix) ?? false
    }
}
