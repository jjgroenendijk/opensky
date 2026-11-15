// Finds the exterior cells that hold a temporary Is Full LOD reference, in any plugin, from
// record headers alone (docs/engine/distant-lod.md#is-full-lod-references).

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellSceneBuilder.TemporaryFullLODScan {
    /// True when the first plugin's temporary children, or a later plugin's, hold a live REFR
    /// with the flag. A later override that clears the flag again keeps the cell; the merged
    /// cell read then draws nothing for it.
    func holdsTemporaryFullLOD(_ cell: FoundCell) -> Bool {
        baseHolds(cell) || loadOrder.laterChildren(ofCell: FormID(cell.formID))
            .contains { !$0.isPersistent && Self.isLiveFullLODReference($0.record.record) }
    }

    private func baseHolds(_ cell: FoundCell) -> Bool {
        guard
            let cellChildren = cell.children,
            let groups = records.childrenOrSkip(cellChildren)
        else { return false }
        for case let .group(group) in groups where group.kind == .cellTemporaryChildren {
            let holds = (records.childrenOrSkip(group) ?? []).contains { child in
                guard case let .record(record) = child else { return false }
                return Self.isLiveFullLODReference(record)
            }
            if holds {
                return true
            }
        }
        return false
    }

    private static func isLiveFullLODReference(_ record: ESMRecord) -> Bool {
        record.type == "REFR" && !record.isDeleted
            && record.flags.rawValue & PlacedReference.fullLODFlag != 0
    }
}
