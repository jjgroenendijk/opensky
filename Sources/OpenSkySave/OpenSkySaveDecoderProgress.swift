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

    /// The `PLGD` chunk: legendary counts per skill, keyed by holder.
    public static func decodeLegendarySkills(_ payload: Data) throws
        -> [ReferenceKey: [Int32: Int]]
    {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PLGD entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumLegendaryEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.legendarySkills
        )
        var entries: [ReferenceKey: [Int32: Int]] = [:]
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            let rows = try reader.uint32("PLGD skill count")
            try OpenSkySaveDecoder.validate(
                count: rows,
                minimumElementSize: OpenSkySaveFormat.legendarySkillRowSize,
                remaining: reader.bytesRemaining,
                chunk: OpenSkySaveFormat.ChunkTag.legendarySkills
            )
            var counts: [Int32: Int] = [:]
            for _ in 0 ..< rows {
                let skill = try Int32(bitPattern: reader.uint32("PLGD skill"))
                let times = try reader.uint32("PLGD count")
                guard ActorValueIdentity.isSkill(index: skill) else { continue }
                counts[skill] = Int(times)
            }
            entries[key] = counts
        }
        return entries
    }

    /// The `PTRN` chunk: training sessions this level, keyed by holder.
    public static func decodeTrainingSessions(_ payload: Data) throws -> [ReferenceKey: Int] {
        var reader = SaveReader(payload)
        let count = try reader.uint32("PTRN entry count")
        try OpenSkySaveDecoder.validate(
            count: count,
            minimumElementSize: OpenSkySaveFormat.minimumTrainingEntrySize,
            remaining: reader.bytesRemaining,
            chunk: OpenSkySaveFormat.ChunkTag.trainingSessions
        )
        var entries: [ReferenceKey: Int] = [:]
        for _ in 0 ..< count {
            let key = try OpenSkySaveEntryDecoder.decodeKey(&reader)
            entries[key] = try Int(reader.uint32("PTRN sessions"))
        }
        return entries
    }

    /// `PLVL` with its `PLGD` and `PTRN` siblings laid on.
    static func progress(of body: OpenSkySaveDecoder.Body) -> [SavePlayerProgressEntry] {
        let progress = merge(body.legendarySkills, into: body.playerProgress) {
            $0.withLegendaryCounts($1)
        }
        return merge(body.trainingSessions, into: progress) { $0.withTrainingSessions($1) }
    }

    /// Lays a sibling chunk's values onto each holder's `PLVL` progress; a holder
    /// with no `PLVL` entry gets a fresh progress carrying only that value.
    public static func merge<Value>(
        _ values: [ReferenceKey: Value],
        into progress: [SavePlayerProgressEntry],
        apply: (PlayerProgressState, Value) -> PlayerProgressState
    ) -> [SavePlayerProgressEntry] {
        guard !values.isEmpty else { return progress }
        var merged = progress.map { entry in
            guard let value = values[entry.key] else { return entry }
            return SavePlayerProgressEntry(
                key: entry.key, cell: entry.cell, state: apply(entry.state, value)
            )
        }
        let covered = Set(progress.map(\.key))
        for (key, value) in values.sorted(by: { $0.key < $1.key }) where !covered.contains(key) {
            merged.append(SavePlayerProgressEntry(
                key: key, cell: nil, state: apply(PlayerProgressState(), value)
            ))
        }
        return merged
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
