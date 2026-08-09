// DLGS chunk decoding for the OpenSky native save container (issue #426).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `QSTS`: an INFO has no placement, so its key normally appears in no
// other chunk, and merging by `ReferenceKey` is what lets the encoder omit an
// `RDLT` entry that would otherwise hold nothing.
//
// Bounds, as everywhere else in this decoder: the declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.

import Foundation

/// One INFO's saved said-state, before it is merged back into its delta.
nonisolated struct SaveDialogueEntry: Equatable, Sendable {
    let key: ReferenceKey
    let state: DialogueRuntimeState
}

nonisolated enum OpenSkySaveDialogueDecoder {
    static func decodeDialogueStates(_ payload: Data) throws -> [SaveDialogueEntry] {
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

    /// Lays each saved said-state over the matching `RDLT` delta, adding an
    /// entry for an INFO that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order — the order `WorldStateSnapshot`
    /// promises, which a chunk-order insertion would otherwise break.
    ///
    /// An entry whose count decodes as zero is dropped rather than stored. The
    /// encoder never writes one, so it can only come from a corrupt or
    /// hand-built file, and storing the baseline as a delta would make a
    /// restored world compare unequal to the one that was saved.
    static func merge(
        _ dialogue: [SaveDialogueEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        let written = dialogue.filter { !$0.state.isUntouched }
        guard !written.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + written.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in written {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta()
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }
}
