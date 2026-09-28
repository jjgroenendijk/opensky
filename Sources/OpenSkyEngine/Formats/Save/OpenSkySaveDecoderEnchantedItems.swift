// ECHG chunk decoding for the OpenSky native save container (issue #472).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly like
// `SPLB`, `AEFF`, `AVAL` and `DETH`: an owner whose only delta is its enchanted
// items has no `RDLT` entry, so merging by `ReferenceKey` is what lets the
// encoder omit one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked against
// the bytes actually left before an array is reserved, so a corrupt length is a
// thrown error rather than a multi-gigabyte allocation.
//
// Nothing here rejects a state on content. A non-finite charge, a charge above the
// item's capacity and a sequence naming an effect the `AEFF` chunk no longer
// carries are all normalized or simply carried by `EnchantedItemState.init` rather
// than failing a load: the invariant belongs to the type, and one stale sequence is
// not a reason to refuse a whole save. A stale sequence dispels nothing when the
// item comes off, which is the same answer as an item that granted nothing. There
// is no hard stop of the kind `AEFF` has, because this chunk carries no closed
// enumeration: every field is a FormID, a count, a float or a sequence.

import Foundation

/// One owner's saved enchanted-item state, before it is merged back into the
/// delta.
nonisolated struct SaveEnchantedItemEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: EnchantedItemState
}

nonisolated enum OpenSkySaveEnchantedItemDecoder {
    static func decodeEnchantedItems(_ payload: Data) throws -> [SaveEnchantedItemEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("ECHG entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumEnchantedItemEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.enchantedItems
        )
        var entries: [SaveEnchantedItemEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved state over the matching `RDLT` delta, adding an entry for
    /// an owner that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ values: [SaveEnchantedItemEntry],
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

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveEnchantedItemEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        return try SaveEnchantedItemEntry(
            key: key,
            cell: cell,
            state: EnchantedItemState(
                charges: decodeCharges(&reader),
                wornEffects: decodeWornEffects(&reader)
            )
        )
    }

    private static func decodeCharges(_ reader: inout SaveReader) throws -> [UInt32: Float] {
        let count = try reader.uint32("ECHG charge count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.enchantedItemChargeRecordSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.enchantedItems
        )
        var charges: [UInt32: Float] = [:]
        charges.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let item = try reader.uint32("ECHG charge item")
            charges[item] = try reader.float32("ECHG remaining charge")
        }
        return charges
    }

    private static func decodeWornEffects(
        _ reader: inout SaveReader
    ) throws -> [UInt32: [UInt64]] {
        let count = try reader.uint32("ECHG worn item count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumEnchantedItemWornSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.enchantedItems
        )
        var worn: [UInt32: [UInt64]] = [:]
        worn.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let item = try reader.uint32("ECHG worn item")
            worn[item] = try decodeSequences(&reader)
        }
        return worn
    }

    private static func decodeSequences(_ reader: inout SaveReader) throws -> [UInt64] {
        let count = try reader.uint32("ECHG worn sequence count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.enchantedItemSequenceSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.enchantedItems
        )
        var sequences: [UInt64] = []
        sequences.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try sequences.append(reader.uint64("ECHG worn sequence"))
        }
        return sequences
    }
}
