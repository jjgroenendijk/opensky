// QJLG chunk: the journal's newest log entry per quest, laid onto the QSTS states.
// Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Every quest state with a log entry, in the snapshot's key order.
    public static func writeQuestJournalLogs(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (ReferenceKey, QuestJournalLog)? in
            guard let log = entry.delta.component(QuestRuntimeState.self)?.journalLog
            else { return nil }
            return (entry.key, log)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.questJournalLogs, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (key, log) in saved {
                writeKey(key, into: &payload)
                payload.writeUInt16(log.stage)
                payload.writeUInt32(UInt32(clamping: log.items.count))
                for item in log.items {
                    payload.writeUInt16(item)
                }
            }
        }
    }
}

nonisolated extension OpenSkySaveQuestDecoder {
    public static func decodeQuestJournalLogs(
        _ payload: Data
    ) throws -> [ReferenceKey: QuestJournalLog] {
        let tag = OpenSkySaveFormat.ChunkTag.questJournalLogs
        var reader = SaveReader(payload)
        let count = try reader.uint32("QJLG entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumQuestJournalLogEntrySize,
            remaining: reader.bytesRemaining,
            chunk: tag
        )
        var logs: [ReferenceKey: QuestJournalLog] = [:]
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let stage = try reader.uint16("QJLG stage")
            let itemCount = try reader.uint32("QJLG item count")
            try OpenSkySaveDecoder.validate(
                count: itemCount,
                minimumElementSize: OpenSkySaveFormat.questStageSize,
                remaining: reader.bytesRemaining,
                chunk: tag
            )
            var items: [UInt16] = []
            for _ in 0 ..< itemCount {
                try items.append(reader.uint16("QJLG item"))
            }
            logs[key] = QuestJournalLog(stage: stage, items: items)
        }
        return logs
    }

    /// A log for a quest `QSTS` does not name is dropped: the quest was never touched.
    static func applying(
        _ logs: [ReferenceKey: QuestJournalLog],
        to quests: [SaveQuestEntry]
    ) -> [SaveQuestEntry] {
        guard !logs.isEmpty else { return quests }
        return quests.map { entry in
            guard let log = logs[entry.key] else { return entry }
            let state = entry.state
            return SaveQuestEntry(key: entry.key, state: QuestRuntimeState(
                isRunning: state.isRunning,
                isCompleted: state.isCompleted,
                stagesReached: state.stagesReached,
                objectives: state.objectives,
                isFailed: state.isFailed,
                journalLog: log
            ))
        }
    }
}
