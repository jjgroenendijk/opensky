// FCTN chunk writing. Per actor: key, cell, then memberships in the ascending order
// `ActorFactionState.init` sets, so an unchanged set re-encodes identically.

import Foundation
public import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyWorldState

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
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.factions) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                payload.writeKey(each.entry.key)
                payload.writeCell(each.entry.delta.cell)
                payload.writeUInt32(UInt32(clamping: each.state.count))
                for membership in each.state.memberships {
                    payload.writeKey(membership.faction)
                    payload.writeUInt8(UInt8(bitPattern: membership.rank))
                }
            }
        }
    }
}
