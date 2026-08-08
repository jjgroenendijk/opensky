// Loading one real cell's terrain without a Metal device (issue #188).
//
// `CellSceneBuilder` needs a device to build a scene; the locomotion drive only
// needs the LAND heights, so it walks the WRLD tree straight to them. That is
// what keeps the acceptance test numeric and device-free. The heights come from
// the user's own install and never leave `logs/` (AGENTS.md "Legal & IP").

@testable import opensky
import simd

enum LocomotionRealTerrain {
    /// The launch cell's LAND heights as a walkable field, found by walking the
    /// WRLD tree directly so the test needs no Metal device.
    static func terrainField(root: GameDataRoot) -> TerrainHeightField? {
        guard
            let file = try? ESMFile(url: root.dataURL.appending(path: "Skyrim.esm")),
            let worlds = file.topGroup(of: "WRLD"),
            let children = try? worlds.children()
        else { return nil }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        var matchedFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
                matchedFormID = world?.editorID == FirstRenderCell.worldspaceEditorID
                    ? record.formID
                    : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                guard
                    let heights = land(in: group, localized: localized)?
                        .heightField?.heights
                else { return nil }
                return TerrainHeightField(
                    coordinate: CellCoordinate(
                        x: FirstRenderCell.gridX, y: FirstRenderCell.gridY
                    ),
                    heights: heights
                )
            default:
                break
            }
        }
        return nil
    }

    /// Depth-first for the LAND of the launch cell, matched on the decoded
    /// XCLC grid exactly as `CellSceneBuilder.findCell` matches it.
    static func land(in group: ESMGroup, localized: Bool) -> Land? {
        guard let children = try? group.children() else { return nil }
        var targetCellFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "CELL":
                let cell = try? Cell(record: record, localized: localized)
                let matches = cell?.grid.map {
                    $0.x == FirstRenderCell.gridX && $0.y == FirstRenderCell.gridY
                } ?? false
                targetCellFormID = matches ? record.formID : nil
            case let .group(sub):
                if
                    sub.kind == .cellChildren || sub.kind == .cellTemporaryChildren,
                    sub.parentFormID == targetCellFormID,
                    let found = landRecord(in: sub)
                {
                    return found
                }
                if let found = land(in: sub, localized: localized) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    /// The LAND record directly under one cell-children group.
    static func landRecord(in group: ESMGroup) -> Land? {
        guard let children = try? group.children() else { return nil }
        for child in children {
            switch child {
            case let .record(record) where record.type == "LAND":
                return try? Land(record: record)
            case let .group(sub):
                if let found = landRecord(in: sub) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    /// Cell centre, one capsule height above the terrain there.
    static func startPosition(on terrain: TerrainHeightField) -> SIMD3<Float> {
        let centre = SIMD2<Float>(
            (Float(FirstRenderCell.gridX) + 0.5) * TerrainMeshBuilder.cellSize,
            (Float(FirstRenderCell.gridY) + 0.5) * TerrainMeshBuilder.cellSize
        )
        let height = terrain.sample(at: centre)?.height ?? 0
        return SIMD3<Float>(centre.x, centre.y, height)
    }
}
