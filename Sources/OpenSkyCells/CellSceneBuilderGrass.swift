// Cell grass: LAND LTEX -> GNAM -> GRAS, deterministic CPU placements, shared
// models, and GPU batch inputs that live as long as the cell.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering

nonisolated public struct GrassBuild {
    public let placements: [GrassPlacement]
    public let renderPlacements: [GrassRenderPlacement]
    public let typeCount: Int
    public let typeSkipCount: Int
}

nonisolated extension CellSceneBuilder {
    nonisolated public func buildGrass(
        found: FoundCell,
        worldspace: Worldspace?,
        terrain: TerrainBuild?,
        waterHeight: Float?
    ) -> GrassBuild? {
        guard
            worldspace?.flags.contains(.noGrass) != true,
            let terrain,
            let land = landRecord(in: found)
        else { return nil }

        let textures = landTextureIndexBuildingIfNeeded()
        let grasses = grassIndexBuildingIfNeeded()
        let usedTextureIDs = Set(
            land.baseTextures.map(\.texture.rawValue)
                + land.layers.map(\.texture.rawValue)
        )
        var referencedGrassIDs = Set<UInt32>()
        for textureID in usedTextureIDs {
            guard let texture = textures[textureID] else { continue }
            referencedGrassIDs.formUnion(texture.grasses.map(\.rawValue))
        }
        guard !referencedGrassIDs.isEmpty else { return nil }

        let usable = referencedGrassIDs.filter { grassID in
            guard let grass = grasses[grassID] else { return false }
            return grass.modelPath != nil && grass.placement != nil
        }
        let placements = GrassPlacementBuilder.placements(
            land: land,
            heightField: terrain.heightField,
            landTextures: textures,
            grasses: grasses,
            waterHeight: waterHeight
        )
        let skipped = referencedGrassIDs.count - usable.count
        if skipped > 0 {
            Self.logger.warning("\(skipped) referenced grass types unresolvable, dropped")
        }
        let renderPlacements = makeGrassRenderPlacements(placements)
        return GrassBuild(
            placements: placements,
            renderPlacements: renderPlacements,
            typeCount: usable.count,
            typeSkipCount: skipped
        )
    }

    /// Loads each GRAS model once through MeshLibrary, then expands every
    /// deterministic CPU placement into renderer input. One malformed/missing
    /// model drops only that grass type; other cell geometry stays valid.
    nonisolated private func makeGrassRenderPlacements(
        _ placements: [GrassPlacement]
    ) -> [GrassRenderPlacement] {
        let byType = Dictionary(grouping: placements, by: \.grass)
        var result: [GrassRenderPlacement] = []
        result.reserveCapacity(placements.count)
        for grassID in byType.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let typePlacements = byType[grassID], let first = typePlacements.first else {
                continue
            }
            do {
                let model = try meshes.model(path: first.modelPath)
                let bounds = meshes.bounds(forPath: first.modelPath)
                result += typePlacements.map {
                    GrassRenderPlacement(placement: $0, model: model, modelBounds: bounds)
                }
            } catch {
                let id = grassID.description
                let reason = String(describing: error)
                Self.logger.warning(
                    "grass \(id, privacy: .public) model failed: \(reason, privacy: .public)"
                )
            }
        }
        return result
    }

    nonisolated func landTextureIndexBuildingIfNeeded() -> [UInt32: LandTexture] {
        if let landTextureIndex {
            return landTextureIndex
        }
        let textures = loadOrderRecords(of: "LTEX") { record, _ in try LandTexture(record: record) }
        let index = LandTexture.index(textures.sorted { $0.key < $1.key }.map(\.value))
        landTextureIndex = index
        return index
    }

    nonisolated private func grassIndexBuildingIfNeeded() -> [UInt32: Grass] {
        if let grassIndex {
            return grassIndex
        }
        let index = loadOrderRecords(of: "GRAS") { record, _ in try Grass(record: record) }
        grassIndex = index
        return index
    }
}
