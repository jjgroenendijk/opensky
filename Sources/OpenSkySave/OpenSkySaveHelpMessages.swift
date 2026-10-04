// HELP chunk: help-message counts per input event, on the player's delta.
// Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// Events in name order, so the same state writes the same bytes.
    public static func writeHelpMessages(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            HelpMessageState.self, tag: OpenSkySaveFormat.ChunkTag.helpMessages, entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.records.count))
            for (event, record) in state.records.sorted(by: { $0.key < $1.key }) {
                writeString(event, into: &payload)
                payload.writeUInt32(UInt32(clamping: max(0, record.timesShown)))
                payload.writeUInt8(record.isDone ? 1 : 0)
            }
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    public static func decodeHelpMessages(
        _ payload: Data
    ) throws -> [SaveStoryEntry<HelpMessageState>] {
        let tag = OpenSkySaveFormat.ChunkTag.helpMessages
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumHelpMessageEntrySize
        ) { reader in
            let count = try reader.uint32("HELP record count")
            try OpenSkySaveDecoder.validate(
                count: count, minimumElementSize: OpenSkySaveFormat.minimumHelpMessageRecordSize,
                remaining: reader.bytesRemaining, chunk: tag
            )
            var records: [String: HelpMessageRecord] = [:]
            for _ in 0 ..< count {
                let event = try reader.string("HELP event")
                let shown = try reader.uint32("HELP times shown")
                let done = try reader.bool("HELP done")
                records[event] = HelpMessageRecord(timesShown: Int(shown), isDone: done)
            }
            return HelpMessageState(records: records)
        }
    }
}
