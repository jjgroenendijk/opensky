// DLGS and DLGT chunk writing. No cell: an INFO is a base record, so the cell is always absent.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated extension OpenSkySaveEncoder {
    private typealias SavedState = (key: ReferenceKey, state: DialogueRuntimeState)

    /// The `DLGS` chunk: every non-baseline dialogue component, in key order. The
    /// untouched state is skipped, because the decoder restores it for any unnamed INFO.
    public static func writeDialogueStates(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> SavedState? in
            guard
                let state = entry.delta.component(DialogueRuntimeState.self),
                !state.isUntouched
            else {
                return nil
            }
            return (key: entry.key, state: state)
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.dialogueStates, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for each in saved {
                writeKey(each.key, into: &payload)
                payload.writeUInt32(each.state.saidCount)
            }
        }
        let timed = saved.filter { !$0.state.saidDays.isEmpty }
        guard !timed.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.dialogueSaidDays, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: timed.count))
            for each in timed {
                writeKey(each.key, into: &payload)
                let speakers = each.state.saidDays.sorted { $0.key < $1.key }
                payload.writeUInt32(UInt32(clamping: speakers.count))
                for (speaker, day) in speakers {
                    writeKey(speaker, into: &payload)
                    payload.writeUInt64(day.bitPattern)
                }
            }
        }
    }
}
