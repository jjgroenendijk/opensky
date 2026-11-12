// DLGS and DLGT chunks: said-state per INFO, merged into the `RDLT` deltas by
// `ReferenceKey`. DLGT adds the day each speaker last said an INFO.

import Foundation
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One INFO's saved said-state, before it is merged back into its delta.
nonisolated struct SaveDialogueEntry: Equatable, Sendable {
    let key: ReferenceKey
    let state: DialogueRuntimeState
}

nonisolated extension OpenSkySaveDecoder {
    enum DialogueDecoder: Sendable {
        static func decodeSaidDays(
            _ payload: Data
        ) throws -> [ReferenceKey: [ReferenceKey: Double]] {
            var reader = SaveReader(payload)
            let count = try reader.uint32("DLGT entry count")
            try validate(count, OpenSkySaveFormat.minimumDialogueSaidDayEntrySize, reader)
            var days: [ReferenceKey: [ReferenceKey: Double]] = [:]
            for _ in 0 ..< count {
                let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                let speakers = try reader.uint32("DLGT speaker count")
                try validate(speakers, OpenSkySaveFormat.minimumDialogueSaidDaySpeakerSize, reader)
                var bySpeaker: [ReferenceKey: Double] = [:]
                for _ in 0 ..< speakers {
                    let speaker = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                    let day = try Double(bitPattern: reader.uint64("DLGT said day"))
                    if day.isFinite {
                        bySpeaker[speaker] = day
                    }
                }
                days[key] = bySpeaker
            }
            return days
        }

        private static func validate(_ count: UInt32, _ size: Int, _ reader: SaveReader) throws {
            try SaveCountCheck.validate(
                count: count,
                minimumElementSize: size,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.dialogueSaidDays
            )
        }

        /// The `DLGS` entries with their `DLGT` days. A day for an INFO `DLGS` does
        /// not name is dropped, because a count of 0 is the unsaid baseline.
        static func withSaidDays(
            _ days: [ReferenceKey: [ReferenceKey: Double]],
            in entries: [SaveDialogueEntry]
        ) -> [SaveDialogueEntry] {
            guard !days.isEmpty else { return entries }
            return entries.map { entry in
                SaveDialogueEntry(key: entry.key, state: DialogueRuntimeState(
                    saidCount: entry.state.saidCount, saidDays: days[entry.key] ?? [:]
                ))
            }
        }

        static func decodeDialogueStates(_ payload: Data) throws -> [SaveDialogueEntry] {
            var reader = SaveReader(payload)
            let count = try reader.uint32("DLGS entry count")
            try SaveCountCheck.validate(
                count: count,
                minimumElementSize: OpenSkySaveFormat.minimumDialogueEntrySize,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.dialogueStates
            )
            var entries: [SaveDialogueEntry] = []
            entries.reserveCapacity(Int(count))
            for _ in 0 ..< count {
                let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                let said = try reader.uint32("DLGS said count")
                entries.append(SaveDialogueEntry(
                    key: key, state: DialogueRuntimeState(saidCount: said)
                ))
            }
            return entries
        }
    }
}

nonisolated extension SaveDialogueEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        nil
    }

    var deltaComponent: WorldStateComponentValue? {
        state.isUntouched ? nil : state.erased
    }
}
