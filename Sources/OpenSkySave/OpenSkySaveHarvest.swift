// HRVS chunk: harvested flora and trees. An entry's presence means harvested, so
// it holds only the key and the cell. HRVD adds the game day of each timed
// harvest. Both merge into the `RDLT` deltas by key, HRVD last.

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

/// The game day of one saved harvest.
nonisolated public struct SaveHarvestDayEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let day: Float
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
        let timed = saved.compactMap { entry in
            entry.delta.component(ReferenceHarvestState.self)?.harvestedOnDay
                .map { (entry.key, $0) }
        }
        guard !timed.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.harvestDays, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: timed.count))
            for (key, day) in timed {
                writeKey(key, into: &payload)
                payload.writeFloat32(day)
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

    /// A non-finite day is dropped, so its plant stays harvested with no time.
    public static func decodeHarvestDays(_ payload: Data) throws -> [SaveHarvestDayEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("HRVD entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumHarvestDayEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.harvestDays
        )
        var entries: [SaveHarvestDayEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let day = try reader.float32("HRVD day")
            if day.isFinite {
                entries.append(SaveHarvestDayEntry(key: key, day: day))
            }
        }
        return entries
    }
}

nonisolated extension SaveHarvestDayEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        nil
    }

    public var deltaComponent: WorldStateComponentValue? {
        ReferenceHarvestState(isHarvested: true, harvestedOnDay: day).erased
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
