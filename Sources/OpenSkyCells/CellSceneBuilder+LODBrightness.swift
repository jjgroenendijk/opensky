// Fits how much a worldspace's terrain LOD textures were brightened, from the
// worldspace's own LAND and LOD files, so a mod worldspace needs no table entry.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyImageKernels
import OpenSkyRendering
import OpenSkyTerrain

nonisolated extension CellSceneBuilder {
    /// About 1000 cells: enough for a stable median, cheap enough for the build queue.
    static let brightnessSampleBlocks = 64

    /// The vanilla curve when the worldspace has too few painted cells with LOD.
    nonisolated public func terrainLODBrightness(lodWorldspace: String) -> TerrainLODBrightness {
        let key = lodWorldspace.lowercased()
        if let cached = terrainLODBrightnessByWorld[key] {
            return cached
        }
        let curve = TerrainLODBrightness.fitted(samples: brightnessSamples(lodWorldspace))
        terrainLODBrightnessByWorld[key] = curve
        return curve
    }

    nonisolated private func brightnessSamples(_ worldspace: String) -> [SIMD2<Float>] {
        guard
            let builder = distantLODBuilder,
            let origins = builder.brightnessSampleOrigins(
                worldspace: worldspace, maximum: Self.brightnessSampleBlocks
            ),
            let world = try? worldChildrenGroup(editorID: worldspace, localized: pluginLocalized)
        else { return [] }
        var samples: [SIMD2<Float>] = []
        for origin in origins {
            let texels = builder.terrainTexelColours(worldspace: worldspace, blockOrigin: origin)
            for (cell, texel) in texels {
                guard
                    let found = findCell(
                        in: world, gridX: cell.x, gridY: cell.y, localized: pluginLocalized
                    ),
                    let land = landRecord(in: found),
                    let albedo = TerrainCellAlbedo.mean(land: land, textureMean: textureMean)
                else { continue }
                samples.append(SIMD2(
                    TerrainLODBrightness.luminance(albedo), TerrainLODBrightness.luminance(texel)
                ))
            }
        }
        return samples
    }

    /// Read from a small mip: its mean matches the full texture's to within a percent.
    nonisolated private func textureMean(_ ltexID: FormID) -> SIMD3<Float>? {
        guard let path = terrainTextureKeys(for: ltexID)?.diffuse else { return nil }
        if let cached = terrainTextureMeans[path] {
            return cached
        }
        let mean = distantLODBuilder.flatMap { builder in
            (try? builder.fileSystem.contents(forPath: path))
                .flatMap { try? DDSDecoder.smallLevel($0, edge: 4) }
                .map(Self.meanColour)
        }
        terrainTextureMeans[path] = .some(mean)
        return mean
    }

    nonisolated private static func meanColour(_ image: DecodedImage) -> SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        let count = image.width * image.height
        for index in 0 ..< count {
            sum += SIMD3<Float>(
                Float(image.rgba[index * 4]), Float(image.rgba[index * 4 + 1]),
                Float(image.rgba[index * 4 + 2])
            )
        }
        return sum / Float(max(count, 1)) / 255
    }
}
