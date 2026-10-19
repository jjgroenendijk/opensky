// CRST chunk: the game hour the player last left each cell, for the cell reset.
// Merged into the player's `RDLT` delta. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// The saved departures, before they are merged back into the player's delta.
nonisolated public struct SaveCellResetLedger: Equatable, Sendable {
    public let ledger: CellResetLedger
}

nonisolated extension OpenSkySaveEncoder {
    /// The player's departures, ordered by cell. No departure writes no chunk.
    public static func writeCellResets(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        guard
            let ledger = entries.first(where: { $0.key == .player })?
                .delta.component(CellResetLedger.self),
            !ledger.departures.isEmpty
        else { return }
        let departures = ledger.departures.sorted {
            CellSceneLocation.isOrderedBefore($0.key, $1.key)
        }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.cellResets, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: departures.count))
            for (cell, hours) in departures {
                writeCell(cell, into: &payload)
                payload.writeUInt64(hours.bitPattern)
            }
        }
    }
}

nonisolated public enum OpenSkySaveCellResetDecoder: Sendable {
    /// A non-finite hour or an absent cell is dropped, so that cell does not reset.
    public static func decode(_ payload: Data) throws -> SaveCellResetLedger {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CRST entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumCellResetEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.cellResets
        )
        var ledger = CellResetLedger()
        for _ in 0 ..< count {
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let hours = try Double(bitPattern: reader.uint64("CRST hours"))
            if let cell, hours.isFinite {
                ledger.departures[cell] = hours
            }
        }
        return SaveCellResetLedger(ledger: ledger)
    }
}

nonisolated extension SaveCellResetLedger: SaveDeltaComponentEntry {
    public var key: ReferenceKey {
        .player
    }

    public var deltaCell: CellSceneLocation? {
        nil
    }

    public var deltaComponent: WorldStateComponentValue? {
        ledger.departures.isEmpty ? nil : ledger.erased
    }
}
