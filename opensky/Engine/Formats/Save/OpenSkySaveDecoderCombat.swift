// CBTS chunk decoding for the OpenSky native save container (issue #374).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `INVN`, `QSTS`, `AVAL` and `DETH`: an actor whose only delta is its
// hostility has no `RDLT` entry, so merging by `ReferenceKey` is what lets the
// encoder omit one.
//
// Bounds, as everywhere else in this decoder: the declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// An unknown hostility byte decodes as neutral rather than throwing. A future
// build may add a third regard, and a save that carries one should load with
// that actor calm rather than refuse to load at all — the same tolerance the
// chunk stream itself provides one level up.

import Foundation

/// One actor's saved hostility, before it is merged back into the delta.
nonisolated struct SaveCombatStateEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorCombatState
}

nonisolated enum OpenSkySaveCombatDecoder {
    static func decodeCombatStates(_ payload: Data) throws -> [SaveCombatStateEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CBTS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumCombatStateEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.combatStates
        )
        var entries: [SaveCombatStateEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved hostility over the matching `RDLT` delta, adding an
    /// entry for an actor that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order.
    static func merge(
        _ states: [SaveCombatStateEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !states.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + states.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in states {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    // MARK: - Private

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SaveCombatStateEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let raw = try reader.uint8("CBTS hostility")
        return SaveCombatStateEntry(
            key: key,
            cell: cell,
            state: ActorCombatState(hostility: ActorHostility(rawValue: raw) ?? .neutral)
        )
    }
}
