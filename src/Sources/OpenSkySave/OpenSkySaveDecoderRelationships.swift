// RELS chunk: scripted relationship ranks, merged into the `RDLT` deltas by
// `ReferenceKey`. A rank outside -4...4 is kept, because clamping would invent a
// rank the script did not set.

import Foundation
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldState

/// One actor's saved relationship overrides, before they are merged back into
/// the delta.
nonisolated struct SaveRelationshipEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorRelationshipState
}

nonisolated enum OpenSkySaveRelationshipDecoder: Sendable {
    static func decodeRelationshipRanks(_ payload: Data) throws -> [SaveRelationshipEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("RELS entry count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelationshipEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relationships
        )
        var entries: [SaveRelationshipEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SaveRelationshipEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("RELS override count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumRelationshipOverrideSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.relationships
        )
        var overrides: [ActorRelationshipOverride] = []
        overrides.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let other = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rank = try Int8(bitPattern: reader.uint8("RELS override rank"))
            overrides.append(ActorRelationshipOverride(other: other, rank: rank))
        }
        return SaveRelationshipEntry(
            key: key,
            cell: cell,
            state: ActorRelationshipState(overrides: overrides)
        )
    }
}

nonisolated extension SaveRelationshipEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
