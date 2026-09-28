// SPLB chunk decoding for the OpenSky native save container (issue #470).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `AEFF`, `AVAL` and `DETH`: an actor whose only delta is its spellbook has
// no `RDLT` entry, so merging by `ReferenceKey` is what lets the encoder omit
// one.
//
// Bounds, as everywhere else in this decoder: a declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.
//
// Nothing here rejects a spellbook on content. A duplicate key, a hand naming a
// spell the known list does not carry, and a spent-power entry for a spell that
// was forgotten are all normalized away by `SpellbookState.init` rather than
// failing a load — the invariant belongs to the type, and one stale key is not a
// reason to refuse a whole save. There is no hard stop of the kind `AEFF` has,
// because this chunk carries no closed enumeration: every field is a key, a
// count or a signed day.

import Foundation

/// One actor's saved spellbook, before it is merged back into the delta.
nonisolated struct SaveSpellbookEntry: Equatable, Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation?
    let state: SpellbookState
}

nonisolated enum OpenSkySaveSpellbookDecoder {
    static func decodeSpellbooks(_ payload: Data) throws -> [SaveSpellbookEntry] {
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

    /// Lays each saved spellbook over the matching `RDLT` delta, adding an entry
    /// for an actor that had no other component, and re-sorts the result into
    /// `ReferenceKey` total order.
    static func merge(
        _ values: [SaveSpellbookEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !values.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + values.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in values where !entry.state.isEmpty {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta(cell: entry.cell)
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
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
