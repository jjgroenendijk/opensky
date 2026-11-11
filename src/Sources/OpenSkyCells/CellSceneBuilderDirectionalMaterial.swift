// A static's directional material (STAT DNAM): its MATO record, and the textures of the
// MATO's own model, as a surface override (docs/rendering/surface-shading.md).

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

/// The `MATO` records, and each directional material once resolved.
nonisolated struct DirectionalMaterialCache {
    var index: [UInt32: MaterialObject]?
    var resolved: [String: ProjectedMaterial?] = [:]
}

nonisolated extension CellObjectBuilder {
    /// The base's MODS textures, with its directional material laid over them.
    nonisolated public func surface(for base: ResolvedBase) -> ModelSurfaceOverride {
        let alternates = owner.recordIndex.surface(for: base.alternateTextures)
        guard let projected = base.directionalMaterial.flatMap(projectedMaterial(for:)) else {
            return alternates
        }
        return ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil, shapes: alternates.shapes,
            projected: projected
        )
    }

    /// Nil when the `MATO` is missing or has no `DATA`.
    nonisolated func projectedMaterial(
        for directional: StaticObject.DirectionalMaterial
    ) -> ProjectedMaterial? {
        guard let id = directional.material else { return nil }
        let key = "\(id.rawValue):\(directional.maxAngle)"
        if let known = owner.directionalMaterials.resolved[key] {
            return known
        }
        let index = owner.directionalMaterials.index ?? owner.recordIndex
            .loadOrderRecords(of: "MATO") { record, _ in
                try MaterialObject(record: record)
            }
        owner.directionalMaterials.index = index
        var projected: ProjectedMaterial?
        if let object = index[id.rawValue], let properties = object.properties {
            let singlePass = properties.isSinglePass ?? false
            projected = ProjectedMaterial(
                diffuseTexture: singlePass
                    ? Self.projectedDiffusePath
                    : modelTextures(path: object.model?.path)?.diffuseTexture,
                noiseTexture: Self.projectedNoisePath,
                direction: singlePass ? SIMD3(0, 0, 1) : properties.projectionVector,
                maxAngle: directional.maxAngle,
                falloffScale: properties.falloffScale,
                falloffBias: properties.falloffBias,
                noiseUVScale: properties.noiseUVScale,
                materialUVScale: properties.materialUVScale,
                singlePassColor: properties.singlePassColor ?? SIMD3(1, 1, 1),
                singlePass: singlePass,
                isSnow: properties.isSnow ?? false
            )
        }
        owner.directionalMaterials.resolved[key] = .some(projected)
        return projected
    }

    /// A single-pass material draws these shared maps, projected straight down; its
    /// model is a placeholder (docs/rendering/surface-shading.md).
    nonisolated static let projectedDiffusePath = "textures\\effects\\projecteddiffuse.dds"
    nonisolated static let projectedNoisePath = "textures\\effects\\projectednoise.dds"

    /// The first textured material of a model, read straight from its NIF.
    private func modelTextures(path: String?) -> Material? {
        guard
            let path, let fileSystem = owner.fileSystem,
            let key = attempt({ try owner.meshes.meshKey(for: path) }),
            let data = attempt({ try fileSystem.contents(forPath: key) }),
            let model = attempt({ try NIFFile(data: data).model() })
        else { return nil }
        return model.materials.first { $0.diffuseTexture != nil }
    }
}
