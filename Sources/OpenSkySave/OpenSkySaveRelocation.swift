// RLOC chunk: references `MoveTo` sent to another cell. Merged into the `RDLT`
// deltas by key. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One saved move, before it is merged back into the delta.
nonisolated public struct SaveRelocationEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let relocation: ReferenceRelocation
}

nonisolated extension OpenSkySaveEncoder {
    /// Every moved reference, in snapshot order. No move writes no chunk.
    public static func writeRelocations(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(ReferenceRelocation.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.relocations, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, relocation) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                writeCell(relocation.location, into: &payload)
            }
        }
    }
}

nonisolated public enum OpenSkySaveRelocationDecoder: Sendable {
    public static func decodeRelocations(_ payload: Data) throws -> [SaveRelocationEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RLOC entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelocationEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relocations
        )
        var entries: [SaveRelocationEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            guard let location = try OpenSkySaveEntryDecoder.decodeCell(&reader) else {
                throw OpenSkySaveError.invalidValue(context: "RLOC entry with no target cell")
            }
            entries.append(SaveRelocationEntry(
                key: key, cell: cell, relocation: ReferenceRelocation(location: location)
            ))
        }
        return entries
    }
}

nonisolated extension SaveRelocationEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        relocation.erased
    }
}
