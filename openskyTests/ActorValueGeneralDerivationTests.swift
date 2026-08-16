// Record-derived baselines for the non-primary actor values (issue #468,
// roadmap item 19.5): the RACE and CLAS fields that author one, the skill
// spread, and the decode of the record bytes they come out of.
//
// Every expected number is either quoted from the source that documents it or
// hand-computed from the quoted formula, never taken from an implementation
// run. The sources are cited in
// `opensky/Engine/Actors/ActorValueDerivationGeneral.swift`. Records are
// synthetic and built in code — never extracted game files (AGENTS.md "Legal &
// IP boundary").

import Foundation
@testable import opensky
import Testing

struct ActorValueGeneralDerivationTests {
    private static let oneHanded: Int32 = 6
    private static let twoHanded: Int32 = 7
    private static let block: Int32 = 9
    private static let smithing: Int32 = 10

    /// A Nord-shaped race: +10 Two-Handed and +5 Block, 300 carry weight,
    /// mass 1, unarmed damage 4.
    private static let race = Race.Stats(
        startingHealth: 50,
        startingMagicka: 50,
        startingStamina: 50,
        skillBonuses: [
            Race.SkillBonus(actorValue: twoHanded, bonus: 10),
            Race.SkillBonus(actorValue: block, bonus: 5)
        ],
        baseCarryWeight: 300,
        baseMass: 1,
        unarmedDamage: 4
    )

    // MARK: - Baselines

    /// "Skill = 15 + [Racial bonus] + ..." (UESP CLAS). Without auto-calc there
    /// is no class term, so a race's skills are the floor plus its bonuses.
    @Test func skillsAreTheFloorPlusTheRacialBonus() {
        let values = ActorValueDerivation.generalBaseValues(
            inputs: ActorValueInputs(race: Self.race)
        )
        #expect(values[Self.twoHanded] == 25)
        #expect(values[Self.block] == 20)
        #expect(values[Self.oneHanded] == 15)
        // All eighteen skills are present, because the floor applies to each.
        let skills = (ActorValueIdentity.firstSkillIndex ... ActorValueIdentity.lastSkillIndex)
        #expect(skills.allSatisfy { values[$0] != nil })
    }

    /// The four record fields that are actor values by name: RACE DATA's carry
    /// weight, mass and unarmed damage, and ACBS's speed multiplier.
    @Test func theRecordAuthoredValuesComeFromTheirOwnFields() {
        let values = ActorValueDerivation.generalBaseValues(
            inputs: ActorValueInputs(
                race: Self.race,
                stats: ActorBase.Stats(speedMultiplier: 135)
            )
        )
        #expect(values[ActorValueIndex.carryWeight] == 300)
        #expect(values[ActorValueIndex.mass] == 1)
        #expect(values[ActorValueIndex.unarmedDamage] == 4)
        #expect(values[ActorValueIndex.speedMult] == 135)
    }

    /// Nothing invents a resistance: an actor's records author none, so every
    /// resistance is absent from the derived table and reads the documented
    /// zero default.
    @Test func noResistanceIsDerivedFromRecords() {
        let values = ActorValueDerivation.generalBaseValues(
            inputs: ActorValueInputs(race: Self.race)
        )
        #expect(values[ActorValueIndex.resistFire] == nil)
        #expect(ActorValueIdentity.defaultValue(at: ActorValueIndex.resistFire) == 0)
    }

    // MARK: - The skill spread

    /// "Skill = 15 + [Racial bonus] + 8*(Level-1)/(Sum of class' skill
    /// weights)*[Skill weight]" (UESP CLAS). With weights summing to 8 and a
    /// level-2 actor there are exactly 8 points, so each skill gains its own
    /// weight and no leftover pass runs.
    @Test func autoCalcAddsTheClassSpreadOnTopOfTheFloor() {
        let weights = Self.skillWeights([Self.oneHanded: 5, Self.block: 3])
        let values = ActorValueDerivation.generalBaseValues(
            inputs: ActorValueInputs(
                race: Self.race,
                stats: ActorBase.Stats(levelWord: 2),
                autoCalculatesStats: true,
                skillWeights: weights
            )
        )
        #expect(values[Self.oneHanded] == 20) // 15 + 5
        #expect(values[Self.block] == 23) // 15 + 5 racial + 3
        #expect(values[Self.twoHanded] == 25) // floor + racial, no weight
    }

