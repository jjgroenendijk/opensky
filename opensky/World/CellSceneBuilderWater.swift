// Milestone 3.5 exterior water build: resolve CELL overrides against WRLD
// defaults + parent inheritance, resolve WATR colors, upload/reuse one flat
// cell-sized plane, emit a blend-pipeline draw item. Parsing sources:
// UESP CELL/WRLD/WATR + xEdit dev-4.1.6 wbDefinitionsTES5.pas.

import Foundation
import OSLog
import simd

nonisolated struct WaterBuild {
    let item: WaterDrawItem
    let height: Float
}

nonisolated private struct ResolvedWorldWater {
    let height: Float?
    let type: FormID?
}

nonisolated enum WaterMeshBuilder {
    /// Reusable local-space 4096x4096 quad, CCW from +Z.
    static func cellPlane() -> Mesh {
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

extension CellSceneBuilder {
    /// Builds at most one water plane. CELL DATA has-water gates the feature;
    /// an explicit XCLW sentinel wins over every WRLD default.
    nonisolated func buildWater(found: FoundCell, worldspace: Worldspace?) -> WaterBuild? {
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

        let colors = resolvedColors(for: found.cell.waterType ?? worldWater.type)
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
                shallowColor: colors.shallow,
                deepColor: colors.deep,
                reflectionColor: colors.reflection,
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

    nonisolated private func worldspaceIndexBuildingIfNeeded() -> [UInt32: Worldspace] {
        if let worldspaceIndex {
            return worldspaceIndex
        }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        var index: [UInt32: Worldspace] = [:]
        if let top = file.topGroup(of: "WRLD"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "WRLD" {
                if let world = try? Worldspace(record: record, localized: localized) {
                    index[record.formID] = world
                }
            }
        }
        worldspaceIndex = index
        return index
    }

    nonisolated private func waterTypeIndexBuildingIfNeeded() -> [UInt32: WaterType] {
        if let waterTypeIndex {
            return waterTypeIndex
        }
        var index: [UInt32: WaterType] = [:]
        if let top = file.topGroup(of: "WATR"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "WATR" {
                if let water = try? WaterType(record: record) {
                    index[record.formID] = water
                }
            }
        }
        waterTypeIndex = index
        return index
    }

    /// Plausible fallback keeps water visible when XCWT/NAM2 is absent or a
    /// mod carries an unknown WATR DNAM variant.
    nonisolated private func resolvedColors(for formID: FormID?) -> WaterType.Colors {
        guard let formID else { return fallbackWaterColors() }
        guard let colors = waterTypeIndexBuildingIfNeeded()[formID.rawValue]?.colors else {
            return fallbackWaterColors()
        }
        return colors
    }

    nonisolated private func fallbackWaterColors() -> WaterType.Colors {
        WaterType.Colors(
            shallow: SIMD3(0.08, 0.32, 0.42),
            deep: SIMD3(0.015, 0.08, 0.16),
            reflection: SIMD3(0.42, 0.62, 0.78)
        )
    }
}
