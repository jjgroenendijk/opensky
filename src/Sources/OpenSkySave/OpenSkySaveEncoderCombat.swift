// CBTS chunk writing. Each entry carries its cell. A neutral actor is still written: an
// actor returned to neutral keeps its component, or a reload would find it angry.

import Foundation
public import OpenSkyActorsInterface
import OpenSkyFormatsCore
public import OpenSkyWorldState

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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.combatStates) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
                payload.writeUInt8(each.state.hostility.rawValue)
            }
        }
    }
}
