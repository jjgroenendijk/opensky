// ICPY chunk: every distinct item copy per owner, merged into the `RDLT` deltas by
// `ReferenceKey` after `TMPR`, so it replaces the level-only state for that owner.
// `ItemCopyState.init` drops plain copies, so no content error fails a load.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldState

nonisolated public enum OpenSkySaveItemCopies: Sendable {
    private static let hasCharge: UInt8 = 1
    private static let hasEnchantment: UInt8 = 2

    /// Per owner: key, cell, item count, then per item the FormID, a copy count, and per
    /// copy an int32 level, a soul byte, a flags byte, then the charge and the
    /// enchantment FormID the flags name. Items ascend, so equal state gives equal bytes.
    /// Only owners with a copy `TMPR` cannot hold are written.
    public static func write(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (WorldStateSnapshotEntry, ItemCopyState)? in
            guard
                let state = entry.delta.component(ItemCopyState.self),
                state.copies.values.joined().contains(where: needsThisChunk)
            else { return nil }
            return (entry, state)
        }
        guard !saved.isEmpty else { return }
        let tag = OpenSkySaveFormat.ChunkTag.itemCopies
        OpenSkySaveEncoder.writeChunk(tag: tag, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, state) in saved {
                OpenSkySaveEncoder.writeKey(entry.key, into: &payload)
                OpenSkySaveEncoder.writeCell(entry.delta.cell, into: &payload)
                let items = state.copies.sorted { $0.key < $1.key }
                payload.writeUInt32(UInt32(clamping: items.count))
                for (item, copies) in items {
                    payload.writeUInt32(item)
                    payload.writeUInt32(UInt32(clamping: copies.count))
                    copies.forEach { write($0, into: &payload) }
                }
            }
        }
    }

    public static func decode(_ payload: Data) throws -> [SaveTemperedItemEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("ICPY entry count")
        try validate(count, OpenSkySaveFormat.minimumTemperedEntrySize, reader)
        var entries: [SaveTemperedItemEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let state = try ItemCopyState(copies: decodeItems(&reader))
            entries.append(SaveTemperedItemEntry(key: key, cell: cell, state: state))
        }
        return entries
    }

    private static func needsThisChunk(_ copy: ItemCopy) -> Bool {
        copy.soul != 0 || copy.charge != nil || copy.enchantment != nil
    }

    private static func write(_ copy: ItemCopy, into payload: inout BinaryWriter) {
        payload.writeUInt32(UInt32(bitPattern: copy.level))
        payload.writeUInt8(copy.soul)
        let flags = (copy.charge == nil ? 0 : hasCharge)
            | (copy.enchantment == nil ? 0 : hasEnchantment)
        payload.writeUInt8(flags)
        if let charge = copy.charge {
            payload.writeFloat32(charge)
        }
        if let enchantment = copy.enchantment {
            payload.writeUInt32(enchantment.rawValue)
        }
    }

    private static func decodeItems(_ reader: inout SaveReader) throws -> [UInt32: [ItemCopy]] {
        let count = try reader.uint32("ICPY item count")
        try validate(count, OpenSkySaveFormat.minimumTemperedItemSize, reader)
        var items: [UInt32: [ItemCopy]] = [:]
        for _ in 0 ..< count {
            let item = try reader.uint32("ICPY item")
            let copies = try reader.uint32("ICPY copy count")
            try validate(copies, OpenSkySaveFormat.minimumItemCopySize, reader)
            for _ in 0 ..< copies {
                try items[item, default: []].append(decodeCopy(&reader))
            }
        }
        return items
    }

    private static func decodeCopy(_ reader: inout SaveReader) throws -> ItemCopy {
        let level = try Int32(bitPattern: reader.uint32("ICPY level"))
        let soul = try reader.uint8("ICPY soul")
        let flags = try reader.uint8("ICPY flags")
        var charge: Float?
        if flags & hasCharge != 0 {
            charge = try reader.float32("ICPY charge")
        }
        var enchantment: FormID?
        if flags & hasEnchantment != 0 {
            enchantment = try FormID(reader.uint32("ICPY enchantment"))
        }
        return ItemCopy(level: level, soul: soul, charge: charge, enchantment: enchantment)
    }

    private static func validate(_ count: UInt32, _ size: Int, _ reader: SaveReader) throws {
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: size,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.itemCopies
        )
    }
}
