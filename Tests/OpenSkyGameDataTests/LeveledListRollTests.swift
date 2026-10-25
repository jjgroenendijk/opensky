// The leveled-list roll, the encounter level, the difficulty step, special loot,
// and the shared roller, on synthetic lists. Rules: docs/engine/leveled-lists.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct LeveledListRollTests {
    // MARK: - Picking

    @Test func withoutAllLevelsOnlyTheHighestReachableLevelStays() throws {
        let list = try Self.list(entries: [(1, 0x10), (4, 0x20), (4, 0x30), (9, 0x40)])
        #expect(LeveledListRoll.candidates(in: list, level: 6).map(\.reference.rawValue)
            == [0x20, 0x30])
        #expect(LeveledListRoll.candidates(in: list, level: 0).isEmpty)
    }

    @Test func allLevelsKeepsEveryReachableEntry() throws {
        let list = try Self.list(flags: 0x01, entries: [(1, 0x10), (4, 0x20), (9, 0x40)])
        #expect(LeveledListRoll.candidates(in: list, level: 6).map(\.reference.rawValue)
            == [0x10, 0x20])
    }

    @Test func everyEntryIsReachedAcrossSeeds() throws {
        let list = try Self.list(flags: 0x01, entries: [(1, 0x10), (1, 0x20), (1, 0x30)])
        let picked = Set((0 ..< 64).flatMap { Self.roll(list, seed: $0) }.map(\.entry.reference))
        #expect(picked.count == 3)
    }

    @Test func chanceNoneOfOneHundredGivesNothing() throws {
        let list = try Self.list(entries: [(1, 0x10)])
        #expect(Self.roll(list, chanceNone: 100).isEmpty)
        #expect(Self.roll(list, chanceNone: 0).count == 1)
    }

    @Test func useAllGivesEveryEntryScaledByTheCount() throws {
        let list = try Self.list(flags: 0x04, entries: [(1, 0x10), (50, 0x20)], counts: [1, 2])
        let picks = Self.roll(list, count: 3, level: 1)
        #expect(picks.map(\.count) == [3, 6])
    }

    @Test func eachRollsOncePerCount() throws {
        let each = try Self.list(flags: 0x02, entries: [(1, 0x10)], counts: [2])
        #expect(Self.roll(each, count: 3).map(\.count) == [2, 2, 2])
        let once = try Self.list(entries: [(1, 0x10)], counts: [2])
        #expect(Self.roll(once, count: 3).map(\.count) == [6])
    }

    // MARK: - Special loot

    @Test func specialLootLevelFollowsTheCreationKitFormula() {
        let settings = SpecialLootSettings()
        // Low = 10 * 0.6 + 20 * 0.4 = 14, high = 20 * 1 = 20.
        #expect(settings.level(playerLevel: 10, inputLevel: 20, draw: 0) == 14)
        #expect(settings.level(playerLevel: 10, inputLevel: 20, draw: -0.5) == 14.375)
    }

    @Test func aSpecialLootListRollsAtTheSpecialLevel() throws {
        // The special level for player 10 in a level-20 place is 14 to 14.375.
        let list = try Self.list(flags: 0x08, entries: [(10, 0x10), (15, 0x20)])
        let picks = (0 ..< 16).flatMap {
            Self.roll(list, seed: $0, request: LeveledRequest(level: 20, playerLevel: 10))
        }
        #expect(Set(picks.map(\.entry.reference)) == [FormID(0x10)])
    }

    // MARK: - Encounter level

    @Test func aZoneRaisesToItsMinimumAndCapsAtItsMaximum() throws {
        let zone = try Self.zone(minimum: 6, maximum: 20)
        #expect(EncounterLevel.level(playerLevel: 3, zone: nil) == 3)
        #expect(EncounterLevel.level(playerLevel: 3, zone: zone) == 6)
        #expect(EncounterLevel.level(playerLevel: 12, zone: zone) == 12)
        #expect(EncounterLevel.level(playerLevel: 30, zone: zone) == 20)
        let matching = try Self.zone(minimum: 6, maximum: 0, flags: 0x02)
        #expect(EncounterLevel.level(playerLevel: 3, zone: matching) == 3)
        #expect(EncounterLevel.level(playerLevel: 300, zone: matching) == 300)
    }

    @Test func theLevelAdjustSettingsShiftTheEncounterLevel() {
        var settings = LeveledListSettings.fallback
        settings.calcLevelAdjustUp = 3
        settings.calcLevelAdjustDown = 1
        #expect(EncounterLevel.level(playerLevel: 10, zone: nil, settings: settings) == 12)
    }

    // MARK: - Leveled actors

    @Test func difficultyScalesTheLevelAnActorPicksAt() throws {
        let list = try Self.list(entries: [(1, 0x10), (6, 0x20), (9, 0x30), (12, 0x40)])
        // Encounter level 10: easy 3.3, medium 6.7, hard 10, very hard 12.5.
        #expect(Self.actor(list, level: 10, .medium) == 0x20)
        #expect(Self.actor(list, level: 10, .hard) == 0x30)
        #expect(Self.actor(list, level: 10, .none) == 0x30)
        #expect(Self.actor(list, level: 10, .veryHard) == 0x40)
        #expect(Self.actor(list, level: 10, .easy) == 0x10)
    }

    @Test func easyChoosesAmongEveryLevelBelowItsShare() throws {
        let list = try Self.list(entries: [(1, 0x10), (2, 0x20), (20, 0x30)])
        let picked = Set((0 ..< 64).map { Self.actor(list, level: 10, .easy, seed: $0) })
        #expect(picked == [0x10, 0x20])
    }

    @Test func veryHardStepsAboveTheHardChoice() throws {
        // At 10, hard and very hard (12.5) both reach level 9, so very hard
        // takes the next level up, 30, whatever its level.
        let list = try Self.list(entries: [(1, 0x10), (9, 0x20), (30, 0x30)])
        #expect(Self.actor(list, level: 10, .veryHard) == 0x30)
        let top = try Self.list(entries: [(1, 0x10), (9, 0x20)])
        #expect(Self.actor(top, level: 10, .veryHard) == 0x20)
    }

    @Test func anActorListAboveTheLevelGivesItsLowestEntry() throws {
        let list = try Self.list(entries: [(20, 0x10), (30, 0x20)])
        #expect(Self.actor(list, level: 5, .none) == 0x10)
    }

    // MARK: - Roller

    @Test func theRollerReadsThePlacementAndTheChanceNoneGlobal() throws {
        let roller = LeveledListRoller(
            playerLevel: PlayerLevelSource(10),
            chanceNoneGlobal: { $0 == FormID(0x99) ? 100 : nil }
        )
        let list = try Self.list(entries: [(1, 0x10), (9, 0x20), (15, 0x30)])
        let base = FormID(0x500)
        #expect(roller.actorEntry(list, roll: roller.roll(forActor: base))?
            .reference == FormID(0x20))
        try roller.placements.record(
            actor: base,
            LeveledActorPlacement(zone: Self.zone(minimum: 15, maximum: 0), difficulty: .hard)
        )
        #expect(roller.actorEntry(list, roll: roller.roll(forActor: base))?
            .reference == FormID(0x30))
        #expect(roller.roll(forActor: base).encounterLevel == 15)

        let gated = try Self.list(entries: [(1, 0x10)], global: 0x99)
        #expect(roller.roll(gated, count: 1, request: roller.request(atLevel: 1), seed: 1).isEmpty)
    }

    @Test func aContainerRollsAtItsCellsZone() throws {
        let roller = LeveledListRoller(playerLevel: PlayerLevelSource(2))
        let cell = CellSceneLocation.interior(FormID(0x77))
        try roller.placements.record(cell: cell, zone: Self.zone(minimum: 8, maximum: 0))
        let chest = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x900)
        #expect(roller.roll(for: chest, base: nil, cell: cell, frozenLevel: nil)
            .encounterLevel == 8)
        #expect(roller.roll(for: chest, base: nil, cell: nil, frozenLevel: nil).encounterLevel == 2)
    }

    /// Two placed references of one base roll by their own keys, and a frozen level
    /// holds after the player levels up.
    @Test func aPlacedReferenceRollsByItsKeyAtItsFrozenLevel() throws {
        let roller = LeveledListRoller(playerLevel: PlayerLevelSource(30))
        let list = try Self.list(entries: (1 ... 40).map { (UInt16(1), UInt32(0x100 + $0)) })
        let base = FormID(0x500)
        let picks = Set((0 ..< 8).compactMap { id in
            roller.actorEntry(list, roll: roller.roll(
                for: .plugin(name: "skyrim.esm", objectID: 0xA00 + id), base: base, cell: nil,
                frozenLevel: nil
            ))?.reference
        })
        #expect(picks.count > 1)

        let bandit = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xB00)
        let levels = try Self.list(entries: [(1, 0x10), (20, 0x20)])
        let frozen = roller.roll(for: bandit, base: base, cell: nil, frozenLevel: 5)
        #expect(frozen.playerLevel == 5)
        #expect(roller.actorEntry(levels, roll: frozen)?.reference == FormID(0x10))
        let live = roller.roll(for: bandit, base: base, cell: nil, frozenLevel: nil)
        #expect(roller.actorEntry(levels, roll: live)?.reference == FormID(0x20))
    }

    /// The reference's own placement wins over its base's.
    @Test func aReferencePlacementWinsOverItsBase() throws {
        let roller = LeveledListRoller(playerLevel: PlayerLevelSource(2))
        let base = FormID(0x500)
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xC00)
        try roller.placements.record(
            actor: base, LeveledActorPlacement(
                zone: Self.zone(minimum: 5, maximum: 0),
                difficulty: .easy
            )
        )
        try roller.placements.record(
            reference: key,
            LeveledActorPlacement(zone: Self.zone(minimum: 12, maximum: 0), difficulty: .hard)
        )
        let roll = roller.roll(for: key, base: base, cell: nil, frozenLevel: nil)
        #expect(roll.encounterLevel == 12)
        #expect(roll.difficulty == .hard)
        #expect(roller.roll(forActor: base).encounterLevel == 5)
    }

    @Test func settingsResolveFromTheGameSettings() throws {
        let store = try GameSettingStore(plugins: [("Leveled.esp", GameSettingFixture.plugin(
            settings: [
                "fLeveledActorMultEasy": .float(0.5),
                "iCalcLevelAdjustUp": .integer(2),
                "fSpecialLootWeighting": .float(2)
            ]
        ))])
        let settings = LeveledListSettings.resolve(store: store)
        #expect(settings.actorMultEasy == 0.5)
        #expect(settings.actorMultHard == 1)
        #expect(settings.calcLevelAdjustUp == 2)
        #expect(settings.specialLoot.weighting == 2)
        #expect(settings.specialLoot.minPCLevelMult == 0.6)
    }

    // MARK: - Fixtures

    private static func list(
        flags: UInt8 = 0,
        entries: [(UInt16, UInt32)],
        counts: [UInt32] = [],
        global: UInt32? = nil
    ) throws -> LeveledList {
        var fields = ESMFixture.field("LVLF", Data([flags]))
        if let global {
            var data = Data()
            data.appendUInt32(global)
            fields += ESMFixture.field("LVLG", data)
        }
        for (index, (level, reference)) in entries.enumerated() {
            let count = index < counts.count ? counts[index] : 1
            fields += ESMFixture.field(
                "LVLO", ShoutFixture.leveledEntry(level: level, reference: reference, count: count)
            )
        }
        return try LeveledList(record: ShoutFixture.record(type: "LVLI", fields: fields))
    }

    private static func roll(
        _ list: LeveledList,
        count: Int32 = 1,
        level: Int = 50,
        chanceNone: Float = 0,
        seed: Int = 0,
        request: LeveledRequest? = nil
    ) -> [LeveledPick] {
        var random = SplitMix64(seed: UInt64(seed))
        return LeveledListRoll.roll(
            list, count: count,
            request: request ?? LeveledRequest(level: level, playerLevel: level),
            chanceNone: chanceNone, random: &random
        )
    }

    private static func actor(
        _ list: LeveledList, level: Int, _ difficulty: LeveledActorDifficulty, seed: Int = 0
    ) -> UInt32? {
        var random = SplitMix64(seed: UInt64(seed))
        return LeveledListRoll.actorEntry(
            list, encounterLevel: level, difficulty: difficulty, random: &random
        )?.reference.rawValue
    }

    /// ECZN `DATA`: owner, location, rank, minimum, flags, maximum.
    private static func zone(
        minimum: Int8,
        maximum: Int8,
        flags: UInt8 = 0
    ) throws -> EncounterZone {
        var data = Data(count: 8)
        data.append(contentsOf: [
            0xFF,
            UInt8(bitPattern: minimum),
            flags,
            UInt8(bitPattern: maximum)
        ])
        return try EncounterZone(record: ESMFixture.parsedRecord(
            type: "ECZN", fields: ESMFixture.field("DATA", data)
        ))
    }
}
