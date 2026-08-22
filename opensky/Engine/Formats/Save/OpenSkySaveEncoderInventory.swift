// INVN chunk writing for the OpenSky native save container (issue #176).
//
// A satellite of `OpenSkySaveEncoder` rather than more of its body: the
// encoder was already at the type-length limit, and inventory is the one chunk
// with a nested count inside each entry, so it reads better on its own. The
// three shared writers it uses — `writeChunk`, `writeKey`, `writeCell` — are
// internal on the parent for exactly this reason.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One owner's inventory paired with the snapshot entry it came from.
    private struct OwnedInventory {
        let entry: WorldStateSnapshotEntry
        let inventory: ReferenceInventoryState
    }

    /// The `INVN` chunk: every snapshot entry that carries an inventory
    /// component, in the snapshot's `ReferenceKey` order.
    ///
    /// Each entry repeats its key and cell rather than referring back to an
    /// `RDLT` entry by index, because an owner whose only delta is its
    /// inventory has no `RDLT` entry at all, and an index into a list that may
    /// not contain the item is not a layout worth having. A session that
    /// touched no inventory writes no chunk, so its bytes match what this
    /// encoder produced before the chunk existed.
    static func writeInventories(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let owned = entries.compactMap { entry -> OwnedInventory? in
            guard let inventory = entry.delta.component(ReferenceInventoryState.self) else {
                return nil
            }
            return OwnedInventory(entry: entry, inventory: inventory)
        }
        guard !owned.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.inventories, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: owned.count))
            for each in owned {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                writeItems(each.inventory, into: &payload)
            }
        }
    }

    /// Stack count, then item plus count per stack; equipped count, then one
    /// FormID each. Both lists arrive already sorted by the component's own
    /// invariant, so nothing is sorted here and the bytes stay a pure function
    /// of the state.
    ///
    /// One row per *item*, honest and stolen copies summed. Since issue #504 a
    /// stack is keyed by (form, stolen) and an owner may hold two rows for one
    /// form, but `INVN` entries are a flat positional layout with no per-entry
    /// length: appending a flag to them would make every older build misparse
    /// the whole chunk rather than skip the new part. So the totals stay here,
    /// where an older build reads a complete inventory, and the stolen half
    /// rides in the additive `STOL` chunk beside it.
    private static func writeItems(
        _ inventory: ReferenceInventoryState,
        into writer: inout BinaryWriter
    ) {
        let totals = Self.itemTotals(of: inventory)
        writer.writeUInt32(UInt32(clamping: totals.count))
        for row in totals {
            writer.writeUInt32(row.item.rawValue)
            writer.writeUInt32(UInt32(bitPattern: row.count))
        }
        writer.writeUInt32(UInt32(clamping: inventory.equipped.count))
        for item in inventory.equipped {
            writer.writeUInt32(item.rawValue)
        }
    }

    /// One row per item with honest and stolen copies summed, in the same
    /// ascending form order the component already keeps.
    private static func itemTotals(
        of inventory: ReferenceInventoryState
    ) -> [(item: FormID, count: Int32)] {
        var totals: [(item: FormID, count: Int32)] = []
        for stack in inventory.stacks {
            if let last = totals.last, last.item == stack.item {
                totals[totals.count - 1].count = Int32(
                    clamping: Int64(last.count) + Int64(stack.count)
                )
            } else {
                totals.append((stack.item, stack.count))
            }
        }
        return totals
    }
}
