// The plugins after the first: their CELL overrides, the REFR and ACHR records
// they add to or change in a cell, and their base objects. Records are numbered
// in the load-order space, so `Skyrim.esm` FormIDs keep their value
// (docs/engine/cell-scene.md#load-order).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension CellRecordIndex {
    /// The cell as the load order has it: the winning CELL values, and the first
    /// plugin's children group when that plugin has the cell.
    nonisolated func loadOrderCell(formID: FormID, base: FoundCell?) -> FoundCell? {
        guard
            let winner = owner.interiorBuilder.loadOrderIndexBuildingIfNeeded()
                .record(withFormID: formID),
            winner.record.type == "CELL", winner.position > 0, !winner.record.isDeleted,
            let cell = owner.decodeOrSkip(winner.record, using: { _ in
                try winner.decode { try Cell(record: $0, localized: winner.localized) }
            })
        else { return base }
        return FoundCell(cell: cell, formID: formID.rawValue, children: base?.children)
    }

    /// `base` with the later plugins' REFRs for `cell` laid over it.
    nonisolated func mergingLaterReferences(
        _ base: [CollectedReference],
        cell: FormID,
        counts: inout BuildCounts
    ) -> [CollectedReference] {
        var failures = 0
        let later = laterChildren(of: cell, type: "REFR")
        let merged = mergingLater((base, later), formID: \.reference.formID) {
            try CollectedReference(
                reference: $0.record.decode(PlacedReference.init(record:)),
                isPersistent: $0.isPersistent
            )
        } failed: { child in
            failures += 1
            let id = child.record.formID.description
            CellSceneBuilder.logger.warning("malformed REFR \(id, privacy: .public) skipped")
        }
        counts.malformedRefs += failures
        counts.totalRefs += merged.count - base.count + failures
        return merged
    }

    /// `base` with the later plugins' ACHRs for `cell` laid over it.
    nonisolated func mergingLaterActors(
        _ base: [CollectedActor],
        cell: FormID,
        malformed: inout [String]
    ) -> [CollectedActor] {
        var failed: [String] = []
        let later = laterChildren(of: cell, type: "ACHR")
        let merged = mergingLater((base, later), formID: \.actor.formID) {
            try CollectedActor(
                actor: $0.record.decode(PlacedActor.init(record:)),
                isPersistent: $0.isPersistent
            )
        } failed: { child in
            let id = child.record.formID.description
            failed.append("ACHR \(id): malformed record")
            CellSceneBuilder.logger.warning("malformed ACHR \(id, privacy: .public) counted failed")
        }
        malformed += failed
        return merged
    }

    /// A later record replaces the one with the same FormID in place, a new one
    /// joins the end, and a deleted one removes it. An override that does not
    /// decode keeps the earlier version.
    nonisolated func mergingLater<Item>(
        _ layers: (items: [Item], later: [CellChildRecord]),
        formID: (Item) -> FormID,
        decode: (CellChildRecord) throws -> Item,
        failed: (CellChildRecord) -> Void
    ) -> [Item] {
        let (items, later) = layers
        guard !later.isEmpty else { return items }
        var order = items.map(formID)
        var known = Set(order)
        var byID = Dictionary(items.map { (formID($0), $0) }) { _, last in last }
        for child in later {
            let id = child.record.formID
            if child.record.record.isDeleted {
                byID[id] = nil
                continue
            }
            do {
                byID[id] = try decode(child)
            } catch {
                guard byID[id] == nil else { continue }
                failed(child)
                continue
            }
            if known.insert(id).inserted {
                order.append(id)
            }
        }
        return order.compactMap { byID.removeValue(forKey: $0) }
    }

    nonisolated func laterChildren(of cell: FormID, type: FourCC) -> [CellChildRecord] {
        owner.interiorBuilder.loadOrderIndexBuildingIfNeeded().laterChildren(ofCell: cell)
            .filter { $0.record.record.type == type }
    }

    /// Every plugin's `type` records by load-order FormID; a later plugin wins.
    /// A deleted record or one that does not decode keeps the earlier version.
    /// `decode` gets the record and its plugin's localized flag, on any core.
    nonisolated func loadOrderRecords<Value: Sendable>(
        of type: FourCC,
        decode: @Sendable (ESMRecord, Bool) throws -> Value
    ) -> [UInt32: Value] {
        let loadOrder = owner.interiorBuilder.loadOrderIndexBuildingIfNeeded().loadOrder
        return owner.loadPhases.measure(.recordIndex) {
            var skipped = SkippedRecords()
            let index = loadOrder.indexRecordsInParallel(of: type, skipped: &skipped, using: decode)
            owner.noteSkipped(skipped)
            return index
        }
    }
}

nonisolated extension CellSceneBuilder {
    var recordIndex: CellRecordIndex {
        CellRecordIndex(owner: self)
    }
}
