// QSTS chunk decoding for the OpenSky native save container (issue #182).
//
// Decoded on its own and merged into the `RDLT` entries afterwards, exactly
// like `INVN`: a quest has no placement, so its key normally appears in no
// other chunk, and merging by `ReferenceKey` is what lets the encoder omit an
// `RDLT` entry that would otherwise hold nothing.
//
// Bounds, as everywhere else in this decoder: every declared count is checked
// against the bytes actually left before an array is reserved, so a corrupt
// length is a thrown error rather than a multi-gigabyte allocation.

import Foundation

/// One quest's saved state, before it is merged back into its delta.
nonisolated struct SaveQuestEntry: Equatable, Sendable {
    let key: ReferenceKey
    let state: QuestRuntimeState
}

/// One quest's saved alias table (issue #183), likewise pre-merge.
nonisolated struct SaveQuestAliasEntry: Equatable, Sendable {
    let key: ReferenceKey
    let state: QuestAliasState
}

nonisolated struct SaveQuestLocationAliasEntry: Equatable, Sendable {
    let key: ReferenceKey
    let fills: [QuestLocationAliasFill]
}

nonisolated enum OpenSkySaveQuestDecoder {
    static func decodeQuestStates(_ payload: Data) throws -> [SaveQuestEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("QSTS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumQuestEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questStates
        )
        var entries: [SaveQuestEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeEntry(&reader))
        }
        return entries
    }

    /// Lays each saved quest state over the matching `RDLT` delta, adding an
    /// entry for a quest that had no other component, and re-sorts the result
    /// into `ReferenceKey` total order — the order `WorldStateSnapshot`
    /// promises, which a chunk-order insertion would otherwise break.
    static func merge(
        _ quests: [SaveQuestEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !quests.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + quests.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in quests {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta()
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    /// `QALS` (issue #183): the filled alias tables, decoded on their own and
    /// merged the same way the quest states are.
    static func decodeQuestAliases(_ payload: Data) throws -> [SaveQuestAliasEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("QALS entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumQuestAliasEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questAliases
        )
        var entries: [SaveQuestAliasEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try entries.append(decodeAliasEntry(&reader))
        }
        return entries
    }

    /// Lays each saved alias table over the matching delta, exactly as
    /// `merge(_:into:)` does for quest state.
    static func mergeAliases(
        _ aliases: [SaveQuestAliasEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !aliases.isEmpty else { return entries }
        var deltasByKey: [ReferenceKey: ReferenceStateDelta] = [:]
        deltasByKey.reserveCapacity(entries.count + aliases.count)
        for entry in entries {
            deltasByKey[entry.key] = entry.delta
        }
        for entry in aliases {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta()
            delta.set(entry.state.erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            guard let delta = deltasByKey[key] else { return nil }
            return WorldStateSnapshotEntry(key: key, delta: delta)
        }
    }

    static func decodeQuestLocationAliases(
        _ payload: Data
    ) throws -> [SaveQuestLocationAliasEntry] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("QLOC entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumQuestAliasEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questLocationAliases
        )
        var entries: [SaveQuestLocationAliasEntry] = []
        entries.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let fillCount = try reader.uint32("QLOC fill count")
            try OpenSkySaveDecoder.validate(
                count: fillCount,
                minimumElementSize: OpenSkySaveFormat.minimumQuestAliasFillSize,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.questLocationAliases
            )
            var fills: [QuestLocationAliasFill] = []
            fills.reserveCapacity(Int(fillCount))
            for _ in 0 ..< fillCount {
                let aliasID = try reader.uint32("QLOC alias ID")
                let target = try OpenSkySaveEntryDecoder.decodeKey(&reader)
                guard case let .plugin(name, objectID) = target else {
                    throw OpenSkySaveError.invalidValue(context: "QLOC location key")
                }
                fills.append(QuestLocationAliasFill(
                    aliasID: aliasID,
                    location: ResolvedFormID(plugin: name, objectID: objectID)
                ))
            }
            entries.append(SaveQuestLocationAliasEntry(key: key, fills: fills))
        }
        return entries
    }

    static func mergeLocationAliases(
        _ aliases: [SaveQuestLocationAliasEntry],
        into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        guard !aliases.isEmpty else { return entries }
        var deltasByKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.delta) })
        for entry in aliases {
            var delta = deltasByKey[entry.key] ?? ReferenceStateDelta()
            let existing = delta.component(QuestAliasState.self) ?? .empty
            delta.set(QuestAliasState(fills: existing.fills, locationFills: entry.fills).erased)
            deltasByKey[entry.key] = delta
        }
        return deltasByKey.keys.sorted().compactMap { key in
            deltasByKey[key].map { WorldStateSnapshotEntry(key: key, delta: $0) }
        }
    }

    // MARK: - Private

    /// Duplicate or unsorted alias IDs are collapsed and sorted by
    /// `QuestAliasState.init` rather than rejected here, for the same reason
    /// the stage list is: the invariant belongs to the type.
    private static func decodeAliasEntry(
        _ reader: inout SaveReader
    ) throws -> SaveQuestAliasEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let count = try reader.uint32("QALS fill count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumQuestAliasFillSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questAliases
        )
        var fills: [QuestAliasFill] = []
        fills.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let aliasID = try reader.uint32("QALS alias ID")
            let reference = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            fills.append(QuestAliasFill(aliasID: aliasID, reference: reference))
        }
        return SaveQuestAliasEntry(key: key, state: QuestAliasState(fills: fills))
    }

    private static func decodeEntry(_ reader: inout SaveReader) throws -> SaveQuestEntry {
        let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let flags = try reader.uint8("QSTS quest flags")
        let stages = try decodeStages(&reader)
        let objectives = try decodeObjectives(&reader)
        return SaveQuestEntry(
            key: key,
            state: QuestRuntimeState(
                isRunning: flags & OpenSkySaveFormat.QuestFlag.running != 0,
                isCompleted: flags & OpenSkySaveFormat.QuestFlag.completed != 0,
                stagesReached: stages,
                objectives: objectives
            )
        )
    }

    /// Duplicate or unsorted stage indices are collapsed and sorted by
    /// `QuestRuntimeState.init` rather than rejected here: the invariant belongs
    /// to the type, and one repeated index is not a reason to fail a whole save.
    private static func decodeStages(_ reader: inout SaveReader) throws -> [UInt16] {
        let count = try reader.uint32("QSTS stage count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.questStageSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questStates
        )
        var stages: [UInt16] = []
        stages.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            try stages.append(reader.uint16("QSTS stage index"))
        }
        return stages
    }

    /// Unknown bits in an objective's flag byte are ignored rather than
    /// rejected, which is the same tolerance an unknown chunk gets: a newer
    /// build may add a fourth objective flag, and losing it is better than
    /// refusing the file.
    private static func decodeObjectives(
        _ reader: inout SaveReader
    ) throws -> [QuestObjectiveState] {
        let count = try reader.uint32("QSTS objective count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.questObjectiveSize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.questStates
        )
        var objectives: [QuestObjectiveState] = []
        objectives.reserveCapacity(Int(count))
        for _ in 0 ..< count {
            let index = try reader.uint16("QSTS objective index")
            let flags = try reader.uint8("QSTS objective flags")
            objectives.append(QuestObjectiveState(
                index: index,
                isDisplayed: flags & OpenSkySaveFormat.QuestObjectiveFlag.displayed != 0,
                isCompleted: flags & OpenSkySaveFormat.QuestObjectiveFlag.completed != 0,
                isFailed: flags & OpenSkySaveFormat.QuestObjectiveFlag.failed != 0
            ))
        }
        return objectives
    }
}
