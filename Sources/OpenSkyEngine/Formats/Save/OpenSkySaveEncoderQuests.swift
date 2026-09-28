// QSTS chunk writing for the OpenSky native save container (issue #182).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the INVN writer is
// one: the encoder is at its type-length limit, and this chunk has two nested
// counts inside each entry.
//
// No cell travels with a quest entry, unlike an inventory entry. A quest is a
// base record that belongs to no cell, so its delta's cell is always absent and
// writing the tag would be a byte that can only ever hold one value.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// One quest's runtime state paired with the snapshot entry it came from.
    private struct SavedQuest {
        let key: ReferenceKey
        let state: QuestRuntimeState
    }

    /// The `QSTS` chunk: every snapshot entry carrying a quest component, in
    /// the snapshot's `ReferenceKey` order. A session that touched no quest
    /// writes no chunk.
    static func writeQuestStates(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedQuest? in
            guard let state = entry.delta.component(QuestRuntimeState.self) else { return nil }
            return SavedQuest(key: entry.key, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.questStates, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.key, into: &payload)
                writeQuestState(each.state, into: &payload)
            }
        }
    }

    /// Flag byte, then the reached stages, then the objectives. Both lists
    /// arrive sorted by the component's own invariant, so nothing is sorted
    /// here and the bytes stay a pure function of the state.
    private static func writeQuestState(
        _ state: QuestRuntimeState,
        into writer: inout BinaryWriter
    ) {
        var flags: UInt8 = 0
        if state.isRunning {
            flags |= OpenSkySaveFormat.QuestFlag.running
        }
        if state.isCompleted {
            flags |= OpenSkySaveFormat.QuestFlag.completed
        }
        writer.writeUInt8(flags)
        writer.writeUInt32(UInt32(clamping: state.stagesReached.count))
        for stage in state.stagesReached {
            writer.writeUInt16(stage)
        }
        writer.writeUInt32(UInt32(clamping: state.objectives.count))
        for objective in state.objectives {
            writer.writeUInt16(objective.index)
            writer.writeUInt8(objectiveFlags(objective))
        }
    }

    /// The `QALS` chunk (issue #183): every snapshot entry carrying a non-empty
    /// alias table, in the snapshot's `ReferenceKey` order. A session whose
    /// quests filled nothing writes no chunk, so its bytes match what this
    /// encoder produced before the chunk existed.
    ///
    /// An empty table is deliberately not written. It is the state a quest has
    /// before a start and after a stop, and the decoder restores exactly that
    /// for a quest the chunk does not mention.
    static func writeQuestAliases(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (key: ReferenceKey, state: QuestAliasState)? in
            guard
                let state = entry.delta.component(QuestAliasState.self),
                !state.fills.isEmpty
            else {
                return nil
            }
            return (key: entry.key, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.questAliases, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.key, into: &payload)
                payload.writeUInt32(UInt32(clamping: each.state.fills.count))
                // The fills arrive sorted by alias ID from the component's own
                // invariant, so nothing is sorted here and the bytes stay a
                // pure function of the state.
                for fill in each.state.fills {
                    payload.writeUInt32(fill.aliasID)
                    writeKey(fill.reference, into: &payload)
                }
            }
        }
    }

    /// `QLOC`: location targets are a sibling chunk because QALS entries are
    /// not individually length-delimited and cannot be extended compatibly.
    static func writeQuestLocationAliases(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, [QuestLocationAliasFill])? in
            guard
                let state = entry.delta.component(QuestAliasState.self),
                !state.locationFills.isEmpty
            else { return nil }
            return (entry.key, state.locationFills)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.questLocationAliases, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, fills) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt32(UInt32(clamping: fills.count))
                for fill in fills {
                    payload.writeUInt32(fill.aliasID)
                    writeKey(
                        .plugin(name: fill.location.plugin, objectID: fill.location.objectID),
                        into: &payload
                    )
                }
            }
        }
    }

    private static func objectiveFlags(_ objective: QuestObjectiveState) -> UInt8 {
        var flags: UInt8 = 0
        if objective.isDisplayed {
            flags |= OpenSkySaveFormat.QuestObjectiveFlag.displayed
        }
        if objective.isCompleted {
            flags |= OpenSkySaveFormat.QuestObjectiveFlag.completed
        }
        if objective.isFailed {
            flags |= OpenSkySaveFormat.QuestObjectiveFlag.failed
        }
        return flags
    }
}
