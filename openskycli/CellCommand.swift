// `cell`: summarize one exterior cell without touching Metal — WRLD tree
// walk mirroring CellSceneBuilder (UESP "Skyrim Mod:Mod File Format" —
// Groups; docs/engine/cell-scene.md), REFR collection, base-object type
// histogram via a headers-only FormID index. Defaults to the first-render
// cell (docs/decisions/first-render-cell.md).

import Foundation

enum CellCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        let listRefs = scanner.flag("--refs")
        try scanner.finish()

        let file = try context.loadSkyrimESM()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        guard let world = worldChildren(editorID: worldspace, file: file, localized: localized)
        else {
            throw CLIError.failure("worldspace \(worldspace) not found")
        }
        guard let found = findCell(in: world, x: gridX, y: gridY, localized: localized) else {
            throw CLIError.failure("no cell at (\(gridX),\(gridY)) in \(worldspace)")
        }

        let name = found.cell.editorID ?? "cell \(FormID(found.formID))"
        print("[INFO] \(name) (\(gridX),\(gridY)) — CELL \(FormID(found.formID)), "
            + (found.cell.isInterior ? "interior" : "exterior"))
        summarize(found: found, file: file, listRefs: listRefs)
    }

    private static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }

    // MARK: - WRLD tree walk (read-only mirror of CellSceneBuilder)

    private static func worldChildren(
        editorID: String,
        file: ESMFile,
        localized: Bool
    ) -> ESMGroup? {
        guard let top = file.topGroup(of: "WRLD"), let children = try? top.children() else {
            return nil
        }
        var matchedFormID: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
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

    private struct FoundCell {
        let cell: Cell
        let formID: UInt32
        let children: ESMGroup?
    }

    /// Depth-first over exterior (sub-)blocks; match by decoded XCLC grid,
    /// never block labels (unreliable — see ESMGroup).
    private static func findCell(
        in group: ESMGroup,
        x: Int32,
        y: Int32,
        localized: Bool
    ) -> FoundCell? {
        guard let children = try? group.children() else { return nil }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
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

    // MARK: - Summary

    private static func summarize(found: FoundCell, file: ESMFile, listRefs: Bool) {
        var refs: [PlacedReference] = []
        var otherTypes: [String: Int] = [:]
        var deleted = 0
        var malformed = 0
        forEachCellRecord(in: found.children) { record in
            guard record.type == "REFR" else {
                otherTypes[record.type.description, default: 0] += 1
                return
            }
            guard !record.isDeleted else {
                deleted += 1
                return
            }
            do {
                try refs.append(PlacedReference(record: record))
            } catch {
                malformed += 1
            }
        }

        let typeIndex = ESMWalk.recordTypeIndex(in: file)
        var baseTypes: [String: Int] = [:]
        for ref in refs {
            baseTypes[baseType(of: ref, in: typeIndex), default: 0] += 1
        }

        print("[INFO] \(refs.count) placed refs"
            + (deleted > 0 ? ", \(deleted) deleted" : "")
            + (malformed > 0 ? ", \(malformed) malformed" : ""))
        print("base types: \(histogram(baseTypes))")
        if !otherTypes.isEmpty {
            print("other cell records: \(histogram(otherTypes))")
        }
        guard listRefs else { return }
        for ref in refs {
            let type = baseType(of: ref, in: typeIndex)
            let position = ref.placement.position
            print("  REFR \(ref.formID) base \(ref.base) [\(type)] at "
                + "(\(position.x), \(position.y), \(position.z))")
        }
    }

    private static func baseType(
        of ref: PlacedReference,
        in typeIndex: [UInt32: FourCC]
    ) -> String {
        guard let type = typeIndex[ref.base.rawValue] else { return "unresolved" }
        return type.description
    }

    /// Records inside the cell's persistent + temporary children groups.
    private static func forEachCellRecord(
        in cellChildren: ESMGroup?,
        _ body: (ESMRecord) -> Void
    ) {
        guard let cellChildren, let children = try? cellChildren.children() else { return }
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren
                || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records {
                body(record)
            }
        }
    }

    private static func histogram(_ counts: [String: Int]) -> String {
        counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
    }
}
