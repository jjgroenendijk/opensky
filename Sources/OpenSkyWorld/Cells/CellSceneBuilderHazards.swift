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
    /// The enabled `PHZD` records directly under `cellChildren`.
    nonisolated public func collectHazards(
        in cellChildren: ESMGroup?,
        resolved: EffectiveReferences,
        parentPool: [FormID: PlacedReference] = [:]
    ) -> [CellHazard] {
        guard let cellChildren, let children = childrenOrSkip(cellChildren) else { return [] }
        let byFormID = entriesByFormID(resolved.entries)
        let enable = EnableParentResolver(deltas: resolved.deltas) { formID in
            byFormID[formID] ?? parentPool[formID].flatMap { reference in
                self.runtimeEntry(formID: formID, isPersistent: true, record: .reference(reference))
            }
        }
        var hazards: [CellHazard] = []
        for case let .group(group) in children {
            guard let records = childrenOrSkip(group) else { continue }
            for case let .record(record) in records where record.type == "PHZD" {
                guard
                    !record.isDeleted,
                    let placed = try? PlacedProjectile(record: record),
                    let key = ReferenceKey.resolve(placed.formID, using: formIDResolver),
                    enable.isEnabled(
                        key: key,
                        initiallyDisabled: placed.isInitiallyDisabled,
                        link: placed.enableParent
                    )
                else { continue }
                hazards.append(CellHazard(
                    key: key,
                    hazardKey: ReferenceKey.resolve(placed.base, using: formIDResolver),
                    position: placed.placement.position,
                    enableParent: placed.enableParent
                ))
            }
        }
        return hazards
    }
}
