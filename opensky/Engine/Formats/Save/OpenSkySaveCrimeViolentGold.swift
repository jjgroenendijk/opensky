// The CRVG chunk for the OpenSky native save container (issue #563): the
// violent part of each `CRIM` row's bounty.
//
// `CRIM` writes the combined total per faction and keeps doing so, which is
// what lets a build that predates the split restore the right bounty. This
// chunk says how much of that total is violent; the rest is non-violent by
// subtraction, so the two halves cannot disagree with the total a reader sees.
//
// Only rows with a violent part are written, and only actors with such a row,
// so a session whose bounties are all theft and trespass writes no chunk and
// its bytes match what the encoder produced before the chunk existed.
//
// Documented in docs/formats/opensky-save-actor-chunks.md.

import Foundation

/// One actor's violent gold per faction, before it splits the `CRIM` totals.
nonisolated struct SaveViolentCrimeGoldEntry: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let faction: ReferenceKey
        let violentGold: Int32
    }

    let key: ReferenceKey
    let rows: [Row]
}

nonisolated extension OpenSkySaveEncoder {
    /// The `CRVG` chunk, in the snapshot's `ReferenceKey` order.
    static func writeViolentCrimeGold(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, [CrimeLedgerEntry])? in
            guard let ledger = entry.delta.component(CrimeLedgerState.self) else { return nil }
            let rows = ledger.entries.filter { $0.violentGold > 0 }
            return rows.isEmpty ? nil : (entry.key, rows)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.violentCrimeGold, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, rows) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt32(UInt32(clamping: rows.count))
                for row in rows {
                    writeKey(row.faction, into: &payload)
                    payload.writeUInt32(UInt32(bitPattern: row.violentGold))
                }
            }
        }
    }
}

nonisolated extension OpenSkySaveCrimeDecoder {
    static func decodeViolentGold(_ payload: Data) throws -> [SaveViolentCrimeGoldEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CRVG entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumViolentCrimeGoldEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.violentCrimeGold
        )
        var entries: [SaveViolentCrimeGoldEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rowCount = try reader.uint32("CRVG row count")
            try OpenSkySaveDecoder.validate(
                count: rowCount,
                minimumElementSize: OpenSkySaveFormat.minimumViolentCrimeGoldRowSize,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.violentCrimeGold
            )
            var rows: [SaveViolentCrimeGoldEntry.Row] = []
            rows.reserveCapacity(Int(rowCount))
            for _ in 0 ..< rowCount {
                let faction = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                let gold = try Int32(bitPattern: reader.uint32("CRVG row gold"))
                rows.append(.init(faction: faction, violentGold: gold))
            }
            entries.append(SaveViolentCrimeGoldEntry(key: key, rows: rows))
        }
        return entries
    }

    /// The `CRIM` ledgers with each named row's violent part moved out of its
    /// non-violent total.
    ///
    /// A violent part larger than the total is clamped to the total rather than
    /// rejected, and a row naming a faction `CRIM` has no row for is dropped:
    /// `CRIM` says what is owed and this chunk only says how it divides, the
    /// rule `STOL` follows over `INVN`.
    static func splittingViolent(
        _ values: [SaveViolentCrimeGoldEntry],
        in ledgers: [SaveCrimeLedgerEntry]
    ) -> [SaveCrimeLedgerEntry] {
        guard !values.isEmpty else { return ledgers }
        var violentByKey: [ReferenceKey: [ReferenceKey: Int32]] = [:]
        for value in values {
            for row in value.rows {
                violentByKey[value.key, default: [:]][row.faction] = row.violentGold
            }
        }
        return ledgers.map { saved in
            guard let violent = violentByKey[saved.key] else { return saved }
            let rows = saved.ledger.entries.map { row -> CrimeLedgerEntry in
                guard let part = violent[row.faction] else { return row }
                let violentGold = min(max(0, part), row.gold)
                return CrimeLedgerEntry(
                    faction: row.faction,
                    nonViolentGold: row.gold - violentGold,
                    violentGold: violentGold,
                    counts: row.counts
                )
            }
            return SaveCrimeLedgerEntry(
                key: saved.key,
                cell: saved.cell,
                ledger: CrimeLedgerState(entries: rows)
            )
        }
    }
}
