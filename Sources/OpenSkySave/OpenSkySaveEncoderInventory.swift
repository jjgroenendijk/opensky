// INVN chunk writing, the one chunk with a nested count per entry. The shared
// `writeChunk`, `writeKey` and `writeCell` are internal on the encoder for files like this.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One owner's inventory paired with the snapshot entry it came from.
    private struct OwnedInventory {
        let entry: WorldStateSnapshotEntry
        let inventory: ReferenceInventoryState
    }

    /// The `INVN` chunk: every entry with an inventory, in key order. Each repeats its key
    /// and cell, because an inventory-only owner has no `RDLT` entry.
    public static func writeInventories(
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

    /// Stack count, then item and count per stack; equipped count, then FormIDs. Both are
    /// pre-sorted. One row per item, stolen copies summed: the layout has no per-entry
    /// length, so the stolen split goes in the additive `STOL` chunk.
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
