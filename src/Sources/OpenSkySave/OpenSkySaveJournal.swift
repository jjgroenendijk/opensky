// MSTS and QTRK chunks: the player's misc stats, and which quests the player
// tracks. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyQuestsInterface
import OpenSkyWorldState

nonisolated enum OpenSkySaveJournalWriter {
    static func writeJournal(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeMiscStats(entries, into: &writer)
        writeQuestTracking(entries, into: &writer)
    }

    static func writeSceneChunks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveStoryWriter.writeScenes(entries, into: &writer)
        OpenSkySaveStoryWriter.writeScenePauses(entries, into: &writer)
    }

    /// Stats in name order, so the same state writes the same bytes.
    static func writeMiscStats(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveStoryWriter.writeStory(
            (MiscStatsState.self, OpenSkySaveFormat.ChunkTag.miscStats), entries, &writer
        ) { state, payload in
            payload.writeUInt32(UInt32(clamping: state.values.count))
            for (name, value) in state.values.sorted(by: { $0.key < $1.key }) {
                payload.writeString(name)
                payload.writeUInt32(UInt32(bitPattern: value))
            }
        }
    }

    static func writeQuestTracking(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        OpenSkySaveStoryWriter.writeStory(
            (QuestTrackingState.self, OpenSkySaveFormat.ChunkTag.questTracking),
            entries, &writer
        ) { state, payload in
            payload.writeUInt8(state.isTracked ? 1 : 0)
        }
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    static func decodeMiscStats(_ payload: Data) throws -> [SaveStoryEntry<MiscStatsState>] {
        let tag = OpenSkySaveFormat.ChunkTag.miscStats
        return try decode(
            payload, tag: tag, minimumSize: OpenSkySaveFormat.minimumMiscStatsEntrySize
        ) { reader in
            let count = try reader.uint32("MSTS stat count")
            try SaveCountCheck.validate(
                count: count, minimumElementSize: OpenSkySaveFormat.minimumMiscStatRecordSize,
                remaining: reader.bytesRemaining, chunk: tag
            )
            var values: [String: Int32] = [:]
            for _ in 0 ..< count {
                let name = try reader.string("MSTS stat name")
                values[name] = try Int32(bitPattern: reader.uint32("MSTS stat value"))
            }
            return MiscStatsState(values: values)
        }
    }

    static func decodeQuestTracking(
        _ payload: Data
    ) throws -> [SaveStoryEntry<QuestTrackingState>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.questTracking,
            minimumSize: OpenSkySaveFormat.questTrackingEntrySize
        ) { reader in
            try QuestTrackingState(isTracked: reader.bool("QTRK tracked"))
        }
    }
}

nonisolated extension OpenSkySaveDecoder {
    static func applyJournal(tag: String, payload: Data, to body: inout Body) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.miscStats:
            body.side.miscStats = try OpenSkySaveStoryDecoder.decodeMiscStats(payload)
        case OpenSkySaveFormat.ChunkTag.questTracking:
            body.side.questTracking = try OpenSkySaveStoryDecoder.decodeQuestTracking(payload)
        case OpenSkySaveFormat.ChunkTag.cellResets:
            body.side.cellResets = try [OpenSkySaveCellResetDecoder.decode(payload)]
        case OpenSkySaveFormat.ChunkTag.vendorRestocks:
            body.side.vendorRestocks = try [OpenSkySaveVendorRestockDecoder.decode(payload)]
        default:
            break
        }
    }
}

nonisolated extension OpenSkySaveDecoder.Body {
    static func mergeJournal(
        _ body: Self,
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        let merged = OpenSkySaveDeltaMerge.merge(body.side.miscStats, into: entries)
        let tracked = OpenSkySaveDeltaMerge.merge(body.side.questTracking, into: merged)
        let reset = OpenSkySaveDeltaMerge.merge(body.side.cellResets, into: tracked)
        return OpenSkySaveDeltaMerge.merge(body.side.vendorRestocks, into: reset)
    }
}

nonisolated extension OpenSkySaveSideChunks {
    /// `SCNS` scenes with their `SCNP` pause times laid on.
    var pausedScenes: [SaveStoryEntry<SceneRuntimeState>] {
        OpenSkySaveStoryDecoder.applying(scenePauses, to: scenes)
    }
}
