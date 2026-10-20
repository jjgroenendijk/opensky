// VRST chunk: the game hour each merchant chest was last stocked, for the vendor
// restock. Merged into the player's `RDLT` delta. Layout:
// docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// The saved stocking hours, before they are merged back into the player's delta.
nonisolated public struct SaveVendorRestockLedger: Equatable, Sendable {
    public let ledger: VendorRestockLedger
}

nonisolated extension OpenSkySaveEncoder {
    /// The player's stocking hours, ordered by chest. No entry writes no chunk.
    public static func writeVendorRestocks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        guard
            let ledger = entries.first(where: { $0.key == .player })?
                .delta.component(VendorRestockLedger.self),
            !ledger.stockedAt.isEmpty
        else { return }
        let stocked = ledger.stockedAt.sorted { $0.key < $1.key }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.vendorRestocks, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: stocked.count))
            for (chest, hours) in stocked {
                writeKey(chest, into: &payload)
                payload.writeUInt64(hours.bitPattern)
            }
        }
    }
}

nonisolated public enum OpenSkySaveVendorRestockDecoder: Sendable {
    /// A non-finite hour is dropped, so that chest counts as stocked on the next barter.
    public static func decode(_ payload: Data) throws -> SaveVendorRestockLedger {
        var reader = SaveReader(payload)
        let count = try reader.uint32("VRST entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumVendorRestockEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.vendorRestocks
        )
        var ledger = VendorRestockLedger()
        for _ in 0 ..< count {
            let chest = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let hours = try Double(bitPattern: reader.uint64("VRST hours"))
            if hours.isFinite {
                ledger.stockedAt[chest] = hours
            }
        }
        return SaveVendorRestockLedger(ledger: ledger)
    }
}

nonisolated extension SaveVendorRestockLedger: SaveDeltaComponentEntry {
    public var key: ReferenceKey {
        .player
    }

    public var deltaCell: CellSceneLocation? {
        nil
    }

    public var deltaComponent: WorldStateComponentValue? {
        ledger.stockedAt.isEmpty ? nil : ledger.erased
    }
}
