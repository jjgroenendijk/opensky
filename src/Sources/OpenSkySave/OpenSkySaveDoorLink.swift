// RDLK chunk: the doors random doors linked to. Merged into the `RDLT` deltas by
// key. Layout: docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldState

/// One saved link, before it is merged back into the delta.
nonisolated struct SaveDoorLinkEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let link: ReferenceDoorLink
}

nonisolated enum OpenSkySaveDoorLinkWriter {
    /// Every linked door, in snapshot order. No link writes no chunk.
    static func writeDoorLinks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(ReferenceDoorLink.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writer.writeChunk(tag: OpenSkySaveFormat.ChunkTag.doorLinks) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, link) in saved {
                payload.writeKey(entry.key)
                payload.writeCell(entry.delta.cell)
                payload.writeKey(link.door)
            }
        }
    }
}

nonisolated enum OpenSkySaveDoorLinkDecoder: Sendable {
    static func decodeDoorLinks(_ payload: Data) throws -> [SaveDoorLinkEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RDLK entry count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumDoorLinkEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.doorLinks
        )
        var entries: [SaveDoorLinkEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let door = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            entries.append(SaveDoorLinkEntry(
                key: key,
                cell: cell,
                link: ReferenceDoorLink(door: door)
            ))
        }
        return entries
    }
}

nonisolated extension SaveDoorLinkEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        link.erased
    }
}
