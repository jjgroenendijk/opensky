// PLVL chunk writing for the OpenSky native save container (issue #499).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the PRKS and SPLB
// writers are: the encoder is at its type-length limit. The three shared
// writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal on the
// parent for exactly this reason.
//
// One entry at most, because one character levels. It is still written as a
// counted, keyed list rather than as a bare struct so the chunk reads like
// every other component chunk and so a later milestone that levels a follower
// needs no format change.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// The `PLVL` chunk: every snapshot entry carrying character-level
    /// progress, in the snapshot's `ReferenceKey` order. A session that never
    /// levelled writes no chunk.
    static func writePlayerProgress(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (WorldStateSnapshotEntry, PlayerProgressState)? in
            guard
                let state = entry.delta.component(PlayerProgressState.self),
                !state.isEmpty
            else { return nil }
            return (entry, state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.playerProgress, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, state) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                writeProgress(state, into: &payload)
            }
        }
    }

    /// One progress record. The pick history is written as vanilla actor-value
    /// indices rather than as an enum ordinal, so the bytes stay meaningful
    /// against the table every other chunk addresses values by.
    private static func writeProgress(
        _ state: PlayerProgressState,
        into payload: inout BinaryWriter
    ) {
        payload.writeUInt32(UInt32(clamping: state.level))
        payload.writeFloat32(state.experience)
        payload.writeUInt32(UInt32(clamping: state.perkPoints))
        payload.writeUInt32(UInt32(clamping: state.pendingAttributePicks))
        payload.writeUInt32(UInt32(clamping: state.skillIncreases))
        payload.writeUInt32(UInt32(clamping: state.attributePicks.count))
        for pick in state.attributePicks {
            payload.writeUInt32(UInt32(bitPattern: ActorValueIdentity.index(of: pick)))
        }
    }
}
