// SCNS, SMQS, and DLBS chunks: playing scenes, the story manager's per-quest
// start record, and the exclusive dialogue branch a speaker is in. Each merges
// into the `RDLT` deltas by key. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// One saved component of a story chunk, before it is merged back into the delta.
nonisolated public struct SaveStoryEntry<State: WorldStateComponent>: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: State
}

nonisolated extension SaveStoryEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.erased
    }
}

nonisolated extension OpenSkySaveEncoder {
    /// Every playing scene. No scene writes no chunk.
    public static func writeScenes(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            SceneRuntimeState.self,
            tag: OpenSkySaveFormat.ChunkTag.scenes,
            entries,
            &writer
        ) { state, payload in
            payload.writeUInt32(state.phase)
            payload.writeUInt8(state.phaseEntered ? 1 : 0)
            payload.writeUInt32(UInt32(clamping: state.running.count))
            for progress in state.running {
                payload.writeUInt32(progress.action)
                payload.writeUInt64(progress.startedAt.bitPattern)
                payload.writeUInt8(progress.duration == nil ? 0 : 1)
                payload.writeFloat32(progress.duration ?? 0)
            }
            payload.writeUInt32(UInt32(clamping: state.completed.count))
            for action in state.completed {
                payload.writeUInt32(action)
            }
        }
    }

    /// Every quest the story manager started.
    public static func writeStoryManagerQuests(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            StoryManagerQuestState.self, tag: OpenSkySaveFormat.ChunkTag.storyManagerQuests,
            entries, &writer
        ) { state, payload in
            payload.writeUInt64(state.lastStartSeconds.bitPattern)
            payload.writeUInt32(state.startCount)
        }
    }

    /// Every speaker in an exclusive branch.
    public static func writeDialogueBranches(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        writeStory(
            DialogueBranchState.self, tag: OpenSkySaveFormat.ChunkTag.dialogueBranches,
            entries, &writer
        ) { state, payload in
            payload.writeUInt32(state.exclusiveBranch.rawValue)
        }
    }

    static func writeStory<State: WorldStateComponent>(
        _: State.Type,
        tag: String,
        _ entries: [WorldStateSnapshotEntry],
        _ writer: inout BinaryWriter,
        body: (State, inout BinaryWriter) -> Void
    ) {
        let saved = entries
            .compactMap { entry in entry.delta.component(State.self).map { (entry, $0) } }
        guard !saved.isEmpty else { return }
        writeChunk(tag: tag, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, state) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                body(state, &payload)
            }
        }
    }
}

nonisolated public enum OpenSkySaveStoryDecoder: Sendable {
    public static func decodeScenes(_ payload: Data) throws -> [SaveStoryEntry<SceneRuntimeState>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.scenes,
            minimumSize: OpenSkySaveFormat.minimumSceneEntrySize
        ) { reader in
            let phase = try reader.uint32("SCNS phase")
            let entered = try reader.bool("SCNS phase entered")
            let runningCount = try reader.uint32("SCNS running count")
            try OpenSkySaveDecoder.validate(
                count: runningCount, minimumElementSize: OpenSkySaveFormat.sceneActionRecordSize,
                remaining: reader.bytesRemaining, chunk: OpenSkySaveFormat.ChunkTag.scenes
            )
            var running: [SceneActionProgress] = []
            for _ in 0 ..< runningCount {
                let action = try reader.uint32("SCNS action")
                let startedAt = try Double(bitPattern: reader.uint64("SCNS started at"))
                let timed = try reader.bool("SCNS timed")
                let duration = try reader.float32("SCNS duration")
                guard startedAt.isFinite else {
                    throw OpenSkySaveError.invalidValue(context: "SCNS start time is not finite")
                }
                running.append(SceneActionProgress(
                    action: action, startedAt: startedAt, duration: timed ? duration : nil
                ))
            }
            let completedCount = try reader.uint32("SCNS completed count")
            try OpenSkySaveDecoder.validate(
                count: completedCount, minimumElementSize: 4,
                remaining: reader.bytesRemaining, chunk: OpenSkySaveFormat.ChunkTag.scenes
            )
            let completed = try (0 ..< completedCount)
                .map { _ in try reader.uint32("SCNS completed") }
            return SceneRuntimeState(
                phase: phase, phaseEntered: entered, running: running, completed: completed
            )
        }
    }

    public static func decodeStoryManagerQuests(
        _ payload: Data
    ) throws -> [SaveStoryEntry<StoryManagerQuestState>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.storyManagerQuests,
            minimumSize: OpenSkySaveFormat.minimumStoryManagerQuestEntrySize
        ) { reader in
            let seconds = try Double(bitPattern: reader.uint64("SMQS last start"))
            guard seconds.isFinite else {
                throw OpenSkySaveError.invalidValue(context: "SMQS start time is not finite")
            }
            return try StoryManagerQuestState(
                lastStartSeconds: seconds, startCount: reader.uint32("SMQS start count")
            )
        }
    }

    public static func decodeDialogueBranches(
        _ payload: Data
    ) throws -> [SaveStoryEntry<DialogueBranchState>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.dialogueBranches,
            minimumSize: OpenSkySaveFormat.minimumDialogueBranchEntrySize
        ) { reader in
            try DialogueBranchState(exclusiveBranch: FormID(reader.uint32("DLBS branch")))
        }
    }

    static func decode<State: WorldStateComponent>(
        _ payload: Data,
        tag: String,
        minimumSize: Int,
        state: (inout SaveReader) throws -> State
    ) throws -> [SaveStoryEntry<State>] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("\(tag) entry count")
        try OpenSkySaveDecoder.validate(
            count: count, minimumElementSize: minimumSize,
            remaining: reader.bytesRemaining, chunk: tag
        )
        var entries: [SaveStoryEntry<State>] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            try entries.append(SaveStoryEntry(key: key, cell: cell, state: state(&reader)))
        }
        return entries
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// The story chunks. Any other tag is unknown and skipped by its declared length.
    static func applyStory(tag: String, payload: Data, to body: inout Body) throws {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.scenes:
            body.scenes = try OpenSkySaveStoryDecoder.decodeScenes(payload)
        case OpenSkySaveFormat.ChunkTag.storyManagerQuests:
            body.storyManagerQuests = try OpenSkySaveStoryDecoder.decodeStoryManagerQuests(payload)
        case OpenSkySaveFormat.ChunkTag.dialogueBranches:
            body.dialogueBranches = try OpenSkySaveStoryDecoder.decodeDialogueBranches(payload)
        case OpenSkySaveFormat.ChunkTag.helpMessages:
            body.helpMessages = try OpenSkySaveStoryDecoder.decodeHelpMessages(payload)
        case OpenSkySaveFormat.ChunkTag.playerIdentity:
            body.identities = try OpenSkySaveStoryDecoder.decodeIdentities(payload)
        case OpenSkySaveFormat.ChunkTag.mapMarkers:
            body.markers = try OpenSkySaveStoryDecoder.decodeMarkers(payload)
        case OpenSkySaveFormat.ChunkTag.localMapFog:
            body.fog = try OpenSkySaveStoryDecoder.decodeFog(payload)
        default:
            break
        }
    }
}
