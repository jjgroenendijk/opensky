// TMPR chunk: tempered copies per owner, merged into the `RDLT` deltas by
// `ReferenceKey`. A sibling of `INVN`, whose rows have no room for a quality.
// `TemperedItemState.init` drops bad levels, so no content error fails a load.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One owner's saved tempered copies, before they are merged back into the delta.
nonisolated public struct SaveTemperedItemEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: TemperedItemState
}

nonisolated extension SaveTemperedItemEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}

nonisolated public enum OpenSkySaveTemperedItems: Sendable {
    /// Per owner: key, cell, item count, then per item the FormID, a level count,
    /// and one int32 level per copy. Items ascend, so equal state gives equal bytes.
    public static func write(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry -> (WorldStateSnapshotEntry, TemperedItemState)? in
            guard
                let state = entry.delta.component(TemperedItemState.self),
                !state.isEmpty
            else { return nil }
            return (entry, state)
        }
        guard !saved.isEmpty else { return }
        let tag = OpenSkySaveFormat.ChunkTag.temperedItems
        OpenSkySaveEncoder.writeChunk(tag: tag, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, state) in saved {
                OpenSkySaveEncoder.writeKey(entry.key, into: &payload)
                OpenSkySaveEncoder.writeCell(entry.delta.cell, into: &payload)
                let items = state.levels.sorted { $0.key < $1.key }
                payload.writeUInt32(UInt32(clamping: items.count))
                for (item, levels) in items {
                    payload.writeUInt32(item)
                    payload.writeUInt32(UInt32(clamping: levels.count))
                    for level in levels {
                        payload.writeUInt32(UInt32(bitPattern: level))
                    }
                }
            }
        }
    }

    public static func decode(_ payload: Data) throws -> [SaveTemperedItemEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("TMPR entry count")
        try validate(count, OpenSkySaveFormat.minimumTemperedEntrySize, reader)
        var entries: [SaveTemperedItemEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let state = try TemperedItemState(levels: decodeItems(&reader))
            entries.append(SaveTemperedItemEntry(key: key, cell: cell, state: state))
        }
        return entries
    }

    private static func decodeItems(_ reader: inout SaveReader) throws -> [UInt32: [Int32]] {
        let count = try reader.uint32("TMPR item count")
        try validate(count, OpenSkySaveFormat.minimumTemperedItemSize, reader)
        var items: [UInt32: [Int32]] = [:]
        for _ in 0 ..< count {
            let item = try reader.uint32("TMPR item")
            let levels = try reader.uint32("TMPR level count")
            try validate(levels, OpenSkySaveFormat.temperedLevelSize, reader)
            var copies: [Int32] = []
            copies.reserveCapacity(Int(levels))
            for _ in 0 ..< levels {
                try copies.append(Int32(bitPattern: reader.uint32("TMPR level")))
            }
            items[item, default: []] += copies
        }
        return items
    }

    private static func validate(_ count: UInt32, _ size: Int, _ reader: SaveReader) throws {
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: size,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.temperedItems
        )
    }
}
