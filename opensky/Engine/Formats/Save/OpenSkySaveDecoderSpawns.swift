// SPWN chunk decoding for the OpenSky native save container (issue #177).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly as
// `INVN` is: a spawned object usually has no `RDLT` entry at all, and one that
// has been moved or taken again has both. Merging by `ReferenceKey` is what
// lets the encoder omit the `RDLT` entry in the common case.
//
// Bounds, as everywhere else in this decoder: every declared count is checked
// against the bytes actually left before an array is reserved.

import Foundation
import simd

/// One saved spawned object, before it is merged back into its delta.
nonisolated struct SaveSpawnEntry: Equatable, Sendable {
    let key: ReferenceKey
    let spawn: ReferenceSpawnState
}

nonisolated enum OpenSkySaveSpawnDecoder {
    static func decodeSpawns(_ payload: Data) throws -> [SaveSpawnEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("SPWN entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumSpawnEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.spawnedReferences
        )
        var entries: [SaveSpawnEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved spawn over the matching `RDLT` delta, adding an entry
    /// for an object that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order — the order `WorldStateSnapshot` promises.
    static func merge(
        _ spawns: [SaveSpawnEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !spawns.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + spawns.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in spawns {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.spawn.location)
            delta.set(entry.spawn.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    // MARK: - Private

    /// An entry whose cell tag says "absent" is rejected rather than defaulted:
    /// `ReferenceSpawnState` requires a cell because an object with none is not
    /// in the world, and inventing one would put a dropped item somewhere the
    /// player never stood.
    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveSpawnEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let base = try FormID(reader.uint32("SPWN base form ID"))
        guard let location = try OpenSkySaveEntryDecoder.decodeCell(&reader) else {
            throw OpenSkySaveError.invalidValue(
                context: "SPWN entry for \(key) names no cell"
            )
        }
        let position = try vector(&reader, "SPWN position")
        let rotation = try vector(&reader, "SPWN rotation")
        let scale = try reader.float32("SPWN scale")
        let count = try Int32(bitPattern: reader.uint32("SPWN count"))
        return SaveSpawnEntry(
            key: key,
            spawn: ReferenceSpawnState(
                base: base,
                location: location,
                placement: PlacedReference.Placement(position: position, rotation: rotation),
                scale: scale,
                count: count
            )
        )
    }

    private static func vector(
        _ reader: inout SaveReader,
        _ context: String
    ) throws -> SIMD3<Float> {
        let x = try reader.float32("\(context) x")
        let y = try reader.float32("\(context) y")
        let z = try reader.float32("\(context) z")
        return SIMD3(x, y, z)
    }
}
