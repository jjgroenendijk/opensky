// PLVL chunk writing. At most one entry, but still a counted, keyed list like every
// component chunk, so a levelling follower needs no format change.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// The `PLVL` chunk: every snapshot entry carrying character-level
    /// progress, in the snapshot's `ReferenceKey` order. A session that never
    /// levelled writes no chunk.
    static func writeProgressChunks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writePlayerProgress(entries, into: &writer)
        writeLegendarySkills(entries, into: &writer)
        writeTrainingSessions(entries, into: &writer)
    }

    /// The `PTRN` chunk: training sessions since the last level-up. Written only
    /// when the player trained this level.
    public static func writeTrainingSessions(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, Int)? in
            guard
                let sessions = entry.delta.component(PlayerProgressState.self)?.trainingSessions,
                sessions > 0
            else { return nil }
            return (entry.key, sessions)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.trainingSessions, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, sessions) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt32(UInt32(clamping: sessions))
            }
        }
    }

    public static func writePlayerProgress(
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

    /// The `PLGD` chunk: legendary counts per skill, in actor-value order. Written
    /// only when a skill was made legendary.
    public static func writeLegendarySkills(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, [Int32: Int])? in
            guard
                let counts = entry.delta.component(PlayerProgressState.self)?.legendaryCounts,
                !counts.isEmpty
            else { return nil }
            return (entry.key, counts)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.legendarySkills, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, counts) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt32(UInt32(clamping: counts.count))
                for (skill, count) in counts.sorted(by: { $0.key < $1.key }) {
                    payload.writeUInt32(UInt32(bitPattern: skill))
                    payload.writeUInt32(UInt32(clamping: count))
                }
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
