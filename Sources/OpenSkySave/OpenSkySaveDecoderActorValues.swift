// AVAL chunk decoding for the OpenSky save, merged into `RDLT` entries by
// `ReferenceKey` like `INVN`. Declared counts are checked against the bytes
// left. Bad floats are normalized by `ActorValueState.init`, not rejected.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One actor's saved current values, before they are merged back into the
/// delta.
nonisolated public struct SaveActorValueEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: ActorValueState
}

/// One actor's saved actor-value overrides, before they merge onto its `AVAL`
/// entry.
nonisolated public struct SaveActorValueOverrideEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let overrides: [Int32: ActorValueOverride]
}

nonisolated public enum OpenSkySaveActorValueDecoder: Sendable {
    public static func decodeActorValues(_ payload: Data) throws -> [SaveActorValueEntry] {
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
    public static func merge(
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

    /// `AVOV`: one entry per actor with overrides, each a list of
    /// `(index, base offset, permanent, damage)` records.
    public static func decodeActorValueOverrides(
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

    /// Lays each actor's override table onto its `AVAL` entry. An `AVOV` entry
    /// without an `AVAL` entry is dropped, since the encoder writes both together.
    public static func mergeOverrides(
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
        // The cell is written for symmetry with AVAL; the merge takes the AVAL cell.
        _ = try OpenSkySaveEntryDecoder.decodeCell(&reader)
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
        return SaveActorValueOverrideEntry(key: key, overrides: overrides)
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
