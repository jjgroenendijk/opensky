// Exterior water: CELL overrides over WRLD defaults and parents, WATR colors,
// and one shared cell-sized plane. Sources: UESP CELL/WRLD/WATR and xEdit
// dev-4.1.6 wbDefinitionsTES5.pas.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public struct WaterBuild {
    public let item: WaterDrawItem
    public let height: Float
}

nonisolated private struct ResolvedWorldWater {
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
        let mesh: RenderMesh
        do {
            if let waterPlaneMesh {
                mesh = waterPlaneMesh
            } else {
                let uploaded = try meshes.renderMesh(WaterMeshBuilder.cellPlane())
                waterPlaneMesh = uploaded
                mesh = uploaded
            }
        } catch {
            Self.logger.warning("water plane upload failed, skipped")
            return nil
        }

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
        return WaterBuild(
            item: WaterDrawItem(
                mesh: mesh,
                modelMatrix: transform,
                look: look,
                bounds: localBounds.transformed(by: transform)
            ),
            height: height
        )
    }

    /// Applies WRLD PNAM category inheritance recursively. Cycles are invalid
    /// mod data -> stop at the first repeated FormID, keeping local values.
    nonisolated private func resolvedWorldWater(
        for worldspace: Worldspace
    ) -> ResolvedWorldWater {
        resolvedWorldWater(for: worldspace, visited: [])
    }

    nonisolated private func resolvedWorldWater(
        for worldspace: Worldspace,
        visited: Set<UInt32>
    ) -> ResolvedWorldWater {
        guard !visited.contains(worldspace.formID.rawValue) else {
            return ResolvedWorldWater(
                height: worldspace.defaultWaterHeight,
                type: worldspace.waterType
            )
        }
        var nextVisited = visited
        nextVisited.insert(worldspace.formID.rawValue)
        let parent = worldspace.parent.flatMap {
            worldspaceIndexBuildingIfNeeded()[$0.rawValue]
        }
        let parentData = parent.map { resolvedWorldWater(for: $0, visited: nextVisited) }
        return ResolvedWorldWater(
            height: worldspace.parentFlags.contains(.useLandData)
                ? parentData?.height : worldspace.defaultWaterHeight,
            type: worldspace.parentFlags.contains(.useWaterData)
                ? parentData?.type : worldspace.waterType
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

    nonisolated private func waterTypeIndexBuildingIfNeeded() -> [UInt32: WaterType] {
        if let waterTypeIndex {
            return waterTypeIndex
        }
        let index = loadOrderRecords(of: "WATR") { record, _ in try WaterType(record: record) }
        waterTypeIndex = index
        return index
    }

    /// Plausible fallback keeps water visible when XCWT/NAM2 is absent or a
    /// mod carries an unknown WATR DNAM variant.
    nonisolated private func resolvedWaterLook(for formID: FormID?) -> WaterLook {
        guard
            let formID,
            let water = waterTypeIndexBuildingIfNeeded()[formID.rawValue],
            let colors = water.colors
        else { return .fallback }
        return WaterLook(
            shallowColor: colors.shallow,
            deepColor: colors.deep,
            reflectionColor: colors.reflection,
            shading: water.surface.map { Self.shading($0, details: water.details) } ?? .standard
        )
    }

    nonisolated private static func shading(
        _ surface: WaterSurfaceFields,
        details: WaterDetails
    ) -> WaterShading {
        let velocity = details.linearVelocity ?? .zero
        return WaterShading(
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
    }
}
