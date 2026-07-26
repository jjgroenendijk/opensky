// Cached STAT/ModelBase indexes and exterior build-source lookup. Split from
// CellSceneBuilder.swift to keep the primary build flow within strict limits.

import OSLog

nonisolated struct ExteriorBuildSource {
    let world: FoundWorld
    let cell: FoundCell
}

extension CellSceneBuilder {
    nonisolated func exteriorBuildSource(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> ExteriorBuildSource {
        let world = try worldChildrenGroup(
            editorID: worldspaceEditorID,
            localized: pluginLocalized
        )
        guard
            let cell = findCell(
                in: world.children,
                gridX: gridX,
                gridY: gridY,
                localized: pluginLocalized
            )
        else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        return ExteriorBuildSource(world: world, cell: cell)
    }

    /// One plugin means REFR and base IDs share a FormID space for now.
    nonisolated func statIndexBuildingIfNeeded() -> [UInt32: StaticObject] {
        if let statIndex {
            return statIndex
        }
        var index: [UInt32: StaticObject] = [:]
        if let top = file.topGroup(of: "STAT"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "STAT" {
                guard let stat = try? StaticObject(record: record) else {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed STAT \(id, privacy: .public) skipped")
                    continue
                }
                index[record.formID] = stat
            }
        }
        statIndex = index
        return index
    }

    /// One cached index spans the six model-base top groups.
    nonisolated func modelBaseIndexBuildingIfNeeded() -> [UInt32: ModelBase] {
        if let modelBaseIndex {
            return modelBaseIndex
        }
        var index: [UInt32: ModelBase] = [:]
        for type in ModelBase.supportedTypes {
            guard let top = file.topGroup(of: type), let children = try? top.children() else {
                continue
            }
            for case let .record(record) in children where record.type == type {
                guard
                    let base = try? ModelBase(
                        record: record,
                        localized: pluginLocalized
                    )
                else {
                    let id = FormID(record.formID).description
                    let name = type.description
                    Self.logger.warning(
                        "malformed \(name, privacy: .public) \(id, privacy: .public) skipped"
                    )
                    continue
                }
                index[record.formID] = base
            }
        }
        modelBaseIndex = index
        return index
    }

    nonisolated func resolveBase(
        formID: UInt32,
        statIndex: [UInt32: StaticObject],
        modelBaseIndex: [UInt32: ModelBase]
    ) -> ResolvedBase? {
        if let stat = statIndex[formID] {
            return ResolvedBase(
                formID: stat.formID,
                recordType: "STAT",
                modelPath: stat.modelPath
            )
        }
        if let base = modelBaseIndex[formID] {
            return ResolvedBase(
                formID: base.formID,
                recordType: base.recordType,
                modelPath: base.modelPath
            )
        }
        return nil
    }
}
