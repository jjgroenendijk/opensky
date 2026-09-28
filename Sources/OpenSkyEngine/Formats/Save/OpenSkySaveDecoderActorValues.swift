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

/// One actor's saved current values, before they are merged back into the
/// delta.
nonisolated struct SaveActorValueEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorValueState
}

/// One actor's saved actor-value overrides (issue #496), before they are merged
/// onto that actor's `AVAL` entry.
nonisolated struct SaveActorValueOverrideEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let overrides: [Int32: ActorValueOverride]
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

    /// `AVOV` (issue #496): one entry per actor holding actor-value overrides,
    /// each a list of `(index, base offset, permanent, damage)` records.
    static func decodeActorValueOverrides(
        _ payload: Data
    ) throws -> [SaveActorValueOverrideEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("AVOV entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActorValueOverrideEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.actorValueOverrides
        )
        var entries: [SaveActorValueOverrideEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeOverrideEntry(&reader))
        }
        return entries
    }

    /// Lays each actor's override table onto the `AVAL` entry for the same
    /// reference.
    ///
    /// An `AVOV` entry with no `AVAL` entry beside it is dropped rather than
    /// turned into a state of its own. The encoder writes both together, so an
    /// orphan means a hand-edited or truncated file, and the alternative would
    /// be inventing a health for an actor whose health the save never carried.
    static func mergeOverrides(
        _ overrides: [SaveActorValueOverrideEntry],
        into values: [SaveActorValueEntry]
    ) -> [SaveActorValueEntry] {
        guard !overrides.isEmpty else { return values }
        var tables: [ReferenceKey: [Int32: ActorValueOverride]] = [:]
        for entry in overrides {
            tables[entry.key] = entry.overrides
        }
        return values.map { entry in
            guard let table = tables[entry.key] else { return entry }
            return SaveActorValueEntry(
                key: entry.key,
                cell: entry.cell,
                state: ActorValueState(current: entry.state.current, overrides: table)
            )
        }
    }

    // MARK: - Private

    private static func decodeOverrideEntry(
        _ reader: inout SaveReader
    ) throws -> SaveActorValueOverrideEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("AVOV value count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.actorValueOverrideRecordSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.actorValueOverrides
        )
        var overrides: [Int32: ActorValueOverride] = [:]
        overrides.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let index = try Int32(bitPattern: reader.uint32("AVOV actor value index"))
            let baseOffset = try reader.float32("AVOV base offset")
            let permanent = try reader.float32("AVOV permanent modifier")
            let damage = try reader.float32("AVOV damage modifier")
            // A non-finite float is normalized by `ActorValueOverride.init`
            // rather than rejected here, for the reason a corrupt current value
            // is: the invariant belongs to the type, and one nonsensical number
            // is not a reason to fail a whole save. An index outside the table
            // is dropped by `ActorValueState.init` for the same reason.
            overrides[index] = ActorValueOverride(
                baseOffset: baseOffset,
                permanent: permanent,
                damage: damage
            )
        }
        return SaveActorValueOverrideEntry(key: key, cell: cell, overrides: overrides)
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
