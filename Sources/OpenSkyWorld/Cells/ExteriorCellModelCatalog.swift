// Model paths of one exterior cell without Metal, for tooling. Same WRLD ->
// CELL -> REFR -> base chain as CellSceneBuilder (UESP WRLD, CELL, REFR, STAT).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

/// Canonical mesh VFS keys, and the records the walk could not decode.
nonisolated public struct ExteriorCellModels: Equatable, Sendable {
    public let paths: [String]
    public let skippedRecords: SkippedRecords
}

nonisolated public struct ExteriorCellModelCatalog: Sendable {
    public let file: ESMFile

    public func modelPaths(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> [String] {
        try models(worldspaceEditorID: worldspaceEditorID, gridX: gridX, gridY: gridY).paths
    }

    public func models(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> ExteriorCellModels {
        let localized = file.isLocalized
        var skipped = SkippedRecords()
        let world = try worldChildren(
            editorID: worldspaceEditorID, localized: localized, skipped: &skipped
        )
        let found = findCell(
            in: world, x: gridX, y: gridY, localized: localized, skipped: &skipped
        )
        guard let cell = found else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        let bases = baseModelPaths(skipped: &skipped)
        var paths: Set<String> = []
        for record in references(in: cell.children, skipped: &skipped) {
            guard
                !record.isDeleted,
                let ref = skipped.decode(record, using: PlacedReference.init(record:))
            else { continue }
            guard let rawPath = bases[ref.base.rawValue], let rawPath else { continue }
            if let normalized = try? VirtualFileSystem.normalize(rawPath) {
                let path = normalized.hasPrefix("meshes\\")
                    ? normalized
                    : "meshes\\" + normalized
                paths.insert(path)
            }
        }
        return ExteriorCellModels(paths: paths.sorted(), skippedRecords: skipped)
    }

    private struct FoundCell {
        let children: ESMGroup?
    }

    private func worldChildren(
        editorID: String,
        localized: Bool,
        skipped: inout SkippedRecords
    ) throws -> ESMGroup {
        guard let top = file.topGroup(of: "WRLD") else {
            throw CellSceneError.worldspaceNotFound(editorID: editorID)
        }
        var matchedFormID: UInt32?
        for child in try top.children() {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = skipped
                    .decode(record) { try Worldspace(record: $0, localized: localized) }
                matchedFormID = world?.editorID == editorID ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == matchedFormID:
                return group
            default:
                break
            }
        }
        throw CellSceneError.worldspaceNotFound(editorID: editorID)
    }

    private func findCell(
        in group: ESMGroup,
        x: Int32,
        y: Int32,
        localized: Bool,
        skipped: inout SkippedRecords
    ) -> FoundCell? {
        let children = skipped.children(of: group)
        for (index, child) in children.enumerated() {
            switch child {
            // A CELL directly in the world children is the persistent CELL, not grid (0,0).
            case let .record(record) where record.type == "CELL" && group.kind != .worldChildren:
                guard
                    let cell = skipped.decode(record, using: {
                        try Cell(record: $0, localized: localized)
                    }),
                    let grid = cell.grid,
                    grid.x == x,
                    grid.y == y
                else { continue }
                return FoundCell(children: cellChildren(
                    following: index,
                    in: children,
                    formID: record.formID
                ))
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                let found = findCell(
                    in: sub, x: x, y: y, localized: localized, skipped: &skipped
                )
                if let found {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    private func cellChildren(
        following index: Int,
        in children: [ESMGroup.Child],
        formID: UInt32
    ) -> ESMGroup? {
        for case let .group(group) in children[(index + 1)...] {
            if group.kind == .cellChildren, group.parentFormID == formID {
                return group
            }
        }
        return nil
    }

    private func references(
        in cellChildren: ESMGroup?,
        skipped: inout SkippedRecords
    ) -> [ESMRecord] {
        guard let cellChildren else { return [] }
        var references: [ESMRecord] = []
        for case let .group(group) in skipped.children(of: cellChildren) {
            guard group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren
            else { continue }
            for case let .record(record) in skipped.children(of: group)
                where record.type == "REFR"
            {
                references.append(record)
            }
        }
        return references
    }

    private func baseModelPaths(skipped: inout SkippedRecords) -> [UInt32: String?] {
        var result: [UInt32: String?] = [:]
        let localized = file.isLocalized
        if let top = file.topGroup(of: "STAT") {
            for case let .record(record) in skipped.children(of: top) where record.type == "STAT" {
                if let object = skipped.decode(record, using: StaticObject.init(record:)) {
                    result[record.formID] = object.modelPath
                }
            }
        }
        for type in ModelBase.supportedTypes {
            guard let top = file.topGroup(of: type) else { continue }
            for case let .record(record) in skipped.children(of: top) where record.type == type {
                let object = skipped.decode(record) {
                    try ModelBase(record: $0, localized: localized)
                }
                if let object {
                    result[record.formID] = object.modelPath
                }
            }
        }
        return result
    }
}
