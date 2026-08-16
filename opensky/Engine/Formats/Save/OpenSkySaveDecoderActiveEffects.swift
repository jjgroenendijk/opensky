// AEFF chunk decoding for the OpenSky native save container (issue #469).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `AVAL` and `DETH`: an actor whose only delta is its effects has no
// `RDLT` entry, so merging by `ReferenceKey` is what lets the encoder omit one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// A nonsensical float, a duration of zero or an effect with no values is
// normalized away by `ActiveEffect.init` and `ActiveEffectState.init` rather
// than rejected here, for the same reason a corrupt current value is: the
// invariant belongs to the type, and one bad effect is not a reason to fail a
// whole save. An unknown source kind or mode is the one hard stop — both are
// closed enumerations this build wrote itself, so an unreadable one means the
// bytes are not what they claim to be.

import Foundation

/// One actor's saved active effects, before they are merged back into the
/// delta.
nonisolated struct SaveActiveEffectEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActiveEffectState
}

nonisolated enum OpenSkySaveActiveEffectDecoder {
    static func decodeActiveEffects(_ payload: Data) throws -> [SaveActiveEffectEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("AEFF entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActiveEffectEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var entries: [SaveActiveEffectEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved effect list over the matching `RDLT` delta, adding an
    /// entry for an actor that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order.
    static func merge(
        _ values: [SaveActiveEffectEntry],
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

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveActiveEffectEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("AEFF effect count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumActiveEffectSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var effects: [ActiveEffect] = []
        effects.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try effects.append(decodeEffect(&reader))
        }
        return SaveActiveEffectEntry(
            key: key,
            cell: cell,
            state: ActiveEffectState(effects: effects)
        )
    }

    private static func decodeEffect(_ reader: inout SaveReader) throws -> ActiveEffect {
        let sequence = try reader.uint64("AEFF effect sequence")
        let rawKind = try reader.uint32("AEFF source kind")
        guard let kind = ActiveEffectSourceKind(rawValue: rawKind) else {
            throw OpenSkySaveError.invalidValue(context: "AEFF source kind \(rawKind) is unknown")
        }
        let record = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let effect = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let caster = try decodeOptionalKey(&reader)
        let rawMode = try reader.uint32("AEFF mode")
        guard let mode = ActiveEffectMode(rawValue: rawMode) else {
            throw OpenSkySaveError.invalidValue(context: "AEFF mode \(rawMode) is unknown")
        }
        let isDetrimental = try reader.uint8("AEFF detrimental flag") != 0
        let duration = try reader.float32("AEFF duration")
        let elapsed = try reader.float32("AEFF elapsed")
        let paidSeconds = try reader.uint32("AEFF paid seconds")
        let stackKeyword = try decodeOptionalKey(&reader)
        return try ActiveEffect(
            sequence: sequence,
            source: ActiveEffectSource(kind: kind, record: record),
            effect: effect,
            caster: caster,
            mode: mode,
            isDetrimental: isDetrimental,
            duration: duration,
            elapsed: elapsed,
            paidSeconds: paidSeconds,
            values: decodeValues(&reader),
            stackKeyword: stackKeyword
        )
    }

    private static func decodeValues(_ reader: inout SaveReader) throws -> [ActiveEffectValue] {
        let count = try reader.uint32("AEFF value count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.activeEffectValueRecordSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.activeEffects
        )
        var values: [ActiveEffectValue] = []
        values.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let index = try Int32(bitPattern: reader.uint32("AEFF actor value index"))
            let magnitude = try reader.float32("AEFF magnitude")
            let applied = try reader.float32("AEFF applied modifier")
            values.append(ActiveEffectValue(index: index, magnitude: magnitude, applied: applied))
        }
        return values
    }

    private static func decodeOptionalKey(_ reader: inout SaveReader) throws -> ReferenceKey? {
        let present = try reader.uint8("AEFF optional key tag")
        guard present != 0 else { return nil }
        return try OpenSkySaveEntryDecoder.decodeKey(&reader)
    }
}
