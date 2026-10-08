// `cell`: summarize one exterior cell without touching Metal — WRLD tree
// walk mirroring CellSceneBuilder (UESP "Skyrim Mod:Mod File Format" —
// Groups; docs/engine/cell-scene.md), REFR collection, base-object type
// histogram via a headers-only FormID index. Defaults to the first-render
// cell (docs/decisions/first-render-cell.md).

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorld

enum CellCommand {
    static func run(context: CLIContext, arguments: CellArguments) throws {
        let worldspace = arguments.grid.worldspace
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(arguments.grid.x, name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(arguments.grid.y, name: "--y") ?? FirstRenderCell.gridY
        let listRefs = arguments.refs

        let file = try context.loadSkyrimESM()
        let localized = file.isLocalized
        guard
            let world = CLIWorldTreeWalk.worldChildren(
                editorID: worldspace,
                file: file,
                localized: localized
            )
        else {
            throw CLIError.failure("worldspace \(worldspace) not found")
        }
        guard
            let found = CLIWorldTreeWalk.findCell(
                in: world,
                x: gridX,
                y: gridY,
                localized: localized
            )
        else {
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

    // MARK: - Summary

    private static func summarize(
        found: CLIWorldTreeWalk.FoundCell,
        file: ESMFile,
        listRefs: Bool
    ) {
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
        guard let cellChildren, let children = childrenOrWarn(cellChildren) else { return }
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren
                || group.kind == .cellTemporaryChildren,
                let records = childrenOrWarn(group)
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
