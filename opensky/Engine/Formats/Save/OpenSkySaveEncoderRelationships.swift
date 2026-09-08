// RELS chunk writing for the OpenSky native save container (issue #508).
//
// A satellite of `OpenSkySaveEncoder` for the same reason `OpenSkySaveEncoder`
// splits FCTN, PRKS and SPLB out: the encoder is at its type-length limit. The
// three shared writers used here — `writeChunk`, `writeKey`, `writeCell` — are
// internal on the parent for exactly this reason.
//
// Per actor, in order: the key, the cell, then the override list. The list is
// written in the component's own ascending key order, which
// `ActorRelationshipState.init` establishes, so re-encoding an unchanged set
// produces identical bytes.

import Foundation

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
