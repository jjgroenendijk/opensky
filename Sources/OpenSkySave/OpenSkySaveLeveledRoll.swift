// LVRL chunk: the player level each placed actor and container froze for its
// leveled lists. Merged into the `RDLT` deltas by key. Layout:
// docs/formats/opensky-save.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One saved frozen level, before it is merged back into the delta.
nonisolated public struct SaveLeveledRollEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let playerLevel: Int
}

nonisolated extension OpenSkySaveEncoder {
    /// Every reference with a frozen level, in snapshot order. None writes no chunk.
    public static func writeLeveledRolls(
        _ entries: [WorldStateSnapshotEntry],
        into writer: inout BinaryWriter
    ) {
        let saved = entries.compactMap { entry in
            entry.delta.component(LeveledRollState.self).map { (entry, $0) }
        }
        guard !saved.isEmpty else { return }
        writeChunk(tag: OpenSkySaveFormat.ChunkTag.leveledRolls, into: &writer) { payload in
            payload.writeUInt32(UInt32(clamping: saved.count))
            for (entry, roll) in saved {
                writeKey(entry.key, into: &payload)
                writeCell(entry.delta.cell, into: &payload)
                payload.writeUInt32(UInt32(clamping: roll.playerLevel))
            }
        }
    }
}

nonisolated public enum OpenSkySaveLeveledRollDecoder: Sendable {
    /// A level below 1 is dropped, so that reference rolls at the live level.
    public static func decodeLeveledRolls(_ payload: Data) throws -> [SaveLeveledRollEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("LVRL entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumLeveledRollEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.leveledRolls
        )
        var entries: [SaveLeveledRollEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
            let level = try reader.uint32("LVRL player level")
            guard level >= 1, let playerLevel = Int(exactly: level) else { continue }
            entries.append(SaveLeveledRollEntry(key: key, cell: cell, playerLevel: playerLevel))
        }
        return entries
    }
}

nonisolated extension SaveLeveledRollEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        LeveledRollState(playerLevel: playerLevel).erased
    }
}
