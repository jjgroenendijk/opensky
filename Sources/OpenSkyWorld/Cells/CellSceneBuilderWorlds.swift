// Worldspaces and their exterior cells over the whole load order. The first
// plugin's groups give the base cells; a later plugin can override a cell, add
// one, or define a whole worldspace (docs/engine/cell-scene.md#load-order).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellSceneBuilder {
    /// The exterior cell at the grid as the load order has it. A cell only a
    /// later plugin defines has no children group; its records come from
    /// `laterChildren(of:type:)`.
    nonisolated public func findCell(
        in world: FoundWorld,
        gridX: Int32,
        gridY: Int32,
        localized: Bool
    ) -> FoundCell? {
        let key = world.formID.rawValue
        if let cached = loadOrderExteriorCells[key] {
            return cached[SIMD2(gridX, gridY)]
        }
        let base = world.children.map { exteriorCellIndex(of: $0, localized: localized) } ?? [:]
        let index = mergingLaterCells(
            base, later: loadOrderIndexBuildingIfNeeded().laterCells(ofWorld: world.formID)
                .filter { !$0.isPersistent }
        )
        loadOrderExteriorCells[key] = index
        return index[SIMD2(gridX, gridY)]
    }

    /// The worldspace persistent CELL: the first plugin's, or else the last
    /// later plugin's.
    nonisolated public func persistentCell(in world: FoundWorld, localized: Bool) -> FoundCell? {
        if
            let children = world.children, let base = persistentCell(
                in: children,
                localized: localized
            )
        {
            return base
        }
        let later = loadOrderIndexBuildingIfNeeded().laterCells(ofWorld: world.formID)
        guard let last = later.last(where: \.isPersistent), !last.record.record.isDeleted
        else { return nil }
        return decodeCell(last.record).map {
            FoundCell(cell: $0, formID: last.record.formID.rawValue, children: nil)
        }
    }

    /// The first plugin's world children group of `world`.
    nonisolated func baseWorldChildren(of world: FormID) -> ESMGroup? {
        guard
            let base = loadOrderIndexBuildingIfNeeded().plugins.first,
            let top = file.topGroup(of: "WRLD"), let children = childrenOrSkip(top)
        else { return nil }
        for case let .group(group) in children where group.kind == .worldChildren {
            if let parent = group.parentFormID, base.translation(FormID(stored: parent)) == world {
                return group
            }
        }
        return nil
    }

    /// `base` with the later plugins' exterior CELLs laid over it by FormID. An
    /// override keeps the base cell's children group; a deleted cell leaves.
    nonisolated private func mergingLaterCells(
        _ base: [SIMD2<Int32>: FoundCell],
        later: [WorldCellRecord]
    ) -> [SIMD2<Int32>: FoundCell] {
        guard !later.isEmpty else { return base }
        var index = base
        var gridOf = Dictionary(base.map { ($0.value.formID, $0.key) }) { first, _ in first }
        for child in later {
            let id = child.record.formID.rawValue
            let earlier = gridOf[id].flatMap { index[$0] }
            if let grid = gridOf.removeValue(forKey: id), index[grid]?.formID == id {
                index[grid] = nil
            }
            guard
                !child.record.record.isDeleted,
                let cell = decodeCell(child.record), let grid = cell.grid
            else { continue }
            let key = SIMD2(grid.x, grid.y)
            index[key] = FoundCell(cell: cell, formID: id, children: earlier?.children)
            gridOf[id] = key
        }
        return index
    }

    nonisolated private func decodeCell(_ record: LoadOrderRecord) -> Cell? {
        decodeOrSkip(record.record, using: { _ in
            try record.decode { try Cell(record: $0, localized: record.localized) }
        })
    }
}
