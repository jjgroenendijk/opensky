// PRKS chunk decoding for the OpenSky native save container (issue #497).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `SPLB`, `AEFF` and `AVAL`: an actor whose only delta is its perk list has
// no `RDLT` entry, so merging by `ReferenceKey` is what lets the encoder omit
// one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// Nothing here rejects a perk list on content. A duplicate key collapses in
// `PerkState.init`, and a key this load order no longer carries is kept — the
// same rule a known spell follows, because removing a plugin must not destroy
// progress.

import Foundation

/// One actor's saved perks, before they are merged back into the delta.
nonisolated struct SavePerkEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: PerkState
}

nonisolated enum OpenSkySavePerkDecoder {
    static func decodePerks(_ payload: Data) throws -> [SavePerkEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PRKS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPerkEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.perks
        )
        var entries: [SavePerkEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved perk list over the matching `RDLT` delta, adding an entry
    /// for an actor that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ values: [SavePerkEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + values.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in values where !entry.state.isEmpty {
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

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SavePerkEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("PRKS owned count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPerkKeySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.perks
        )
        var owned: [ReferenceKey] = []
        owned.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try owned.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
        }
        return SavePerkEntry(key: key, cell: cell, state: PerkState(owned: owned))
    }
}
