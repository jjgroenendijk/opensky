// CRIM and STOL chunk writing. Two chunks, because they key different owners: `CRIM` is
// the bounty ledger by perpetrator, `STOL` the stolen goods by holder, which differ once
// the player sells to a fence.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

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

    /// The `CRIM` chunk, in key order: per row the faction, the gold, then the four
    /// counts in `CrimeKind.allCases` order. Counts travel because an unwitnessed crime
    /// moves a count and not the gold.
    public static func writeCrimeLedgers(
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

    /// The `STOL` chunk: per owner, one row per item with its stolen count. The partner
    /// of `INVN`'s totals. Nothing stolen writes no chunk.
    public static func writeStolenGoods(
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
