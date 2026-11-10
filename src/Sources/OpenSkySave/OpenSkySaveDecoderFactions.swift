// FCTN chunk: faction memberships, merged into the `RDLT` deltas by `ReferenceKey`.
// A faction the load order lost is kept, so removing a plugin keeps progress.

import Foundation
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldState

/// One actor's saved memberships, before they are merged back into the delta.
nonisolated struct SaveFactionEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorFactionState
}

nonisolated enum OpenSkySaveFactionDecoder: Sendable {
    static func decodeFactionMemberships(_ payload: Data) throws -> [SaveFactionEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("FCTN entry count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumFactionEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.factions
        )
        var entries: [SaveFactionEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveFactionEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let count = try reader.uint32("FCTN membership count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumFactionMembershipSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.factions
        )
        var memberships: [ActorFactionMembership] = []
        memberships.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let faction = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rank = try Int8(bitPattern: reader.uint8("FCTN membership rank"))
            memberships.append(ActorFactionMembership(faction: faction, rank: rank))
        }
        return SaveFactionEntry(
            key: key,
            cell: cell,
            state: ActorFactionState(memberships: memberships)
        )
    }
}

nonisolated extension SaveFactionEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
