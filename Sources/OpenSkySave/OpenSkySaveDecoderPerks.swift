// PRKS chunk: perk lists, merged into the `RDLT` deltas by `ReferenceKey`.
// A perk the load order lost is kept, so removing a plugin keeps progress.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// One actor's saved perks, before they are merged back into the delta.
nonisolated public struct SavePerkEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: PerkState
}

nonisolated public enum OpenSkySavePerkDecoder: Sendable {
    public static func decodePerks(_ payload: Data) throws -> [SavePerkEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PRKS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPerkEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.perks
        )
        var entries: [SavePerkEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SavePerkEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("PRKS owned count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumPerkKeySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.perks
        )
        var owned: [ReferenceKey] = []
        owned.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try owned.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
        }
        return SavePerkEntry(key: key, cell: cell, state: PerkState(owned: owned))
    }
}

nonisolated extension SavePerkEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
