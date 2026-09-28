// CRIM and STOL chunk writing for the OpenSky native save container (issue
// #504).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the FCTN and PRKS
// writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// Two chunks rather than one, because they describe two different owners of two
// different things. `CRIM` is the bounty ledger, keyed by the perpetrator.
// `STOL` is the stolen half of an inventory, keyed by whoever holds the goods —
// and those are not the same reference the moment the player hands a hot ring
// to a fence.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's ledger paired with the snapshot entry it came from.
    private struct SavedLedger {
        let entry: WorldStateSnapshotEntry
        let ledger: CrimeLedgerState
    }

    /// One owner's stolen stacks paired with the snapshot entry they came from.
    private struct SavedStolenGoods {
        let entry: WorldStateSnapshotEntry
        let stacks: [InventoryStack]
    }

    /// The `CRIM` chunk: every snapshot entry carrying a crime ledger, in the
    /// snapshot's `ReferenceKey` order. A law-abiding session writes no chunk.
    ///
    /// Per row: the faction, the gold owed, then the four crime counts in
    /// `CrimeKind.allCases` order. The counts travel beside the gold because
    /// they are not derivable from it — an unwitnessed crime moves one and not
    /// the other, which is the whole difference the ledger records.
    static func writeCrimeLedgers(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedLedger? in
            guard
                let ledger = entry.delta.component(CrimeLedgerState.self),
                !ledger.isEmpty
            else { return nil }
            return SavedLedger(entry: entry, ledger: ledger)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.crimeLedgers, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.ledger.count))
                for row in each.ledger.entries {
                    writeKey(row.faction, into: &payload)
                    payload.writeUInt32(UInt32(bitPattern: row.gold))
                    for kind in CrimeKind.allCases {
                        payload.writeUInt32(UInt32(bitPattern: row.counts[kind]))
                    }
                }
            }
        }
    }

    /// The `STOL` chunk: for every owner holding stolen goods, one row per item
    /// with how many of its copies are stolen.
    ///
    /// The counterpart of the totals `INVN` writes. An owner holding nothing
    /// stolen writes no row and a session in which nothing was stolen writes no
    /// chunk, so its bytes match what this encoder produced before the chunk
    /// existed.
    static func writeStolenGoods(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedStolenGoods? in
            guard let inventory = entry.delta.component(ReferenceInventoryState.self) else {
                return nil
            }
            let stolen = inventory.stacks.filter(\.stolen)
            return stolen.isEmpty ? nil : SavedStolenGoods(entry: entry, stacks: stolen)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.stolenGoods, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.stacks.count))
                for stack in each.stacks {
                    payload.writeUInt32(stack.item.rawValue)
                    payload.writeUInt32(UInt32(bitPattern: stack.count))
                }
            }
        }
    }
}
