// PRKS chunk writing. Per actor: key, cell, then owned perks in the ascending order
// `PerkState.init` sets, so an unchanged set re-encodes identically.

import Foundation
import OpenSkyFormatsCore
import OpenSkyProgressionInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One actor's owned perks paired with the snapshot entry they came from.
    private struct SavedPerks {
        let entry: WorldStateSnapshotEntry
        let state: PerkState
    }

    /// The `PRKS` chunk: every snapshot entry carrying owned perks, in the
    /// snapshot's `ReferenceKey` order. A session in which nobody owns a perk
    /// writes no chunk.
    public static func writePerks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedPerks? in
            guard
                let state = entry.delta.component(PerkState.self),
                !state.isEmpty
            else { return nil }
            return SavedPerks(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.perks, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.state.owned.count))
                for perk in each.state.owned {
                    writeKey(perk, into: &payload)
                }
            }
        }
    }
}
