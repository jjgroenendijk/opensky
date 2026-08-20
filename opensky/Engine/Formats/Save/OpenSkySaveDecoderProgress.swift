// PLVL chunk decoding for the OpenSky native save container (issue #499).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `PRKS`, `SPLB` and `AVAL`: the player's only delta may be its progress,
// in which case there is no `RDLT` entry to hang it on, so merging by
// `ReferenceKey` is what lets the encoder omit one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// Nothing here rejects a record on content. `PlayerProgressState.init` clamps
// every field, and a pick naming an actor value that is not one of the three
// primaries is dropped rather than failing the file — a save written by a build
// that stored something else there must still load.

import Foundation

/// One actor's saved character-level progress, before it is merged back into
/// the delta.
nonisolated struct SavePlayerProgressEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: PlayerProgressState
}

nonisolated enum OpenSkySaveProgressDecoder {
    static func decodePlayerProgress(_ payload: Data) throws -> [SavePlayerProgressEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PLVL entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPlayerProgressEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.playerProgress
        )
        var entries: [SavePlayerProgressEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved record over the matching `RDLT` delta, adding an entry
    /// for a key that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ values: [SavePlayerProgressEntry],
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

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SavePlayerProgressEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let level = try reader.uint32("PLVL level")
        let experience = try reader.float32("PLVL experience")
        let perkPoints = try reader.uint32("PLVL perk points")
        let pending = try reader.uint32("PLVL pending attribute picks")
        let increases = try reader.uint32("PLVL skill increases")
        let pickCount = try reader.uint32("PLVL attribute pick count")
        try OpenSkySaveDecoder.validate(
            count: pickCount,
            minimumElementSize: OpenSkySaveFormat.playerProgressPickSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.playerProgress
        )
        var picks: [ActorValueKind] = []
        picks.reserveCapacity(Int(pickCount))
        for _ in 0 ..< pickCount {
            let index = try Int32(bitPattern: reader.uint32("PLVL attribute pick"))
            guard let kind = ActorValueIdentity.kind(at: index) else { continue }
            picks.append(kind)
        }
        return SavePlayerProgressEntry(
            key: key,
            cell: cell,
            state: PlayerProgressState(
                level: Int(level),
                experience: experience,
                perkPoints: Int(perkPoints),
                pendingAttributePicks: Int(pending),
                attributePicks: picks,
                skillIncreases: Int(increases)
            )
        )
    }
}
