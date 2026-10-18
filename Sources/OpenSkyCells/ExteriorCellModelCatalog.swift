// Model paths of one exterior cell without Metal, for tooling. Same WRLD ->
// CELL -> REFR -> base chain as CellSceneBuilder (UESP WRLD, CELL, REFR, STAT),
// over the whole load order: every plugin that stores the cell adds references.

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
    public let loadOrder: LoadOrderPlugins

    public init(loadOrder: LoadOrderPlugins) {
        self.loadOrder = loadOrder
    }

    /// One plugin read alone, for synthetic test fixtures.
    public init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

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
        var skipped = SkippedRecords()
        var hasWorld = false
        var hasCell = false
        var references: [FormID: PlacedReference] = [:]
        for plugin in loadOrder.plugins {
            guard
                let world = worldChildren(
                    editorID: worldspaceEditorID, in: plugin.file, skipped: &skipped
                )
            else { continue }
            hasWorld = true
            plugin.decode {
                guard
                    let cell = findCell(
                        in: world, x: gridX, y: gridY, localized: plugin.localized,
                        skipped: &skipped
                    )
                else { return }
                hasCell = true
                for record in self.references(in: cell.children, skipped: &skipped) {
                    let formID = FormID(record.formID)
                    guard !record.isDeleted else {
                        references[formID] = nil
                        continue
                    }
                    if let ref = skipped.decode(record, using: PlacedReference.init(record:)) {
                        references[formID] = ref
                    }
                }
            }
        }
        guard hasWorld
        else { throw CellSceneError.worldspaceNotFound(editorID: worldspaceEditorID) }
        guard hasCell else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        let bases = baseModelPaths(skipped: &skipped)
        var paths: Set<String> = []
        for ref in references.values {
            guard let rawPath = bases[ref.base.rawValue] else { continue }
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

    /// The world children group of the WRLD named `editorID` in one plugin.
    private func worldChildren(
        editorID: String,
        in file: ESMFile,
        skipped: inout SkippedRecords
    ) -> ESMGroup? {
        guard let top = file.topGroup(of: "WRLD") else { return nil }
        let localized = file.isLocalized
        var matchedFormID: UInt32?
        for child in skipped.children(of: top) {
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
        return nil
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

    /// Keyed by load-order FormID; a later plugin's base wins.
    private func baseModelPaths(skipped: inout SkippedRecords) -> [UInt32: String] {
        var result: [UInt32: String] = loadOrder.indexRecords(of: "STAT", skipped: &skipped) {
            try StaticObject(record: $0).modelPath
        }
        for type in ModelBase.supportedTypes {
            let paths = loadOrder.indexRecords(of: type, skipped: &skipped) {
                try ModelBase(record: $0, localized: $1).modelPath
            }
            result.merge(paths) { _, new in new }
        }
        return result
    }
}
