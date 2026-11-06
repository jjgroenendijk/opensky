// Cell water: CELL overrides over WRLD defaults and parents, WATR colors, and
// one shared quad, cell-sized outside and room-sized inside. Sources: UESP CELL/WRLD/WATR and xEdit
// dev-4.1.6 wbDefinitionsTES5.pas.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd

nonisolated public struct WaterBuild {
    public let item: WaterDrawItem
    public let height: Float
}

nonisolated struct ResolvedWorldWater {
    let height: Float?
    let type: FormID?
}

nonisolated public enum WaterMeshBuilder: Sendable {
    /// Reusable local-space 4096x4096 quad, CCW from +Z.
    public static func cellPlane() -> Mesh {
        Mesh(
            name: "cell-water",
            transform: matrix_identity_float4x4,
            positions: [
                SIMD3(0, 0, 0),
                SIMD3(TerrainMeshBuilder.cellSize, 0, 0),
                SIMD3(TerrainMeshBuilder.cellSize, TerrainMeshBuilder.cellSize, 0),
                SIMD3(0, TerrainMeshBuilder.cellSize, 0)
            ],
            normals: [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3],
            materialSlot: 0
        )
    }
}

nonisolated extension CellSceneBuilder {
    /// Builds at most one water plane. CELL DATA has-water gates the feature;
    /// an explicit XCLW sentinel wins over every WRLD default.
    nonisolated public func buildWater(found: FoundCell, worldspace: Worldspace?) -> WaterBuild? {
        guard
            found.cell.flags.contains(.hasWater),
            let grid = found.cell.grid,
            let worldspace
        else { return nil }

        let worldWater = resolvedWorldWater(for: worldspace)
        let height: Float? = switch found.cell.waterHeight {
        case let .height(value): value.isFinite ? value : nil
        case .noWater: nil
        case nil: worldWater.height
        }
        guard let height, height.isFinite else { return nil }

        let look = resolvedWaterLook(for: found.cell.waterType ?? worldWater.type)
        guard let mesh = sharedWaterPlane() else { return nil }

        let origin = SIMD3<Float>(
            Float(grid.x) * TerrainMeshBuilder.cellSize,
            Float(grid.y) * TerrainMeshBuilder.cellSize,
            height
        )
        let transform = MatrixMath.translation(origin)
        let localBounds = ModelBounds(
            min: .zero,
            max: SIMD3(TerrainMeshBuilder.cellSize, TerrainMeshBuilder.cellSize, 0)
        )
        var item = WaterDrawItem(
            mesh: mesh,
            modelMatrix: transform,
            look: look,
            bounds: localBounds.transformed(by: transform)
        )
        if look.shading.flowMapped {
            item.flowMap = flowMapPath(x: grid.x, y: grid.y)
        }
        return WaterBuild(item: item, height: height)
    }

    /// The per-cell flow map sits under the folder of the plugin that made it; the
    /// latest plugin with a file wins.
    nonisolated func flowMapPath(x: Int32, y: Int32) -> String? {
        guard let fileSystem else { return nil }
        for name in loadOrderPlugins.reversed().map(\.name) {
            let path = "textures\\water\\\(name.lowercased())\\flow.\(x).\(y).dds"
            if fileSystem.exists(path) {
                return path
            }
        }
        return nil
    }

    /// An interior has no grid, so its plane spans the XY bounds of the placed
    /// geometry plus a margin. Every vanilla interior stores the editor default 0, and
    /// draws its water as placed meshes, so 0 draws nothing (docs/engine/sky-water.md).
    nonisolated public func buildInteriorWater(
        found: FoundCell,
        instances: [ResolvedInstance]
    ) -> WaterBuild? {
        guard
            found.cell.isInterior, found.cell.flags.contains(.hasWater),
            case let .height(height)? = found.cell.waterHeight,
            height.isFinite, height != 0,
            let placed = placedBounds(instances, waterSurfaces: false),
            placed.min.z < height, height < placed.max.z,
            !placedWaterSurface(instances, isAt: height),
            let mesh = sharedWaterPlane()
        else { return nil }
        let margin = SIMD2<Float>(repeating: Self.interiorWaterMargin)
        let lower = SIMD2(placed.min.x, placed.min.y) - margin
        let size = SIMD2(placed.max.x, placed.max.y) + margin - lower
        let origin = SIMD3(lower, height)
        let transform = MatrixMath.translation(origin) * float4x4(diagonal: SIMD4(
            size.x / TerrainMeshBuilder.cellSize, size.y / TerrainMeshBuilder.cellSize, 1, 1
        ))
        return WaterBuild(
            item: WaterDrawItem(
                mesh: mesh,
                modelMatrix: transform,
                look: resolvedWaterLook(for: found.cell.waterType),
                bounds: ModelBounds(min: origin, max: origin + SIMD3(size, 0))
            ),
            height: height
        )
    }

    /// Walls sit at the geometry's edge; a short overlap hides the seam behind them.
    nonisolated static let interiorWaterMargin: Float = 64

    nonisolated private func placedBounds(
        _ instances: [ResolvedInstance],
        waterSurfaces: Bool
    ) -> ModelBounds? {
        var result: ModelBounds?
        for instance in instances where Self.drawsWater(instance) == waterSurfaces {
            guard
                let local = meshes.bounds(forPath: instance.modelPath, surface: instance.surface)
            else { continue }
            let world = local.transformed(by: instance.transform)
            result = result.map { $0.union(world) } ?? world
        }
        return result
    }

    /// A placed water mesh at the cell height already draws that surface.
    nonisolated private func placedWaterSurface(
        _ instances: [ResolvedInstance],
        isAt height: Float
    ) -> Bool {
        instances.contains { instance in
            guard
                Self.drawsWater(instance),
                let local = meshes.bounds(forPath: instance.modelPath, surface: instance.surface)
            else { return false }
            let world = local.transformed(by: instance.transform)
            return world.min.z - 1 <= height && height <= world.max.z + 1
        }
    }

    nonisolated private static func drawsWater(_ instance: ResolvedInstance) -> Bool {
        instance.model.materials.contains(where: \.waterSurface)
    }

    /// The cached 4096 x 4096 quad every water plane scales and moves.
    nonisolated func sharedWaterPlane() -> RenderMesh? {
        if let waterPlaneMesh {
            return waterPlaneMesh
        }
        do {
            let uploaded = try meshes.renderMesh(WaterMeshBuilder.cellPlane())
            waterPlaneMesh = uploaded
            return uploaded
        } catch {
            Self.logger.warning("water plane upload failed, skipped")
            return nil
        }
    }

    /// The water height follows the land flag and the water type the water flag.
    nonisolated func resolvedWorldWater(
        for worldspace: Worldspace
    ) -> ResolvedWorldWater {
        let worlds = worldspaceIndexBuildingIfNeeded()
        return ResolvedWorldWater(
            height: worldspace.source(of: .useLandData, in: worlds).defaultWaterHeight,
            type: worldspace.source(of: .useWaterData, in: worlds).waterType
        )
    }

    nonisolated func worldspaceIndexBuildingIfNeeded() -> [UInt32: Worldspace] {
        if let worldspaceIndex {
            return worldspaceIndex
        }
        let index = loadOrderRecords(of: "WRLD") { try Worldspace(record: $0, localized: $1) }
        worldspaceIndex = index
        return index
    }

    nonisolated func waterTypeIndexBuildingIfNeeded() -> [UInt32: WaterType] {
        if let waterTypeIndex {
            return waterTypeIndex
        }
        let index = loadOrderRecords(of: "WATR") { record, _ in try WaterType(record: record) }
        waterTypeIndex = index
        return index
    }

    /// Plausible fallback keeps water visible when XCWT/NAM2 is absent or a
    /// mod carries an unknown WATR DNAM variant.
    nonisolated func resolvedWaterLook(for formID: FormID?) -> WaterLook {
        guard
            let formID,
            let water = waterTypeIndexBuildingIfNeeded()[formID.rawValue],
            let colors = water.colors
        else { return .fallback }
        var look = WaterLook(
            shallowColor: colors.shallow,
            deepColor: colors.deep,
            reflectionColor: colors.reflection,
            shading: water.surface.map { Self.shading($0, details: water.details) } ?? .standard
        )
        look.underwaterImageSpace = water.details.imageSpace
        return look
    }

    nonisolated private static func shading(
        _ surface: WaterSurfaceFields,
        details: WaterDetails
    ) -> WaterShading {
        let velocity = details.linearVelocity ?? .zero
        var shading = WaterShading(
            opacity: Float(min(details.opacity ?? 30, 100)) / 100,
            fresnelAmount: surface.fresnelAmount,
            reflectivity: surface.reflectivity,
            sunSpecularPower: surface.sunSpecularPower,
            sunSpecularMagnitude: surface.sunSpecularMagnitude,
            fogNear: surface.fogNear,
            fogFar: surface.fogFar,
            windDirections: surface.windDirections,
            windSpeeds: surface.windSpeeds,
            uvScales: surface.uvScales,
            amplitudes: surface.amplitudes,
            flowVelocity: SIMD2(velocity.x, velocity.y)
        )
        shading.noiseTextures = details.noiseTextures.prefix(3).map { $0 ?? "" }
        shading.flowMapped = details.flags & 0x08 != 0
        shading.flowNoiseTexture = details.noiseTextures.count > 3 ? details
            .noiseTextures[3] ?? "" : ""
        shading.flowMapScale = surface.flowMapScale
        shading.sunSparkleMagnitude = surface.sunSparkleMagnitude
        shading.sunSparklePower = surface.sunSparklePower
        shading.refractionMagnitude = surface.refractionMagnitude
        shading.noiseFalloff = max(surface.noiseFalloff, 0)
        let rings = surface.displacement
        shading.displacement = SIMD4(
            rings.startingSize,
            rings.force,
            rings.velocity,
            rings.dampener
        )
        shading.displacementFalloff = rings.falloff
        shading.underwaterFog = SIMD3(
            surface.underwaterFogNear, surface.underwaterFogFar, surface.underwaterFogAmount
        )
        return shading
    }
}
