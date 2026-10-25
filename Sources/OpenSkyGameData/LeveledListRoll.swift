// One leveled-list request: chance none, the level filter, "all levels", "each",
// "use all", special loot, and the leveled-actor difficulty step. Pure: the
// random source is a seeded value, so the same request gives the same answer.
// Rules: UESP "Skyrim:Leveled Lists", <https://ck.uesp.net/wiki/LeveledItem>,
// <https://ck.uesp.net/wiki/LeveledCharacter>. See docs/engine/leveled-lists.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One entry a request returned, with the count it gives.
nonisolated public struct LeveledPick: Equatable, Sendable {
    public let entry: LeveledList.Entry
    public let count: Int32

    public init(entry: LeveledList.Entry, count: Int32) {
        self.entry = entry
        self.count = count
    }
}

/// What one request asks a list for: the level to roll at and the player's level,
/// which special loot also reads.
nonisolated public struct LeveledRequest: Equatable, Sendable {
    public var level: Int
    public var playerLevel: Int

    public init(level: Int, playerLevel: Int) {
        self.level = level
        self.playerLevel = playerLevel
    }
}

nonisolated public enum LeveledListRoll {
    /// One seed from several parts, such as an owner and a list FormID, so a
    /// re-derived baseline rolls the same.
    public static func seed(_ parts: UInt64...) -> UInt64 {
        parts.reduce(0x5EED_1E5E_7E11_0000) { mixed, part in
            var random = SplitMix64(seed: mixed ^ part)
            return random.next()
        }
    }

    /// A seed from a stable text, such as a reference key's description.
    public static func seed(text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    /// The entries a roll at `level` chooses from. Without "all levels" only the
    /// highest entry level at or below `level` stays.
    public static func candidates(
        in list: LeveledList, level: Double, allLevels: Bool? = nil
    ) -> [LeveledList.Entry] {
        let reachable = list.entries.filter { Double($0.level) <= level }
        if allLevels ?? list.flags.contains(.calculateFromAllLevels) {
            return reachable
        }
        guard let top = reachable.map(\.level).max() else { return [] }
        return reachable.filter { $0.level == top }
    }

    /// `count` asked of `list`. "Use all" gives every entry. "Each" rolls once per
    /// count; any other list rolls once and multiplies. `chanceNone` is in percent.
    public static func roll(
        _ list: LeveledList,
        count: Int32,
        request: LeveledRequest,
        chanceNone: Float,
        settings: SpecialLootSettings = SpecialLootSettings(),
        random: inout SplitMix64
    ) -> [LeveledPick] {
        if list.flags.contains(.useAll) {
            guard !isNone(chanceNone, &random) else { return [] }
            return list.entries.map { LeveledPick(entry: $0, count: scaled(count, $0)) }
        }
        let rolls = list.flags.contains(.calculateForEach) ? max(1, Int(count)) : 1
        let each: Int32 = rolls > 1 ? 1 : count
        var picks: [LeveledPick] = []
        for _ in 0 ..< rolls {
            guard !isNone(chanceNone, &random) else { continue }
            let level = list.flags.contains(.specialLoot)
                ? settings.level(
                    playerLevel: request.playerLevel, inputLevel: request.level,
                    draw: Double(random.unitFloat()) - 0.5
                )
                : Double(request.level)
            let choices = candidates(in: list, level: level)
            guard !choices.isEmpty else { continue }
            let entry = choices[Int(random.next(upperBound: UInt64(choices.count)))]
            picks.append(LeveledPick(entry: entry, count: scaled(each, entry)))
        }
        return picks
    }

    /// The entry a placed leveled actor resolves to. Easy chooses among every
    /// level at or below its level. Very hard steps one entry level above the hard
    /// choice when both would match. A list with no entry low enough gives its
    /// lowest entries; no source says what the game does then.
    public static func actorEntry(
        _ list: LeveledList,
        encounterLevel: Int,
        difficulty: LeveledActorDifficulty,
        settings: LeveledListSettings = .fallback,
        random: inout SplitMix64
    ) -> LeveledList.Entry? {
        let level = EncounterLevel.actorListLevel(
            encounterLevel: encounterLevel, difficulty: difficulty, settings: settings
        )
        var choices = candidates(
            in: list,
            level: level,
            allLevels: difficulty == .easy ? true : nil
        )
        if difficulty == .veryHard {
            choices = steppedAboveHard(list, choices: choices, encounterLevel, settings)
        }
        if choices.isEmpty, let lowest = list.entries.map(\.level).min() {
            choices = list.entries.filter { $0.level == lowest }
        }
        guard !choices.isEmpty else { return nil }
        return choices[Int(random.next(upperBound: UInt64(choices.count)))]
    }

    private static func steppedAboveHard(
        _ list: LeveledList,
        choices: [LeveledList.Entry],
        _ encounterLevel: Int,
        _ settings: LeveledListSettings
    ) -> [LeveledList.Entry] {
        let hardLevel = EncounterLevel.actorListLevel(
            encounterLevel: encounterLevel, difficulty: .hard, settings: settings
        )
        let hardTop = candidates(in: list, level: hardLevel, allLevels: false).first?.level
        let top = choices.map(\.level).max()
        guard let hardTop, top == hardTop else { return choices }
        guard let next = list.entries.map(\.level).filter({ $0 > hardTop }).min() else {
            return choices
        }
        return list.entries.filter { $0.level == next }
    }

    private static func isNone(_ chanceNone: Float, _ random: inout SplitMix64) -> Bool {
        chanceNone > 0 && random.unitFloat() * 100 < chanceNone
    }

    private static func scaled(_ count: Int32, _ entry: LeveledList.Entry) -> Int32 {
        Int32(clamping: Int64(count) * Int64(max(entry.count, 1)))
    }
}
