// DLGS chunk: said-state per INFO, merged into the `RDLT` deltas by `ReferenceKey`.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One INFO's saved said-state, before it is merged back into its delta.
nonisolated public struct SaveDialogueEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let state: DialogueRuntimeState
}

nonisolated public enum OpenSkySaveDialogueDecoder: Sendable {
    public static func decodeDialogueStates(_ payload: Data) throws -> [SaveDialogueEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("DLGS entry count")
        try OpenSkySaveDecoder.validate(
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

nonisolated extension SaveDialogueEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        nil
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isUntouched ? nil : state.erased
    }
}
