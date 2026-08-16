// AVAL chunk decoding for the OpenSky native save container (issue #194).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `INVN` and `QSTS`: an actor whose only delta is its values has no `RDLT`
// entry, so merging by `ReferenceKey` is what lets the encoder omit one.
//
// Bounds, as everywhere else in this decoder: the declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// A non-finite or negative float is normalized to zero by
// `ActorValueState.init` rather than rejected here, for the same reason a
// duplicate quest stage is: the invariant belongs to the type, and one
// nonsensical value is not a reason to fail a whole save.

import Foundation

/// One actor's saved values, before they are merged back into the delta.
nonisolated struct SaveActorValueEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorValueState
}

/// One actor's saved non-primary actor values (issue #468), before they are
/// merged onto that actor's `AVAL` entry.
nonisolated struct SaveGeneralActorValueEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let general: [Int32: ActorValueEntry]
}

nonisolated enum OpenSkySaveActorValueDecoder {
    static func decodeActorValues(_ payload: Data) throws -> [SaveActorValueEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("AVAL entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActorValueEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.actorValues
        )
        var entries: [SaveActorValueEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved state over the matching `RDLT` delta, adding an entry
    /// for an actor that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order — the order `WorldStateSnapshot` promises,
    /// which a chunk-order insertion would otherwise break.
    static func merge(
        _ values: [SaveActorValueEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + values.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in values {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    /// `AVGN` (issue #468): one entry per actor holding non-primary actor
    /// values, each a list of `(index, base, permanent, damage)` records.
    static func decodeGeneralActorValues(
        _ payload: Data
    ) throws -> [SaveGeneralActorValueEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("AVGN entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumGeneralActorValueEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.generalActorValues
        )
        var entries: [SaveGeneralActorValueEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeGeneralEntry(&reader))
        }
        return entries
    }

    /// Lays each actor's general table onto the `AVAL` entry for the same
    /// reference.
    ///
    /// An `AVGN` entry with no `AVAL` entry beside it is dropped rather than
    /// turned into a state of its own. The encoder writes both together, so an
    /// orphan means a hand-edited or truncated file, and the alternative would
    /// be inventing a health for an actor whose health the save never carried.
    static func mergeGeneral(
        _ general: [SaveGeneralActorValueEntry],
        into values: [SaveActorValueEntry]
    ) -> [SaveActorValueEntry] {
        guard !general.isEmpty else { return values }
        var tables: [ReferenceKey: [Int32: ActorValueEntry]] = [:]
        for entry in general {
            tables[entry.key] = entry.general
        }
        return values.map { entry in
            guard let table = tables[entry.key] else { return entry }
            return SaveActorValueEntry(
                key: entry.key,
                cell: entry.cell,
                state: ActorValueState(current: entry.state.current, general: table)
            )
        }
    }

    // MARK: - Private

    private static func decodeGeneralEntry(
        _ reader: inout SaveReader
    ) throws -> SaveGeneralActorValueEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("AVGN value count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.generalActorValueRecordSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.generalActorValues
        )
        var general: [Int32: ActorValueEntry] = [:]
        general.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let index = try Int32(bitPattern: reader.uint32("AVGN actor value index"))
            let base = try reader.float32("AVGN base")
            let permanent = try reader.float32("AVGN permanent modifier")
            let damage = try reader.float32("AVGN damage modifier")
            // A non-finite float is normalized by `ActorValueEntry.init` rather
            // than rejected here, for the reason a corrupt current value is:
            // the invariant belongs to the type, and one nonsensical number is
            // not a reason to fail a whole save. An index outside the table is
            // dropped by `ActorValueState.init` for the same reason.
            general[index] = ActorValueEntry(base: base, permanent: permanent, damage: damage)
        }
        return SaveGeneralActorValueEntry(key: key, cell: cell, general: general)
    }

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveActorValueEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        var current = ActorValues.zero
        for kind in ActorValueKind.allCases {
            current[kind] = try reader.float32("AVAL \(kind.rawValue)")
        }
        return SaveActorValueEntry(
            key: key,
            cell: cell,
            state: ActorValueState(current: current)
        )
    }
}
