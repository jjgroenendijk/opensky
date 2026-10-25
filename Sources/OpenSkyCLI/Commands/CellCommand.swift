// `cell`: summarize one cell without touching Metal. The cell comes from
// the whole load order: the last plugin that has the cell wins its record, and
// every plugin adds, overrides, or deletes references by load-order FormID
// (docs/engine/cell-scene.md#load-order). Defaults to the first-render cell.

import Foundation
import OpenSkyCells
import OpenSkyCLIArguments
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

enum CellCommand {
    static func run(context: CLIContext, arguments: CellArguments) throws {
        if let interior = arguments.cell {
            try runInterior(context: context, editorID: interior, listRefs: arguments.refs)
            return
        }
        let worldspace = arguments.grid.worldspace
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = arguments.grid.x ?? FirstRenderCell.gridX
        let gridY = arguments.grid.y ?? FirstRenderCell.gridY

        let loadOrder = try context.loadOrder().plugins
        var merged = MergedCell()
        var hasWorld = false
        for plugin in loadOrder.plugins {
            guard
                let world = CLIWorldTreeWalk.worldChildren(
                    editorID: worldspace, file: plugin.file, localized: plugin.localized
                )
            else { continue }
            hasWorld = true
            let found = plugin.decode {
                CLIWorldTreeWalk.findCell(
                    in: world, x: gridX, y: gridY, localized: plugin.localized
                )
            }
            if let found {
                merged.add(found, from: plugin)
            }
        }
        guard hasWorld else {
            throw CLIError.failure("worldspace \(worldspace) not found in the load order")
        }
        guard let winner = merged.winner else {
            throw CLIError.failure("no cell at (\(gridX),\(gridY)) in \(worldspace)")
        }

        let formID = winner.plugin.translation(FormID(stored: winner.found.formID))
        let name = winner.found.cell.editorID ?? "cell \(formID)"
        print("[INFO] \(name) (\(gridX),\(gridY)) — CELL \(formID), "
            + (winner.found.cell.isInterior ? "interior" : "exterior")
            + ", from \(winner.plugin.name)")
        summarize(merged, index: LoadOrderRecordIndex(loadOrder), listRefs: arguments.refs)
    }

    private static func runInterior(
        context: CLIContext, editorID: String, listRefs: Bool
    ) throws {
        let loadOrder = try context.loadOrder().plugins
        var merged = MergedCell()
        for plugin in loadOrder.plugins {
            let found = plugin.decode {
                CLIWorldTreeWalk.interiorCell(
                    editorID: editorID, file: plugin.file, localized: plugin.localized
                )
            }
            if let found {
                merged.add(found, from: plugin)
            }
        }
        guard let winner = merged.winner else {
            throw CLIError.failure("no interior cell \(editorID) in the load order")
        }
        let formID = winner.plugin.translation(FormID(stored: winner.found.formID))
        print("[INFO] \(editorID) — CELL \(formID), interior, from \(winner.plugin.name)")
        summarize(merged, index: LoadOrderRecordIndex(loadOrder), listRefs: listRefs)
    }

    // MARK: - Summary

    private static func summarize(
        _ merged: MergedCell,
        index: LoadOrderRecordIndex,
        listRefs: Bool
    ) {
        let refs = merged.references
        var baseTypes: [String: Int] = [:]
        for ref in refs {
            baseTypes[baseType(of: ref, in: index), default: 0] += 1
        }

        print("[INFO] \(refs.count) placed refs"
            + (merged.deleted > 0 ? ", \(merged.deleted) deleted" : "")
            + (merged.malformed > 0 ? ", \(merged.malformed) malformed" : ""))
        print("base types: \(histogram(baseTypes))")
        if !merged.otherTypes.isEmpty {
            print("other cell records: \(histogram(merged.otherTypes))")
        }
        guard listRefs else { return }
        for ref in refs {
            let type = baseType(of: ref, in: index)
            let position = ref.placement.position
            let name = index.record(withFormID: ref.base).flatMap {
                ESMWalk.editorID(of: $0.record)
            } ?? "-"
            print("  REFR \(ref.formID) base \(ref.base) \(name) [\(type)] at "
                + "(\(position.x), \(position.y), \(position.z))")
        }
    }

    private static func baseType(
        of ref: PlacedReference,
        in index: LoadOrderRecordIndex
    ) -> String {
        index.record(withFormID: ref.base)?.record.type.description ?? "unresolved"
    }

    private static func histogram(_ counts: [String: Int]) -> String {
        counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
    }
}

/// One cell gathered from every plugin that stores it, lowest priority first.
private struct MergedCell {
    struct Winner {
        let found: CLIWorldTreeWalk.FoundCell
        let plugin: LoadOrderPlugin
    }

    private(set) var winner: Winner?
    private(set) var otherTypes: [String: Int] = [:]
    private(set) var malformed = 0
    private var order: [FormID] = []
    private var known: Set<FormID> = []
    private var byID: [FormID: PlacedReference] = [:]
    private var deletedIDs: Set<FormID> = []

    var deleted: Int {
        deletedIDs.count
    }

    var references: [PlacedReference] {
        order.compactMap { byID[$0] }
    }

    mutating func add(_ found: CLIWorldTreeWalk.FoundCell, from plugin: LoadOrderPlugin) {
        winner = Winner(found: found, plugin: plugin)
        forEachCellRecord(in: found.children) { record in
            guard record.type == "REFR" else {
                otherTypes[record.type.description, default: 0] += 1
                return
            }
            let formID = plugin.formID(of: record)
            guard !record.isDeleted else {
                byID[formID] = nil
                deletedIDs.insert(formID)
                return
            }
            guard let ref = try? plugin.decode({ try PlacedReference(record: record) }) else {
                malformed += 1
                return
            }
            byID[formID] = ref
            if known.insert(formID).inserted {
                order.append(formID)
            }
            deletedIDs.remove(formID)
        }
    }

    /// Records inside the cell's persistent and temporary children groups.
    private func forEachCellRecord(in cellChildren: ESMGroup?, _ body: (ESMRecord) -> Void) {
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
}
