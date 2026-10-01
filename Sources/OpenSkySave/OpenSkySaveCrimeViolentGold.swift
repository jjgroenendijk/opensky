// The CRVG chunk: the violent part of each `CRIM` row's bounty. `CRIM` still writes the
// total, so an older build restores the right bounty; non-violent gold is the
// remainder. Only rows with a violent part are written, so a theft-only session
// writes no chunk. See docs/formats/opensky-save-actor-chunks.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One actor's violent gold per faction, before it splits the `CRIM` totals.
nonisolated public struct SaveViolentCrimeGoldEntry: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let faction: ReferenceKey
        public let violentGold: Int32
    }

    public let key: ReferenceKey
    public let rows: [Row]
}

nonisolated extension OpenSkySaveEncoder {
    /// The `CRVG` chunk, in the snapshot's `ReferenceKey` order.
    public static func writeViolentCrimeGold(
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
    public static func decodeViolentGold(_ payload: Data) throws -> [SaveViolentCrimeGoldEntry] {
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

    /// The `CRIM` ledgers with each row's violent part split out. A violent part over
    /// the total is clamped, and a row with no `CRIM` row is dropped: `CRIM` says what
    /// is owed, as `INVN` does for `STOL`.
    public static func splittingViolent(
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
