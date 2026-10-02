// HRVS chunk: harvested flora and trees. An entry's presence means harvested, so
// it holds only the key and the cell. Merged into the `RDLT` deltas by key.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One saved harvested reference, before it is merged back into the delta.
nonisolated public struct SaveHarvestEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
}

nonisolated extension OpenSkySaveEncoder {
    /// Every harvested reference, in snapshot order. Nothing harvested writes no chunk.
    public static func writeHarvests(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.filter {
            $0.delta.component(ReferenceHarvestState.self)?.isHarvested == true
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.harvests, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for entry in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
            }
        }
    }
}

nonisolated public enum OpenSkySaveHarvestDecoder: Sendable {
    public static func decodeHarvests(_ payload: Data) throws -> [SaveHarvestEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("HRVS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumHarvestEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.harvests
        )
        var entries: [SaveHarvestEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(SaveHarvestEntry(
                key: OpenSkySaveEntryDecoder.decodeKey(&reader),
                cell: OpenSkySaveEntryDecoder.decodeCell(&reader)
            ))
        }
        return entries
    }
}

nonisolated extension SaveHarvestEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        ReferenceHarvestState.harvested.erased
    }
}
