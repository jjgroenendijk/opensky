// What a worldspace's terrain LOD textures show for each cell, to fit how much they
// were brightened (TerrainLODBrightness). The 4 x 4 mip of a level-4 texture holds
// one texel per cell, with the north row first.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyImageKernels

nonisolated extension DistantLODSelection {
    /// Level-4 block origins spread evenly over the LOD area, at most `maximum` of them,
    /// so the fit does not depend on where the player enters the worldspace.
    public static func brightnessSampleOrigins(
        settings: LODSettings,
        maximum: Int
    ) -> [CellCoordinate] {
        let blocksPerSide = max(Int(settings.stride) / 4, 1)
        let perSide = max(Int(Double(maximum).squareRoot()), 1)
        let step = max((blocksPerSide + perSide - 1) / perSide, 1)
        var origins: [CellCoordinate] = []
        for column in stride(from: step / 2, to: blocksPerSide, by: step) {
            for row in stride(from: step / 2, to: blocksPerSide, by: step) {
                origins.append(CellCoordinate(
                    x: settings.origin.x + Int32(column * 4),
                    y: settings.origin.y + Int32(row * 4)
                ))
            }
        }
        return origins
    }
}

nonisolated extension DistantLODBuilder {
    /// Nil when the worldspace has no `lodsettings` file.
    public func brightnessSampleOrigins(worldspace: String, maximum: Int) -> [CellCoordinate]? {
        guard let settings = try? settings(worldspace: worldspace) else { return nil }
        return DistantLODSelection.brightnessSampleOrigins(settings: settings, maximum: maximum)
    }

    /// Mean gamma colour of each cell of a level-4 terrain block; empty when the
    /// texture is missing or cannot be decoded on the CPU.
    public func terrainTexelColours(
        worldspace: String,
        blockOrigin: CellCoordinate
    ) -> [CellCoordinate: SIMD3<Float>] {
        let key = worldspace.lowercased()
        let path = "textures\\terrain\\\(key)\\\(key).4.\(blockOrigin.x).\(blockOrigin.y).dds"
        guard
            let data = try? fileSystem.contents(forPath: path),
            let image = try? DDSDecoder.smallLevel(data, edge: 4),
            image.width == 4, image.height == 4
        else { return [:] }
        return Self.cellColours(image, blockOrigin: blockOrigin)
    }

    static func cellColours(
        _ image: DecodedImage,
        blockOrigin: CellCoordinate
    ) -> [CellCoordinate: SIMD3<Float>] {
        var colours: [CellCoordinate: SIMD3<Float>] = [:]
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                let index = (row * 4 + column) * 4
                let texel = SIMD3<Float>(
                    Float(image.rgba[index]), Float(image.rgba[index + 1]),
                    Float(image.rgba[index + 2])
                ) / 255
                let cell = CellCoordinate(
                    x: blockOrigin.x + Int32(column), y: blockOrigin.y + Int32(3 - row)
                )
                colours[cell] = texel
            }
        }
        return colours
    }
}
