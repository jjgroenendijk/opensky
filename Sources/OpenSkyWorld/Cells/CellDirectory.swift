// Finds a cell by editor ID for a console-style `coc`. An exterior cell gives
// its grid. An interior gives a door elsewhere that leads in, because the door
// transition path is how an interior is built and entered. Pure: file in,
// value out, so it runs off the main actor.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum CellDirectoryEntry: Equatable, Sendable {
    /// `entryDoor` is a door REFR whose teleport ends inside the cell; nil
    /// when the cell has no teleport door at all.
    case interior(cell: FormID, entryDoor: FormID?)
    case exterior(cell: FormID, grid: CellCoordinate)
}

nonisolated public enum CellDirectory {
    /// Interior cells live under the CELL top group, exterior ones under WRLD.
    public static func find(editorID: String, in file: ESMFile) -> CellDirectoryEntry? {
        let wanted = editorID.lowercased()
        for type: FourCC in ["CELL", "WRLD"] {
            guard let top = file.topGroup(of: type), let children = try? top.children() else {
                continue
            }
            if let entry = search(children, wanted: wanted, localized: file.isLocalized) {
                return entry
            }
        }
        return nil
    }

    private static func search(
        _ children: [ESMGroup.Child],
        wanted: String,
        localized: Bool
    ) -> CellDirectoryEntry? {
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    ESMWalk.editorID(of: record)?.lowercased() == wanted,
                    let cell = try? Cell(record: record, localized: localized)
                else { continue }
                return entry(for: cell, childrenAfter: index, in: children)
            case let .group(group):
                guard let nested = try? group.children() else { continue }
                if let entry = search(nested, wanted: wanted, localized: localized) {
                    return entry
                }
            case .record:
                continue
            }
        }
        return nil
    }

    private static func entry(
        for cell: Cell,
        childrenAfter index: Int,
        in siblings: [ESMGroup.Child]
    ) -> CellDirectoryEntry {
        if !cell.isInterior, let grid = cell.grid {
            return .exterior(cell: cell.formID, grid: CellCoordinate(x: grid.x, y: grid.y))
        }
        let next = siblings.index(after: index)
        guard
            siblings.indices.contains(next),
            case let .group(group) = siblings[next],
            group.parentFormID == cell.formID.rawValue
        else { return .interior(cell: cell.formID, entryDoor: nil) }
        return .interior(cell: cell.formID, entryDoor: firstReturnDoor(in: group))
    }

    /// A door inside the cell teleports out to its partner, and the partner's
    /// teleport leads back in. So the partner is the way in.
    private static func firstReturnDoor(in group: ESMGroup) -> FormID? {
        var found: FormID?
        visitReferences(in: group) { record in
            guard found == nil else { return false }
            guard
                let reference = try? PlacedReference(record: record),
                let destination = reference.teleportDestination
            else { return true }
            found = destination.door
            return false
        }
        return found
    }

    private static func visitReferences(in group: ESMGroup, _ body: (ESMRecord) -> Bool) {
        guard let children = try? group.children() else { return }
        for child in children {
            switch child {
            case let .record(record) where record.type == "REFR":
                guard body(record) else { return }
            case let .group(nested):
                visitReferences(in: nested, body)
            case .record:
                continue
            }
        }
    }
}