    /// The leftover pass: 8 points over weights summing to 3 gives two whole
    /// sets (6 points) plus 2 leftover, handed out in decreasing weight order
    /// with ties broken by ascending actor-value index, and never past a
    /// skill's own weight in one pass.
    @Test func leftoverPointsFollowTheDocumentedOrder() {
        let weights = Self.skillWeights([
            Self.oneHanded: 1, Self.block: 1, Self.smithing: 1
        ])
        let spread = ActorValueDerivation.distributeSkillPoints(points: 8, weights: weights)
        #expect(spread[Self.oneHanded] == 3) // 2 sets + 1 leftover
        #expect(spread[Self.block] == 3) // 2 sets + 1 leftover
        #expect(spread[Self.smithing] == 2) // 2 sets, leftover ran out
        #expect(spread.values.reduce(0, +) == 8)
    }

    /// A class with no weights spreads nothing rather than dividing by zero,
    /// which would put a NaN into a skill.
    @Test func aClasslessActorSpreadsNothing() {
        #expect(ActorValueDerivation.distributeSkillPoints(
            points: 80, weights: CharacterClass.SkillWeights()
        ).isEmpty)
        #expect(ActorValueDerivation.distributeSkillPoints(
            points: 0, weights: Self.skillWeights([Self.block: 4])
        ).isEmpty)
    }

    // MARK: - Record decode

    /// RACE DATA 0x00: seven `(actor value, bonus)` byte pairs, then the fields
    /// at 0x30, 0x34 and 0x60 (UESP RACE DATA).
    @Test func decodesTheRaceFieldsThatAuthorAnActorValue() throws {
        let decoded = try Self.raceRecord()
        #expect(decoded.stats.skillBonuses == [
            Race.SkillBonus(actorValue: Self.twoHanded, bonus: 10),
            Race.SkillBonus(actorValue: Self.block, bonus: 5)
        ])
        #expect(decoded.stats.baseCarryWeight == 300)
        #expect(decoded.stats.baseMass == 1)
        #expect(decoded.stats.unarmedDamage == 4)
    }

    /// A pair whose bonus byte is zero is dropped: a race that fills fewer than
    /// seven slots leaves the rest zeroed, and a stored 0/0 pair would read as
    /// "+0 to Aggression".
    @Test func aZeroBonusPairIsNotAnActorValue() throws {
        let decoded = try Self.raceRecord(bonuses: [(actorValue: 0, bonus: 0)])
        #expect(decoded.stats.skillBonuses.isEmpty)
    }

    /// CLAS DATA 0x06: eighteen weight bytes in actor-value index order, "skill
    /// at byte 06 is One-handed; at byte 17, Enchanting" (UESP CLAS).
    @Test func decodesTheClassSkillWeights() throws {
        let decoded = try Self.classRecord(weights: [0: 5, 3: 2, 17: 9])
        #expect(decoded.skillWeights.weights.count == 18)
        #expect(decoded.skillWeights.weight(at: Self.oneHanded) == 5)
        #expect(decoded.skillWeights.weight(at: 9) == 2)
        #expect(decoded.skillWeights.weight(at: 23) == 9)
        #expect(decoded.skillWeights.weight(at: 24) == nil) // Health is no skill
        #expect(decoded.skillWeights.sum == 16)
    }

    /// A DATA too short to hold all eighteen weights yields none rather than a
    /// truncated list, because the position-to-actor-value mapping only holds
    /// for a complete block.
    @Test func aShortClassDATAYieldsNoWeights() throws {
        let decoded = try Self.classRecord(weights: [0: 5], dataLength: 0x10)
        #expect(decoded.skillWeights.weights.isEmpty)
        #expect(decoded.skillWeights.sum == 0)
    }

    /// ACBS 0x0E, which vanilla leaves at 100 for an actor nobody sped up.
    @Test func decodesTheSpeedMultiplier() throws {
        #expect(try Self.actorRecord(speedMultiplier: 100).stats.speedMultiplier == 100)
        #expect(try Self.actorRecord(speedMultiplier: 65).stats.speedMultiplier == 65)
    }

    // MARK: - Fixtures

    private static func skillWeights(
        _ byActorValue: [Int32: UInt8]
    ) -> CharacterClass.SkillWeights {
        var weights = [UInt8](repeating: 0, count: CharacterClass.SkillWeights.count)
        for (index, weight) in byActorValue {
            let offset = Int(index - CharacterClass.SkillWeights.firstActorValue)
            guard weights.indices.contains(offset) else { continue }
            weights[offset] = weight
        }
        return CharacterClass.SkillWeights(weights: weights)
    }

    /// RACE DATA, 128 bytes (UESP RACE): seven skill pairs + 2 pad, four
    /// height/weight floats, flags at 0x20, starting attributes at 0x24, carry
    /// weight at 0x30, mass at 0x34, regen at 0x54, unarmed damage at 0x60.
    private static func raceRecord(
        bonuses: [(actorValue: UInt8, bonus: UInt8)] = [
            (actorValue: 7, bonus: 10), (actorValue: 9, bonus: 5)
        ]
    ) throws -> Race {
        var data = Data()
        for pair in bonuses.prefix(7) {
            data.append(pair.actorValue)
            data.append(pair.bonus)
        }
        data.append(Data(count: 0x24 - data.count))
        for value in [Float(50), 50, 50, 300, 1] { // attributes, carry weight, mass
            data.appendUInt32(value.bitPattern)
        }
        data.append(Data(count: 0x60 - data.count))
        data.appendUInt32(Float(4).bitPattern) // unarmed damage
        data.append(Data(count: 128 - data.count))
        return try Race(
            record: Self.record(ESMFixture.record(
                "RACE", formID: 0x200, data: ESMFixture.field("DATA", data)
            )),
            localized: false
        )
    }

    /// CLAS DATA, 36 bytes (UESP CLAS), with the eighteen weight bytes at 0x06.
    private static func classRecord(
        weights: [Int: UInt8],
        dataLength: Int = 36
    ) throws -> CharacterClass {
        var data = Data(count: 0x06)
        for offset in 0 ..< CharacterClass.SkillWeights.count {
            data.append(weights[offset] ?? 0)
        }
        data.append(Data(count: max(0, 36 - data.count)))
        return try CharacterClass(
            record: Self.record(ESMFixture.record(
                "CLAS", formID: 0x300, data: ESMFixture.field("DATA", data.prefix(dataLength))
            )),
            localized: false
        )
    }

    /// ACBS, 24 bytes (UESP NPC_), with the speed multiplier at 0x0E.
    private static func actorRecord(speedMultiplier: UInt16) throws -> ActorBase {
        var data = Data()
        data.appendUInt32(0) // flags
        data.appendUInt16(0) // magicka offset
        data.appendUInt16(0) // stamina offset
        data.appendUInt16(1) // level
        data.appendUInt16(0) // calc min
        data.appendUInt16(0) // calc max
        data.appendUInt16(speedMultiplier)
        data.appendUInt16(0) // disposition base
        data.appendUInt16(0) // template flags
        data.appendUInt16(0) // health offset
        data.appendUInt16(0) // bleedout override
        return try ActorBase(
            record: Self.record(ESMFixture.record(
                "NPC_", formID: 0x100, data: ESMFixture.field("ACBS", data)
            )),
            localized: false
        )
    }

    private static func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
