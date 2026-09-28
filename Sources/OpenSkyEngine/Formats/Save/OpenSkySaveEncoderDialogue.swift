// DLGS chunk writing for the OpenSky native save container (issue #426).
//
// A satellite of `OpenSkySaveEncoder` for the same reason the QSTS writer is
// one: that type is at its length limit, and a chunk's writer belongs beside
// the decoder that reads it back rather than inside a growing switch.
//
// No cell travels with a dialogue entry, unlike an inventory entry. An INFO is
// a base record that belongs to no cell, so its delta's cell is always absent
// and writing the tag would be a byte that can only ever hold one value.

import Foundation

nonisolated extension OpenSkySaveEncoder {
    /// The `DLGS` chunk: every snapshot entry carrying a dialogue component
    /// that is not the untouched baseline, in the snapshot's `ReferenceKey`
    /// order. A session in which nobody spoke writes no chunk.
    ///
    /// An untouched state is deliberately skipped rather than written as a
    /// zero. It is the state every INFO has before anything says it, and the
    /// decoder restores exactly that for an INFO the chunk does not mention, so
    /// writing it would only make the file bigger and two equal worlds differ.
    static func writeDialogueStates(
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
