// RELS chunk writing. Per actor: key, cell, then overrides in the ascending order
// `ActorRelationshipState.init` sets, so an unchanged set re-encodes identically.

import Foundation
public import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyWorldState

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
    static func writeRelationshipRanks(
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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.relationships) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
                payload.writeUInt32(UInt32(clamping: each.state.count))
                for override in each.state.overrides {
                    payload.writeKey(override.other)
                    payload.writeUInt8(UInt8(bitPattern: override.rank))
                }
            }
        }
    }
}
