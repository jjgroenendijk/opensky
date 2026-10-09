// `PHZD` placed hazards of one cell, kept only while their enable state allows.
// Trap hazards hang off an `XESP` parent the trap script enables, so they share
// the reference resolver. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One enabled `PHZD` of a built cell.
nonisolated public struct CellHazard: Equatable, Sendable {
    public let key: ReferenceKey
    /// The `HAZD` it places, resolved through the load order.
    public let hazardKey: ReferenceKey?
    public let position: SIMD3<Float>
    public let enableParent: EnableParent?
}

nonisolated extension CellSceneBuilder {
    /// The enabled `PHZD` records every plugin stores under `cell`.
    nonisolated public func collectHazards(
        in cell: FoundCell,
        resolved: EffectiveReferences,
        parentPool: [FormID: PlacedReference] = [:]
    ) -> [CellHazard] {
        let placed = mergingLater(
            baseHazards(in: cell.children),
            later: laterChildren(of: FormID(cell.formID), type: "PHZD"),
            formID: \.formID
        ) {
            try $0.record.decode(PlacedProjectile.init(record:))
        } failed: { _ in }
        let byFormID = entriesByFormID(resolved.entries)
        let enable = EnableParentResolver(deltas: resolved.deltas) { formID in
            byFormID[formID] ?? parentPool[formID].flatMap { reference in
                self.runtimeEntry(formID: formID, isPersistent: true, record: .reference(reference))
            }
        }
        return placed.compactMap { placed in
            guard
                let key = ReferenceKey.resolve(placed.formID, using: formIDResolver),
                enable.isEnabled(
                    key: key,
                    initiallyDisabled: placed.isInitiallyDisabled,
                    link: placed.enableParent
                )
            else { return nil }
            return CellHazard(
                key: key,
                hazardKey: ReferenceKey.resolve(placed.base, using: formIDResolver),
                position: placed.placement.position,
                enableParent: placed.enableParent
            )
        }
    }

    /// The first plugin's live `PHZD` records; one that does not decode is skipped.
    nonisolated private func baseHazards(in cellChildren: ESMGroup?) -> [PlacedProjectile] {
        guard let cellChildren, let children = childrenOrSkip(cellChildren) else { return [] }
        var hazards: [PlacedProjectile] = []
        for case let .group(group) in children {
            guard let records = childrenOrSkip(group) else { continue }
            for case let .record(record) in records
                where record.type == "PHZD" && !record.isDeleted
            {
                if let placed = try? PlacedProjectile(record: record) {
                    hazards.append(placed)
                }
            }
        }
        return hazards
    }
}
