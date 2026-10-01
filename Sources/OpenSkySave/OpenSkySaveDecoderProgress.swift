// PLVL chunk: player level progress, merged into the `RDLT` deltas by
// `ReferenceKey`. `PlayerProgressState.init` clamps every field, and a pick that
// is not one of the three primaries is dropped.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// One actor's saved character-level progress, before it is merged back into
/// the delta.
nonisolated public struct SavePlayerProgressEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: PlayerProgressState
}

nonisolated public enum OpenSkySaveProgressDecoder: Sendable {
    public static func decodePlayerProgress(_ payload: Data) throws -> [SavePlayerProgressEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PLVL entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPlayerProgressEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.playerProgress
        )
        var entries: [SavePlayerProgressEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SavePlayerProgressEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let level = try reader.uint32("PLVL level")
        let experience = try reader.float32("PLVL experience")
        let perkPoints = try reader.uint32("PLVL perk points")
        let pending = try reader.uint32("PLVL pending attribute picks")
        let increases = try reader.uint32("PLVL skill increases")
        let pickCount = try reader.uint32("PLVL attribute pick count")
        try OpenSkySaveDecoder.validate(
            count: pickCount,
            minimumElementSize: OpenSkySaveFormat.playerProgressPickSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.playerProgress
        )
        var picks: [ActorValueKind] = []
        picks.reserveCapacity(Int(pickCount))
        for _ in 0 ..< pickCount {
            let index = try Int32(bitPattern: reader.uint32("PLVL attribute pick"))
            guard let kind = ActorValueIdentity.kind(at: index) else { continue }
            picks.append(kind)
        }
        return SavePlayerProgressEntry(
            key: key,
            cell: cell,
            state: PlayerProgressState(
                level: Int(level),
                experience: experience,
                perkPoints: Int(perkPoints),
                pendingAttributePicks: Int(pending),
                attributePicks: picks,
                skillIncreases: Int(increases)
            )
        )
    }
}

nonisolated extension SavePlayerProgressEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
