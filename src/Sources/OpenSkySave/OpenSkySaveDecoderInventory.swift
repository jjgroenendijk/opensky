// INVN chunk: reference inventories, merged into the `RDLT` deltas by
// `ReferenceKey`, so a reference with only items needs no `RDLT` entry.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One owner's saved inventory, before it is merged back into its delta.
nonisolated struct SaveInventoryEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let inventory: ReferenceInventoryState
}

nonisolated enum OpenSkySaveInventoryDecoder: Sendable {
    static func decodeInventories(_ payload: Data) throws -> [SaveInventoryEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("INVN entry count")
        try SaveCountCheck.validate(
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
        try SaveCountCheck.validate(
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
        try SaveCountCheck.validate(
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

nonisolated extension SaveInventoryEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        inventory.erased
    }
}
