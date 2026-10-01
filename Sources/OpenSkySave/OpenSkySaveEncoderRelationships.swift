// RELS chunk writing. Per actor: key, cell, then overrides in the ascending order
// `ActorRelationshipState.init` sets, so an unchanged set re-encodes identically.

import Foundation
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One actor's relationship overrides paired with the snapshot entry they
    /// came from.
    private struct SavedRelationships {
        let entry: WorldStateSnapshotEntry
        let state: ActorRelationshipState
    }

    /// The `RELS` chunk: every snapshot entry carrying a scripted relationship
    /// rank, in the snapshot's `ReferenceKey` order. A session in which no
    /// script set a rank writes no chunk.
    public static func writeRelationshipRanks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedRelationships? in
            guard
                let state = entry.delta.component(ActorRelationshipState.self),
                !state.isEmpty
            else { return nil }
            return SavedRelationships(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.relationships, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.state.count))
                for override in each.state.overrides {
                    writeKey(override.other, into: &payload)
                    payload.writeUInt8(UInt8(bitPattern: override.rank))
                }
            }
        }
    }
}
