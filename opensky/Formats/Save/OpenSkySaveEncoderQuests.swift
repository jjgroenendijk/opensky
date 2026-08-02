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
