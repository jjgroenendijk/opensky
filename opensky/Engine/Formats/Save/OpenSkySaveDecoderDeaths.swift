// DETH chunk decoding for the OpenSky native save container (issue #197).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `INVN`, `QSTS` and `AVAL`: an actor whose only delta is its death has no
// `RDLT` entry, so merging by `ReferenceKey` is what lets the encoder omit one.
//
// Bounds, as everywhere else in this decoder: the declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.

import Foundation

/// One actor's saved death, before it is merged back into the delta.
nonisolated struct SaveDeathEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorDeathState
}

nonisolated enum OpenSkySaveDeathDecoder {
    static func decodeDeaths(_ payload: Data) throws -> [SaveDeathEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("DETH entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumDeathEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.deaths
        )
        var entries: [SaveDeathEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved death over the matching `RDLT` delta, adding an entry
    /// for an actor that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ deaths: [SaveDeathEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !deaths.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + deaths.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in deaths {
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

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveDeathEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let isDead = try reader.uint8("DETH isDead") != 0
        let wasLooted = try reader.uint8("DETH wasLooted") != 0
        let transform = try decodeRestingTransform(&reader)
        return SaveDeathEntry(
            key: key,
            cell: cell,
            state: ActorDeathState(
                isDead: isDead, restingTransform: transform, wasLooted: wasLooted
            )
        )
    }

    private static func decodeRestingTransform(
        _ reader: inout SaveReader
    ) throws -> ReferenceTransformOverride? {
        guard try reader.uint8("DETH resting transform present") != 0 else { return nil }
        let position = try vector(&reader, named: "DETH resting position")
        let rotation = try vector(&reader, named: "DETH resting rotation")
        let scale = try reader.float32("DETH resting scale")
        return ReferenceTransformOverride(
            position: position, rotation: rotation, scale: scale
        )
    }

    private static func vector(
        _ reader: inout SaveReader,
        named name: String
    ) throws -> SIMD3<Float> {
        try SIMD3(
            reader.float32("\(name).x"),
            reader.float32("\(name).y"),
            reader.float32("\(name).z")
        )
    }
}
