// DLGS chunk writing. No cell: an INFO is a base record, so the cell is always absent.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    /// The `DLGS` chunk: every non-baseline dialogue component, in key order. The
    /// untouched state is skipped, because the decoder restores it for any unnamed INFO.
    public static func writeDialogueStates(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (key: ReferenceKey, said: UInt32)? in
            guard
                let state = entry.delta.component(DialogueRuntimeState.self),
                !state.isUntouched
            else {
                return nil
            }
            return (key: entry.key, said: state.saidCount)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.dialogueStates, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.key, into: &payload)
                payload.writeUInt32(each.said)
            }
        }
    }
}
