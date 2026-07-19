// Read-only ESM walk for tooling that needs model paths without Metal. This
// follows the same WRLD -> CELL -> REFR -> base-record chain as
// CellSceneBuilder, but returns canonical VFS keys only.
//
// References: UESP Skyrim Mod File Format pages for WRLD groups, CELL, REFR,
// STAT, plus ModelBase's cited MSTT/TREE/FURN/ACTI/CONT/DOOR pages.

import Foundation

nonisolated struct ExteriorCellModelCatalog {
    let file: ESMFile

    func modelPaths(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> [String] {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let world = try worldChildren(editorID: worldspaceEditorID, localized: localized)
        guard let cell = findCell(in: world, x: gridX, y: gridY, localized: localized) else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        let bases = baseModelPaths()
        var paths: Set<String> = []
        forEachReference(in: cell.children) { record in
            guard !record.isDeleted, let ref = try? PlacedReference(record: record) else {
                return
            }
            guard let rawPath = bases[ref.base.rawValue], let rawPath else { return }
            if let normalized = try? VirtualFileSystem.normalize(rawPath) {
                let path = normalized.hasPrefix("meshes\\")
                    ? normalized
                    : "meshes\\" + normalized
                paths.insert(path)
            }
        }
        return paths.sorted()
    }

    private struct FoundCell {
        let children: ESMGroup?
    }

    private func worldChildren(editorID: String, localized: Bool) throws -> ESMGroup {
        guard let top = file.topGroup(of: "WRLD") else {
            throw CellSceneError.worldspaceNotFound(editorID: editorID)
        }
        var matchedFormID: UInt32?
        for child in try top.children() {
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
        throw CellSceneError.worldspaceNotFound(editorID: editorID)
    }

    private func findCell(
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
                if let found = findCell(in: sub, x: x, y: y, localized: localized) {
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

    private func forEachReference(in cellChildren: ESMGroup?, body: (ESMRecord) -> Void) {
        guard let children = try? cellChildren?.children() else { return }
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren
                || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            for case let .record(record) in records where record.type == "REFR" {
                body(record)
            }
        }
    }

    private func baseModelPaths() -> [UInt32: String?] {
        var result: [UInt32: String?] = [:]
        if let top = file.topGroup(of: "STAT"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "STAT" {
                if let object = try? StaticObject(record: record) {
                    result[record.formID] = object.modelPath
                }
            }
        }
        for type in ModelBase.supportedTypes {
            guard let top = file.topGroup(of: type), let children = try? top.children() else {
                continue
            }
            for case let .record(record) in children where record.type == type {
                if let object = try? ModelBase(record: record) {
                    result[record.formID] = object.modelPath
                }
            }
        }
        return result
    }
}
