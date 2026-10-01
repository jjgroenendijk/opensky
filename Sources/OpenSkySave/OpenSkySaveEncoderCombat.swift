// CBTS chunk writing. Each entry carries its cell. A neutral actor is still written: an
// actor returned to neutral keeps its component, or a reload would find it angry.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// One actor's hostility paired with the snapshot entry it came from.
    private struct SavedCombatState {
        let entry: WorldStateSnapshotEntry
        let state: ActorCombatState
    }

    /// The `CBTS` chunk: every snapshot entry carrying a combat component, in
    /// the snapshot's `ReferenceKey` order. A session in which nothing was
    /// provoked writes no chunk.
    public static func writeCombatStates(
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
