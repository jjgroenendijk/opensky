// Cached STAT/ModelBase indexes and the exterior build-source lookup.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics

nonisolated public struct ExteriorBuildSource: Sendable {
    public let world: FoundWorld
    public let cell: FoundCell
}

nonisolated extension CellSceneBuilder {
    nonisolated public func exteriorBuildSource(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> ExteriorBuildSource {
        let world = try worldChildrenGroup(
            editorID: worldspaceEditorID,
            localized: pluginLocalized
        )
        guard
            let found = findCell(
                in: world.children,
                gridX: gridX,
                gridY: gridY,
                localized: pluginLocalized
            ),
            let cell = loadOrderCell(formID: FormID(found.formID), base: found)
        else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        return ExteriorBuildSource(world: world, cell: cell)
    }

    /// Keyed in the load-order space, like the references that place them.
    nonisolated public func statIndexBuildingIfNeeded() -> [UInt32: StaticObject] {
        if let statIndex {
            return statIndex
        }
        let index = loadOrderRecords(of: "STAT") { record, _ in try StaticObject(record: record) }
        statIndex = index
        return index
    }

    /// TXST by FormID, for the MODS texture sets of placed models.
    nonisolated public func textureSetIndexBuildingIfNeeded() -> [UInt32: TextureSet] {
        if let textureSetIndex {
            return textureSetIndex
        }
        let index = loadOrderRecords(of: "TXST") { record, _ in try TextureSet(record: record) }
        textureSetIndex = index
        return index
    }

    /// MODS entries as per-shape textures. An entry whose TXST is missing keeps
    /// the shape's own textures.
    nonisolated public func surface(
        for alternates: [ModelData.AlternateTexture]
    ) -> ModelSurfaceOverride {
        guard !alternates.isEmpty else {
            return ModelSurfaceOverride(diffuseTexture: nil, normalTexture: nil, tint: nil)
        }
        let sets = textureSetIndexBuildingIfNeeded()
        let shapes = alternates.compactMap { alternate in
            sets[alternate.textureSet.rawValue].map { set in
                ModelSurfaceOverride.ShapeTextures(
                    shapeName: alternate.shapeName,
                    diffuseTexture: set.diffusePath.flatMap(NIFShaderTextureSet.vfsKey(for:)),
                    normalTexture: set.normalPath.flatMap(NIFShaderTextureSet.vfsKey(for:))
                )
            }
        }
        return ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil, shapes: shapes
        )
    }

    /// One cached index spans the six model-base top groups.
    nonisolated public func modelBaseIndexBuildingIfNeeded() -> [UInt32: ModelBase] {
        if let modelBaseIndex {
            return modelBaseIndex
        }
        var index: [UInt32: ModelBase] = [:]
        for type in ModelBase.supportedTypes {
            index.merge(loadOrderRecords(of: type) { record, localized in
                try ModelBase(record: record, localized: localized)
            }) { _, later in later }
        }
        modelBaseIndex = index
        return index
    }

    /// A plugin without MATT gets an empty index, so it is not rebuilt per cell.
    nonisolated public func materialTypeIndexBuildingIfNeeded() -> MaterialTypeIndex {
        if let materialTypeIndex {
            return materialTypeIndex
        }
        let index = MaterialTypeIndex(file: file)
        materialTypeIndex = index
        return index
    }

    nonisolated public func resolveBase(
        formID: UInt32,
        statIndex: [UInt32: StaticObject],
        modelBaseIndex: [UInt32: ModelBase]
    ) -> ResolvedBase? {
        if let stat = statIndex[formID] {
            return ResolvedBase(
                formID: stat.formID,
                recordType: "STAT",
                modelPath: stat.modelPath,
                isEditorMarker: stat.isEditorMarker,
                alternateTextures: stat.model?.alternateTextures ?? []
            )
        }
        if let base = modelBaseIndex[formID] {
            return ResolvedBase(
                formID: base.formID,
                recordType: base.recordType,
                modelPath: base.modelPath,
                isEditorMarker: base.isEditorMarker,
                alternateTextures: base.details.model?.alternateTextures ?? []
            )
        }
        return nil
    }
}
