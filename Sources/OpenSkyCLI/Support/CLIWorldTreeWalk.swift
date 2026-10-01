// Read-only WRLD tree walk that mirrors `CellSceneBuilder` (UESP "Skyrim Mod:Mod
// File Format" - Groups; docs/engine/cell-scene.md).

import OpenSkyFormatsCore
import OpenSkyFormatsESM

enum CLIWorldTreeWalk {
    struct FoundCell {
        let cell: Cell
        let formID: UInt32
        let children: ESMGroup?
    }

    /// The world-children group of the WRLD record named `editorID`.
    static func worldChildren(
        editorID: String,
        file: ESMFile,
        localized: Bool
    ) -> ESMGroup? {
        guard let top = file.topGroup(of: "WRLD"), let children = childrenOrWarn(top) else {
            return nil
        }
        var matchedFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = decodeOrWarn(record) { try Worldspace(record: $0, localized: localized)
                }
                matchedFormID = world?.editorID == editorID ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                return group
            default:
                break
            }
        }
        return nil
    }

    /// Depth-first over exterior (sub-)blocks. Matches the decoded XCLC grid,
    /// because block labels are unreliable (see `ESMGroup`). Skips the
    /// persistent CELL, which also carries XCLC (0,0).
    static func findCell(
        in group: ESMGroup,
        x: Int32,
        y: Int32,
        localized: Bool
    ) -> FoundCell? {
        guard let children = childrenOrWarn(group) else { return nil }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL" && group.kind != .worldChildren:
                guard
                    let cell = decodeOrWarn(
                        record,
                        using: { try Cell(record: $0, localized: localized) }
                    ),
                    let grid = cell.grid, grid.x == x, grid.y == y
                else { continue }
                let children = cellChildren(following: index, in: children, formID: record.formID)
                return FoundCell(cell: cell, formID: record.formID, children: children)
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                if let found = findCell(in: sub, x: x, y: y, localized: localized) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    /// The worldspace persistent CELL: the CELL stored directly in the world
    /// children group, not in a block.
    static func persistentCell(in worldChildren: ESMGroup, localized: Bool) -> FoundCell? {
        guard let children = childrenOrWarn(worldChildren) else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                let cell = decodeOrWarn(
                    record,
                    using: { try Cell(record: $0, localized: localized) }
                )
            else { continue }
            let children = cellChildren(following: index, in: children, formID: record.formID)
            return FoundCell(cell: cell, formID: record.formID, children: children)
        }
        return nil
    }

    /// The cell-children group sits after its CELL among the same siblings,
    /// labeled with the cell's FormID.
    private static func cellChildren(
        following index: Int,
        in children: [ESMGroup.Child],
        formID: UInt32
    ) -> ESMGroup? {
        for case let .group(sub) in children[(index + 1)...] where sub.kind == .cellChildren {
            if sub.parentFormID == formID {
                return sub
            }
        }
        return nil
    }
}
