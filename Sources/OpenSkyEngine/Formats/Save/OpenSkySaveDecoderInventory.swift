// INVN chunk decoding for the OpenSky native save container (issue #176).
//
// The chunk is decoded on its own and merged into the `RDLT` entries
// afterwards, because the two chunks describe the same references from
// different sides: `RDLT` carries a reference's placement, enable and
// activation deltas, `INVN` carries its items, and either may be present
// without the other. Merging by `ReferenceKey` rather than by position is what
// lets the encoder omit an `RDLT` entry whose only component was inventory.
//
// Bounds, as everywhere else in this decoder: every declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.

import Foundation

/// One owner's saved inventory, before it is merged back into its delta.
nonisolated struct SaveInventoryEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let inventory: ReferenceInventoryState
}

nonisolated enum OpenSkySaveInventoryDecoder {
    static func decodeInventories(_ payload: Data) throws -> [SaveInventoryEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("INVN entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumInventoryEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.inventories
        )
        var entries: [SaveInventoryEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved inventory over the matching `RDLT` delta, adding an
    /// entry for an owner that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order.
    ///
    /// Re-sorting is not defensive tidying: `WorldStateSnapshot` promises that
    /// order, and an owner that appears only in `INVN` is inserted in whatever
    /// position the chunk listed it.
    static func merge(
        _ inventories: [SaveInventoryEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !inventories.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + inventories.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in inventories {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.inventory.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    // MARK: - Private

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveInventoryEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let stacks = try decodeStacks(&reader)
        let equipped = try decodeEquipped(&reader)
        return SaveInventoryEntry(
            key: key,
            cell: cell,
            inventory: ReferenceInventoryState(stacks: stacks, equipped: equipped)
        )
    }

    /// Counts are written as `Int32` because CNTO is signed on disk, so the
    /// decoder reads them back the same way. A zero or negative count is
    /// dropped by `ReferenceInventoryState.init` rather than rejected here:
    /// the invariant belongs to the type, and one nonsensical stack is not a
    /// reason to fail a whole save.
    private static func decodeStacks(_ reader: inout SaveReader) throws -> [InventoryStack] {
        let count = try reader.uint32("INVN stack count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.inventoryStackSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.inventories
        )
        var stacks: [InventoryStack] = []
        stacks.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let item = try FormID(reader.uint32("INVN stack item"))
            let amount = try Int32(bitPattern: reader.uint32("INVN stack count"))
            stacks.append(InventoryStack(item: item, count: amount))
        }
        return stacks
    }

    private static func decodeEquipped(_ reader: inout SaveReader) throws -> [FormID] {
        let count = try reader.uint32("INVN equipped count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.inventoryEquippedSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.inventories
        )
        var equipped: [FormID] = []
        equipped.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try equipped.append(FormID(reader.uint32("INVN equipped item")))
        }
        return equipped
    }
}
