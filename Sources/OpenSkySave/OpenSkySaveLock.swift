// LOCK chunk: runtime lock state of doors and containers. Merged into the `RDLT`
// deltas by key. Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One saved lock, before it is merged back into the delta.
nonisolated public struct SaveLockEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: ReferenceLockState
}

nonisolated extension OpenSkySaveEncoder {
    /// Every changed lock, in snapshot order. No change writes no chunk.
    public static func writeLocks(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(ReferenceLockState.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.locks, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, state) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                payload.writeUInt8(state.isLocked ? 1 : 0)
                payload.writeUInt8(state.level)
                payload.writeUInt32(state.key?.rawValue ?? 0)
            }
        }
    }
}

nonisolated public enum OpenSkySaveLockDecoder: Sendable {
    public static func decodeLocks(_ payload: Data) throws -> [SaveLockEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("LOCK entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumLockEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.locks
        )
        var entries: [SaveLockEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let locked = try reader.bool("LOCK locked")
            let level = try reader.uint8("LOCK level")
            let lockKey = try FormID(reader.uint32("LOCK key"))
            entries.append(SaveLockEntry(
                key: key,
                cell: cell,
                state: ReferenceLockState(isLocked: locked, level: level, key: lockKey.nonNull)
            ))
        }
        return entries
    }
}

nonisolated extension SaveLockEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.erased
    }
}
