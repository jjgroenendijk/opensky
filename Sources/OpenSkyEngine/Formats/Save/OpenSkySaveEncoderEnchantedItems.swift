// ECHG chunk writing for the OpenSky native save container (issue #472).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the SPLB, AEFF, AVAL
// and DETH writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// Per owner, in order: the key, the cell, the charge list as `(item FormID,
// remaining charge)` pairs, then the worn-item list as `(item FormID, sequence
// count, sequences)` groups.
//
// Both lists are written in ascending FormID order and the sequences inside a
// group ascend, which `EnchantedItemState.init` establishes, so re-encoding an
// unchanged owner produces identical bytes.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One owner's enchanted-item state paired with the snapshot entry it came
    /// from.
    private struct SavedEnchantedItems {
        let entry: WorldStateSnapshotEntry
        let state: EnchantedItemState
    }

    /// The `ECHG` chunk: every snapshot entry carrying enchanted-item state, in
    /// the snapshot's `ReferenceKey` order. A session in which nothing enchanted
    /// fired and nothing enchanted was worn writes no chunk.
    static func writeEnchantedItems(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedEnchantedItems? in
            guard
                let state = entry.delta.component(EnchantedItemState.self),
                !state.isEmpty
            else { return nil }
            return SavedEnchantedItems(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.enchantedItems, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                writeEnchantedItems(each.state, into: &payload)
            }
        }
    }

    private static func writeEnchantedItems(
        _ state: EnchantedItemState,
        into writer: inout BinaryWriter
    ) {
        let charges = state.charges.sorted { $0.key < $1.key }
        writer.writeUInt32(UInt32(clamping: charges.count))
        for (item, remaining) in charges {
            writer.writeUInt32(item)
            writer.writeFloat32(remaining)
        }
        let worn = state.wornEffects.sorted { $0.key < $1.key }
        writer.writeUInt32(UInt32(clamping: worn.count))
        for (item, sequences) in worn {
            writer.writeUInt32(item)
            writer.writeUInt32(UInt32(clamping: sequences.count))
            for sequence in sequences {
                writer.writeUInt64(sequence)
            }
        }
    }
}
