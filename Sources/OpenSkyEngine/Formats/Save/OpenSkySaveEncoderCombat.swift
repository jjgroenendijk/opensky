// CBTS chunk writing for the OpenSky native save container (issue #374).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the INVN, QSTS, AVAL
// and DETH writers are: the encoder is at its type-length limit. The three
// shared writers it uses — `writeChunk`, `writeKey`, `writeCell` — are internal
// on the parent for exactly this reason.
//
// The cell travels with each entry, as it does for an actor's values and its
// death: an actor is a placed reference and its cell is what the store's
// per-cell dirty counts are keyed by.
//
// A neutral actor is written like any other. Neutrality is the default an
// untouched actor reads, but an actor *returned* to neutral from hostile has a
// component and has to keep it, or a reload would find it angry again.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One actor's hostility paired with the snapshot entry it came from.
    private struct SavedCombatState {
        let entry: WorldStateSnapshotEntry
        let state: ActorCombatState
    }

    /// The `CBTS` chunk: every snapshot entry carrying a combat component, in
    /// the snapshot's `ReferenceKey` order. A session in which nothing was
    /// provoked writes no chunk.
    static func writeCombatStates(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedCombatState? in
            guard let state = entry.delta.component(ActorCombatState.self) else { return nil }
            return SavedCombatState(entry: entry, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.combatStates, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.entry.key, into: &payload)
                writeCell(each.entry.delta.cell, into: &payload)
                payload.writeUInt8(each.state.hostility.rawValue)
            }
        }
    }
}
