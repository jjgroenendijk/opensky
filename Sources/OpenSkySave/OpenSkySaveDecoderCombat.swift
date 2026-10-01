// CBTS chunk: combat hostility, merged into the `RDLT` deltas by `ReferenceKey`.
// An unknown hostility byte decodes as neutral, so a newer save still loads.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One actor's saved hostility, before it is merged back into the delta.
nonisolated public struct SaveCombatStateEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: ActorCombatState
}

nonisolated public enum OpenSkySaveCombatDecoder: Sendable {
    public static func decodeCombatStates(_ payload: Data) throws -> [SaveCombatStateEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("CBTS entry count")
        try OpenSkySaveDecoder.validate(
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
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.erased
    }
}
