// FCTN chunk writing for the OpenSky native save container (issue #503).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the PRKS and SPLB
// writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// Per actor, in order: the key, the cell, then the membership list. The list is
// written in the component's own ascending faction-key order, which
// `ActorFactionState.init` establishes, so re-encoding an unchanged membership
// set produces identical bytes.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's memberships paired with the snapshot entry they came from.
    private struct SavedFactions {
        let entry: WorldStateSnapshotEntry
        let state: ActorFactionState
    }

    /// The `FCTN` chunk: every snapshot entry carrying faction memberships, in
    /// the snapshot's `ReferenceKey` order. A session in which nobody joined
    /// anything and nobody was asked writes no chunk.
    static func writeFactionMemberships(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedFactions? in
            guard
                let state = entry.delta.component(ActorFactionState.self),
                !state.isEmpty
            else { return nil }
            return SavedFactions(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.factions, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.state.count))
                for membership in each.state.memberships {
                    writeKey(membership.faction, into: &payload)
                    payload.writeUInt8(UInt8(bitPattern: membership.rank))
                }
            }
        }
    }
}
