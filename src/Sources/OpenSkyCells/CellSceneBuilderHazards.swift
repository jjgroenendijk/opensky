// `PHZD` placed hazards of one cell, kept only while their enable state allows.
// Trap hazards hang off an `XESP` parent the trap script enables, so they share
// the reference resolver. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyWorldState

/// One enabled `PHZD` of a built cell.
nonisolated public struct CellHazard: Equatable, Sendable {
    public let key: ReferenceKey
    /// The `HAZD` it places, resolved through the load order.
    public let hazardKey: ReferenceKey?
    public let position: SIMD3<Float>
    public let enableParent: EnableParent?
}

nonisolated extension CellSceneBuilder.CellHazardBuilder {
    /// The enabled `PHZD` records every plugin stores under `cell`.
    nonisolated public func collectHazards(
        in cell: FoundCell,
        resolved: EffectiveReferences,
        parentPool: EnableParentPool = EnableParentPool()
    ) -> [CellHazard] {
        let placed = owner.recordIndex.mergingLater(
            (
                baseHazards(in: cell.children),
                owner.recordIndex.laterChildren(of: FormID(cell.formID), type: "PHZD")
            ),
            formID: \.formID
        ) {
            try $0.record.decode(PlacedProjectile.init(record:))
        } failed: { _ in }
        let byFormID = owner.referenceBuilder.states.entriesByFormID(resolved.entries)
        let enable = owner.enableResolver(
            entries: byFormID,
            pool: parentPool,
            deltas: resolved.deltas
        )
        return placed.compactMap { placed in
            guard
                let key = ReferenceKey.resolve(placed.formID, using: owner.formIDResolver),
                enable.isEnabled(
                    key: key,
                    initiallyDisabled: placed.isInitiallyDisabled,
                    link: placed.enableParent
                )
            else { return nil }
            return CellHazard(
                key: key,
                hazardKey: ReferenceKey.resolve(placed.base, using: owner.formIDResolver),
                position: placed.placement.position,
                enableParent: placed.enableParent
            )
        }
    }

    /// The first plugin's live `PHZD` records; one that does not decode is skipped.
    nonisolated private func baseHazards(in cellChildren: ESMGroup?) -> [PlacedProjectile] {
        guard
            let cellChildren,
            let children = owner.records.childrenOrSkip(cellChildren) else { return [] }
        var hazards: [PlacedProjectile] = []
        for case let .group(group) in children {
            guard let records = owner.records.childrenOrSkip(group) else { continue }
            for case let .record(record) in records
                where record.type == "PHZD" && !record.isDeleted
            {
                if let placed = attempt({ try PlacedProjectile(record: record) }) {
                    hazards.append(placed)
                }
            }
        }
        return hazards
    }
}
