// Terrain LOD blocks built from the load order instead of read from the vanilla files
// (docs/engine/distant-lod.md#generated-terrain).

public import Foundation
public import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd

/// One generated terrain block: its model and its two maps as DDS bytes.
nonisolated public struct GeneratedTerrainBlock: Sendable {
    public let model: Model
    public let diffuse: Data
    public let normal: Data

    public init(model: Model, diffuse: Data, normal: Data) {
        self.model = model
        self.diffuse = diffuse
        self.normal = normal
    }
}

/// Builds terrain blocks from the winning `LAND` records.
nonisolated public protocol TerrainLODGenerating: AnyObject {
    /// Nil when the worldspace has no land in the block.
    func terrainBlock(_ block: DistantLODBlock) -> GeneratedTerrainBlock?
}

nonisolated extension DistantLODBlock {
    /// Beside the vanilla file's path, so the two never share a cache entry.
    public var generatedMeshKey: String {
        generatedPath(path)
    }

    public var generatedDiffuseKey: String {
        generatedPath(path.replacingOccurrences(of: "meshes\\", with: "textures\\"))
            .replacingOccurrences(of: ".btr", with: ".dds")
    }

    public var generatedNormalKey: String {
        generatedDiffuseKey.replacingOccurrences(of: ".dds", with: "_n.dds")
    }

    private func generatedPath(_ path: String) -> String {
        guard let cut = path.lastIndex(of: "\\") else { return "generated\\" + path }
        return path[..<cut] + "\\generated" + path[cut...]
    }
}

nonisolated extension DistantLODBuilder {
    /// Nil when the generator has no land for the block; the vanilla file then draws.
    func generatedPlacement(
        for block: DistantLODBlock,
        terrain: any TerrainLODGenerating
    ) throws -> RenderPlacement? {
        let textures = textures
        guard
            let model = try meshes.model(
                generatedKey: block.generatedMeshKey, terrainLODClipMask: block.clipMask,
                make: {
                    guard let made = terrain.terrainBlock(block) else { return nil }
                    textures.register(
                        dds: made.diffuse,
                        key: block.generatedDiffuseKey,
                        usage: .color
                    )
                    textures.register(
                        dds: made.normal, key: block.generatedNormalKey, usage: .data
                    )
                    return made.model
                }
            )
        else { return nil }
        let transform = MatrixMath.translation(SIMD3(
            Float(block.origin.x) * TerrainMeshBuilder.cellSize,
            Float(block.origin.y) * TerrainMeshBuilder.cellSize,
            0
        ))
        let bounds = meshes.bounds(
            forPath: block.generatedMeshKey, terrainLODClipMask: block.clipMask
        )?.transformed(by: transform)
        return RenderPlacement(
            model: model,
            transform: transform,
            bounds: bounds,
            castsShadows: false,
            receivesPointLights: false,
            receivesShadows: false,
            layer: .distantLOD
        )
    }
}
