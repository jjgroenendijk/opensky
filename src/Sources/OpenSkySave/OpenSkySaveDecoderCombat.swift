// CBTS chunk: combat hostility, merged into the `RDLT` deltas by `ReferenceKey`.
// An unknown hostility byte decodes as neutral, so a newer save still loads.

import Foundation
public import OpenSkyActorsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldState

/// One actor's saved hostility, before it is merged back into the delta.
nonisolated struct SaveCombatStateEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: ActorCombatState
}

nonisolated enum OpenSkySaveCombatDecoder: Sendable {
    static func decodeCombatStates(_ payload: Data) throws -> [SaveCombatStateEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CBTS entry count")
        try SaveCountCheck.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumCombatStateEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.combatStates
        )
        var entries: [SaveCombatStateEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(
        _ reader: inout SaveReader
    ) throws -> SaveCombatStateEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let raw = try reader.uint8("CBTS hostility")
        return SaveCombatStateEntry(
            key: key,
            cell: cell,
            state: ActorCombatState(hostility: ActorHostility(rawValue: raw) ?? .neutral)
        )
    }
}

nonisolated extension SaveCombatStateEntry: SaveDeltaComponentEntry {
    var deltaCell: CellSceneLocation? {
        cell
    }

    var deltaComponent: WorldStateComponentValue? {
        state.erased
    }
}
