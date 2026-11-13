// The record walk of the cell scene builder: skips, groups, exterior cells, and instances.

import Foundation
import Metal
import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellRecordWalker {
    /// Adds the skips of a load-order decode, which counts them itself.
    func noteSkipped(_ skipped: SkippedRecords) {
        guard !skipped.isEmpty else { return }
        owner.skippedRecords.merge(skipped)
        for line in skipped.lines {
            CellSceneBuilder.logger.warning("malformed records skipped: \(line, privacy: .public)")
        }
    }

    /// Decodes `record`, or counts it in `skippedRecords` and returns nil.
    /// Cell searches re-read records on every build, so a FormID counts once.
    nonisolated public func decodeOrSkip<Value>(
        _ record: ESMRecord,
        using decode: (ESMRecord) throws -> Value
    ) -> Value? {
        do {
            return try decode(record)
        } catch {
            guard owner.skippedFormIDs.insert(record.formID).inserted else { return nil }
            owner.skippedRecords.note(record.type, error: error)
            let id = FormID(record.formID).description
            let type = record.type.description
            let reason = String(describing: error)
            CellSceneBuilder.logger.warning(
                """
                malformed \(type, privacy: .public) \(id, privacy: .public) skipped: \
                \(reason, privacy: .public)
                """
            )
            return nil
        }
    }

    /// The group's children, or nil with the error counted once under its record type.
    nonisolated public func childrenOrSkip(_ group: ESMGroup) -> [ESMGroup.Child]? {
        do {
            return try group.children()
        } catch {
            guard owner.skippedGroupOffsets.insert(group.contentRange.lowerBound).inserted else {
                return nil
            }
            owner.skippedRecords.note(group.recordType ?? "GRUP", error: error)
            Self.logMalformedGroup(error)
            return nil
        }
    }

    /// For static walks, which hold no builder to count the skip in.
    nonisolated public static func loggedChildren(_ group: ESMGroup) -> [ESMGroup.Child]? {
        do {
            return try group.children()
        } catch {
            logMalformedGroup(error)
            return nil
        }
    }

    private static func logMalformedGroup(_ error: any Error) {
        let reason = String(describing: error)
        CellSceneBuilder.logger.warning("malformed group skipped: \(reason, privacy: .public)")
    }

    /// Returns the first WRLD group whose EDID matches exactly. A malformed WRLD
    /// is skipped, because another one may still match.
    nonisolated public func worldChildrenGroup(
        editorID: String,
        localized: Bool
    ) throws -> FoundWorld {
        guard localized == owner.pluginLocalized else {
            return try owner.preparation.uncachedWorldChildrenGroup(
                editorID: editorID,
                localized: localized
            )
        }
        if let cached = owner.caches.worldChildrenGroups[editorID] {
            return cached
        }
        let found = try owner.preparation.uncachedWorldChildrenGroup(
            editorID: editorID,
            localized: localized
        )
        owner.caches.worldChildrenGroups[editorID] = found
        return found
    }

    /// Every exterior CELL under `group` by grid. One full walk costs about as much
    /// as a few single-cell searches, and each later build then skips the walk.
    nonisolated func exteriorCellIndex(
        of group: ESMGroup,
        localized: Bool
    ) -> [SIMD2<Int32>: FoundCell] {
        var index: [SIMD2<Int32>: FoundCell] = [:]
        indexExteriorCells(in: group, localized: localized, into: &index)
        return index
    }

    nonisolated private func indexExteriorCells(
        in group: ESMGroup,
        localized: Bool,
        into index: inout [SIMD2<Int32>: FoundCell]
    ) {
        // Prune a malformed subtree: other cells may live in a sibling block.
        guard let children = childrenOrSkip(group) else { return }
        for (position, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL" && group.kind != .worldChildren:
                guard
                    let cell = decodeOrSkip(record, using: {
                        try Cell(record: $0, localized: localized)
                    }),
                    let grid = cell.grid, index[SIMD2(grid.x, grid.y)] == nil
                else { continue }
                index[SIMD2(grid.x, grid.y)] = FoundCell(
                    cell: cell,
                    formID: record.formID,
                    children: cellChildrenGroup(
                        following: position, in: children, cellFormID: record.formID
                    )
                )
            case let .group(sub)
                where sub.kind == .exteriorCellBlock || sub.kind == .exteriorCellSubBlock:
                indexExteriorCells(in: sub, localized: localized, into: &index)
            default:
                break
            }
        }
    }

    /// The worldspace persistent CELL: the one CELL stored directly in the world
    /// children group, not in a block (xEdit names it "<Persistent Worldspace Cell>").
    nonisolated func persistentCell(
        in worldChildren: ESMGroup,
        localized: Bool
    ) -> FoundCell? {
        guard let children = childrenOrSkip(worldChildren) else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                let cell = decodeOrSkip(record, using: {
                    try Cell(record: $0, localized: localized)
                })
            else { continue }
            return FoundCell(
                cell: cell,
                formID: record.formID,
                children: cellChildrenGroup(
                    following: index, in: children, cellFormID: record.formID
                )
            )
        }
        return nil
    }

    /// The group follows its CELL among the same siblings, labeled with its FormID.
    nonisolated func cellChildrenGroup(
        following index: Int,
        in children: [ESMGroup.Child],
        cellFormID: UInt32
    ) -> ESMGroup? {
        let rest = children[(index + 1)...]
        for case let .group(group) in rest where group.kind == .cellChildren {
            if group.parentFormID == cellFormID {
                return group
            }
        }
        return nil
    }
}
