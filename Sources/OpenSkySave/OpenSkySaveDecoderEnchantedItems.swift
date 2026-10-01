// ECHG chunk: enchanted items, merged into the `RDLT` deltas by `ReferenceKey`.
// `EnchantedItemState.init` normalizes bad charges and stale sequences, so no
// content error fails a load.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

/// One owner's saved enchanted-item state, before it is merged back into the
/// delta.
nonisolated public struct SaveEnchantedItemEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: EnchantedItemState
}

nonisolated public enum OpenSkySaveEnchantedItemDecoder: Sendable {
    public static func decodeEnchantedItems(_ payload: Data) throws -> [SaveEnchantedItemEntry] {
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

nonisolated extension SaveEnchantedItemEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
