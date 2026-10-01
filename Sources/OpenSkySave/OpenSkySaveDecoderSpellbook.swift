// SPLB chunk: spellbooks, merged into the `RDLT` deltas by `ReferenceKey`.
// `SpellbookState.init` normalizes duplicate and stale keys, so no content error
// fails a load.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyWorldState

/// One actor's saved spellbook, before it is merged back into the delta.
nonisolated public struct SaveSpellbookEntry: Equatable, Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation?
    public let state: SpellbookState
}

nonisolated public enum OpenSkySaveSpellbookDecoder: Sendable {
    public static func decodeSpellbooks(_ payload: Data) throws -> [SaveSpellbookEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("SPLB entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumSpellbookEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.spellbooks
        )
        var entries: [SaveSpellbookEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    // MARK: - Private

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveSpellbookEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let cell = try OpenSkySaveEntryDecoder.decodeCell(&reader)
        let known = try decodeKeyList(&reader, label: "SPLB known count")
        let readBooks = try decodeKeyList(&reader, label: "SPLB read book count")
        let leftHand = try decodeOptionalKey(&reader)
        let rightHand = try decodeOptionalKey(&reader)
        return try SaveSpellbookEntry(
            key: key,
            cell: cell,
            state: SpellbookState(
                known: known,
                readBooks: readBooks,
                leftHand: leftHand,
                rightHand: rightHand,
                powerDays: decodePowerDays(&reader)
            )
        )
    }

    private static func decodeKeyList(
        _ reader: inout SaveReader,
        label: String
    ) throws -> [ReferenceKey] {
        let count = try reader.uint32(label)
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumSpellbookKeySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.spellbooks
        )
        var keys: [ReferenceKey] = []
        keys.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try keys.append(OpenSkySaveEntryDecoder.decodeKey(&reader))
        }
        return keys
    }

    private static func decodePowerDays(
        _ reader: inout SaveReader
    ) throws -> [ReferenceKey: Int32] {
        let count = try reader.uint32("SPLB spent power count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumSpellbookPowerSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.spellbooks
        )
        var days: [ReferenceKey: Int32] = [:]
        days.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let power = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            days[power] = try Int32(bitPattern: reader.uint32("SPLB spent power day"))
        }
        return days
    }

    private static func decodeOptionalKey(_ reader: inout SaveReader) throws -> ReferenceKey? {
        let present = try reader.uint8("SPLB readied hand tag")
        guard present != 0 else { return nil }
        return try OpenSkySaveEntryDecoder.decodeKey(&reader)
    }
}

nonisolated extension SaveSpellbookEntry: SaveDeltaComponentEntry {
    public var deltaCell: CellSceneLocation? {
        cell
    }

    public var deltaComponent: WorldStateComponentValue? {
        state.isEmpty ? nil : state.erased
    }
}
