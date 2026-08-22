// CRIM and STOL chunk decoding for the OpenSky native save container (issue
// #504).
//
// Both are decoded on their own and merged into the `RDLT` entries afterwards,
// exactly like `FCTN`, `PRKS` and `INVN`: an actor whose only delta is its
// bounty has no `RDLT` entry, so merging by `ReferenceKey` is what lets the
// encoder omit one.
//
// `STOL` merges *after* `INVN`, and the ordering is load-bearing rather than
// incidental: `INVN` carries per-item totals and `STOL` says how many of each
// were stolen, so the split can only be applied once the totals are in place.
// A `STOL` row for an owner with no inventory at all is dropped rather than
// conjuring a stack out of it — the goods are what `INVN` says they are, and
// this chunk only re-flags them.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.

import Foundation

/// One actor's saved ledger, before it is merged back into the delta.
nonisolated struct SaveCrimeLedgerEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let ledger: CrimeLedgerState
}

/// One owner's stolen counts, before they are laid over its inventory.
nonisolated struct SaveStolenGoodsEntry: Equatable, Sendable {
    let key: ReferenceKey
    /// How many copies of each item are stolen, in the order the chunk listed.
    let stolen: [InventoryStack]
}

nonisolated enum OpenSkySaveCrimeDecoder {
    // MARK: - CRIM

    static func decodeCrimeLedgers(_ payload: Data) throws -> [SaveCrimeLedgerEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CRIM entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumCrimeLedgerEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.crimeLedgers
        )
        var entries: [SaveCrimeLedgerEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeLedgerEntry(&reader))
        }
        return entries
    }

    /// Lays each saved ledger over the matching `RDLT` delta, adding an entry
    /// for an actor that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ values: [SaveCrimeLedgerEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey = Self.index(entries)
        for entry in values where !entry.ledger.isEmpty {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.ledger.erased)
            deltasByKey[entry.key] = delta
        }
        return Self.sorted(deltasByKey)
    }

    // MARK: - STOL

    static func decodeStolenGoods(_ payload: Data) throws -> [SaveStolenGoodsEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("STOL entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumStolenGoodsEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.stolenGoods
        )
        var entries: [SaveStolenGoodsEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeStolenEntry(&reader))
        }
        return entries
    }

    /// Re-splits each owner's already-merged inventory into honest and stolen
    /// stacks.
    ///
    /// A stolen count larger than the total the inventory holds is clamped to
    /// that total rather than rejected: the invariant belongs to the component,
    /// and one impossible row is not a reason to fail a whole save.
    static func mergeStolen(
        _ values: [SaveStolenGoodsEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey = Self.index(entries)
        for entry in values {
            guard
                var delta = deltasByKey[entry.key],
                let inventory = delta.component(ReferenceInventoryState.self)
            else { continue }
            delta.set(Self.applying(entry.stolen, to: inventory).erased)
            deltasByKey[entry.key] = delta
        }
        return Self.sorted(deltasByKey)
    }

    // MARK: - Private

    private static func decodeLedgerEntry(
        _ reader: inout SaveReader
    ) throws -> SaveCrimeLedgerEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("CRIM row count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumCrimeLedgerRowSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.crimeLedgers
        )
        var rows: [CrimeLedgerEntry] = []
        rows.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try rows.append(decodeLedgerRow(&reader))
        }
        return SaveCrimeLedgerEntry(
            key: key,
            cell: cell,
            ledger: CrimeLedgerState(entries: rows)
        )
    }

    /// The faction, the gold, then the four counts in `CrimeKind.allCases`
    /// order. Read positionally rather than by name, so a build that adds a
    /// fifth kind reads an older file's four and leaves the new one at zero.
    private static func decodeLedgerRow(_ reader: inout SaveReader) throws -> CrimeLedgerEntry {
        let faction = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let gold = try Int32(bitPattern: reader.uint32("CRIM row gold"))
        var counts: [CrimeKind: Int32] = [:]
        for kind in CrimeKind.allCases {
            counts[kind] = try Int32(bitPattern: reader.uint32("CRIM row count"))
        }
        return CrimeLedgerEntry(
            faction: faction,
            gold: gold,
            counts: CrimeCounts(
                theft: counts[.theft] ?? 0,
                assault: counts[.assault] ?? 0,
                murder: counts[.murder] ?? 0,
                trespass: counts[.trespass] ?? 0
            )
        )
    }

    private static func decodeStolenEntry(
        _ reader: inout SaveReader
    ) throws -> SaveStolenGoodsEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let count = try reader.uint32("STOL row count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.stolenGoodsRowSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.stolenGoods
        )
        var stolen: [InventoryStack] = []
        stolen.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let item = try FormID(reader.uint32("STOL row item"))
            let amount = try Int32(bitPattern: reader.uint32("STOL row count"))
            stolen.append(InventoryStack(item: item, count: amount, stolen: true))
        }
        return SaveStolenGoodsEntry(key: key, stolen: stolen)
    }

    /// `inventory` with each named item split into an honest remainder and a
    /// stolen part.
    private static func applying(
        _ stolen: [InventoryStack],
        to inventory: ReferenceInventoryState
    ) -> ReferenceInventoryState {
        var result = inventory
        for row in stolen {
            result = result.markingStolen(row.item, count: row.count)
        }
        return result
    }

    private static func index(
        _ entries: [WorldStateSnapshotEntry]
    ) -> [ReferenceKey: ReferenceStateDelta] {
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        return deltasByKey
    }

    private static func sorted(
        _ deltasByKey: [ReferenceKey: ReferenceStateDelta]
    ) -> [WorldStateSnapshotEntry] {
        deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }
}
