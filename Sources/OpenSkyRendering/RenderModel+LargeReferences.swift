// Object LOD keeps its large references apart, so the ring that draws their full models
// can hide them (docs/engine/distant-lod.md).

nonisolated extension RenderModel {
    /// The suffix of the merged shapes that hold an object LOD block's large references.
    public static let largeReferenceShapeSuffix = "-largeref"

    /// The model without its large-reference shapes; the same model when it has none.
    public func withoutLargeReferences() -> RenderModel {
        let kept = meshes.filter { mesh in
            !(mesh.name?.lowercased().hasSuffix(Self.largeReferenceShapeSuffix) ?? false)
        }
        guard kept.count != meshes.count else { return self }
        return RenderModel(meshes: kept, renderMaterials: materials)
    }
}
