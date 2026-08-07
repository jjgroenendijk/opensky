// Stat-record decode + stat-side template resolution tests (issue #194) over
// synthetic in-code records (ESMFixture) — never extracted game files
// (AGENTS.md "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format"
// per-record pages; see docs/formats/actors.md.

import Foundation
@testable import opensky
import Testing

struct ActorValueRecordDecodeTests {
    // MARK: - NPC_ ACBS

    @Test func decodesACBSStatWords() throws {
        let actor = try npc(
            formID: 0x100,
            flags: 0x0000_0010, // auto calc stats
            magickaOffset: -25,
            staminaOffset: 40,
            level: 7,
            calcMin: 3,
            calcMax: 12,
            healthOffset: -10,
            characterClass: 0x0001_3176
        )
        #expect(actor.stats.magickaOffset == -25)
        #expect(actor.stats.staminaOffset == 40)
        #expect(actor.stats.levelWord == 7)
        #expect(actor.stats.calcMinLevel == 3)
        #expect(actor.stats.calcMaxLevel == 12)
        #expect(actor.stats.healthOffset == -10)
        #expect(actor.stats.characterClass == FormID(0x0001_3176))
        #expect(actor.autoCalculatesStats)
    }

    /// "Note that if PC Level Mult is checked, Auto Calc Stats will always be
    /// checked." (<https://ck.uesp.net/wiki/Stats_Tab>)
    @Test func pcLevelMultImpliesAutoCalc() throws {
        let actor = try npc(formID: 0x100, flags: 0x0000_0080)
        #expect(actor.flags.contains(.pcLevelMult))
        #expect(!actor.flags.contains(.autoCalcStats))
        #expect(actor.autoCalculatesStats)
    }

    @Test func statWordsDefaultWithoutAutoCalcOrClass() throws {
        let actor = try npc(formID: 0x100)
        #expect(!actor.autoCalculatesStats)
        #expect(actor.stats.characterClass == nil)
        #expect(actor.stats.healthOffset == 0)
        #expect(actor.stats.bakedHealth == nil)
    }

    /// A 20-byte ACBS is short of the health offset. The appearance fields
    /// still decode and the offset keeps its zero default rather than the
    /// record failing.
    @Test func shortACBSKeepsTheHealthOffsetDefault() throws {
        var data = acbs(magickaOffset: -5, templateFlags: 0x0002)
        data = data.prefix(20)
        let fields = ESMFixture.field("ACBS", data)
        let actor = try ActorBase(
            record: record(ESMFixture.record("NPC_", formID: 1, data: fields)),
            localized: false
        )
        #expect(actor.templateFlags == .useStats)
        #expect(actor.stats.magickaOffset == -5)
        #expect(actor.stats.healthOffset == 0)
    }

    /// DNAM's baked triple is decoded for cross-checking only; a short DNAM
    /// leaves it absent rather than inventing zeros.
    @Test func decodesDNAMBakedValues() throws {
        let actor = try npc(formID: 0x100, baked: Triple(300, 150, 200))
        #expect(actor.stats.bakedHealth == 300)
        #expect(actor.stats.bakedMagicka == 150)
        #expect(actor.stats.bakedStamina == 200)

        let short = try ActorBase(
            record: record(ESMFixture.record("NPC_", formID: 2, data: ESMFixture.field(
                "ACBS", acbs()
            ) + ESMFixture.field("DNAM", Data(count: 12)))),
            localized: false
        )
        #expect(short.stats.bakedHealth == nil)
    }

    // MARK: - RACE DATA

    @Test func decodesRaceStartingAttributesAndRegen() throws {
        let race = try race(
            formID: 0x200,
            starting: Triple(50, 60, 70),
            regen: Triple(0.7, 3, 5)
        )
        #expect(race.stats.startingHealth == 50)
        #expect(race.stats.startingMagicka == 60)
        #expect(race.stats.startingStamina == 70)
        #expect(race.stats.healthRegenPercent == 0.7)
        #expect(race.stats.magickaRegenPercent == 3)
        #expect(race.stats.staminaRegenPercent == 5)
    }

    /// The two windows are read independently, so a DATA long enough for the
    /// starting attributes but not the regen block still yields the attributes.
    @Test func shortRaceDATAYieldsWhatItReaches() throws {
        let full = raceDATA(starting: Triple(50, 60, 70), regen: Triple(0.7, 3, 5))
        let truncated = full.prefix(0x40)
        let decoded = try Race(
            record: record(ESMFixture.record(
                "RACE", formID: 0x201, data: ESMFixture.field("DATA", truncated)
            )),
            localized: false
        )
        #expect(decoded.stats.startingHealth == 50)
        #expect(decoded.stats.staminaRegenPercent == 0)

        let tiny = try Race(
            record: record(ESMFixture.record(
                "RACE", formID: 0x202, data: ESMFixture.field("DATA", Data(count: 0x24))
            )),
            localized: false
        )
        #expect(tiny.stats == Race.Stats())
    }

    // MARK: - CLAS

    @Test func decodesClassAttributeWeights() throws {
        let decoded = try characterClass(formID: 0x300, weights: Triple(1, 2, 3), bleedout: 0.15)
        #expect(decoded.editorID == "TestClass")
        #expect(decoded.attributeWeights.health == 1)
        #expect(decoded.attributeWeights.magicka == 2)
        #expect(decoded.attributeWeights.stamina == 3)
        #expect(decoded.attributeWeights.sum == 6)
        #expect(decoded.bleedoutDefault == 0.15)
    }

    /// A short DATA yields zero weights rather than failing the record: a class
    /// that spreads nothing is a usable answer, a thrown error is not.
    @Test func shortClassDATAYieldsZeroWeights() throws {
        let decoded = try CharacterClass(
            record: record(ESMFixture.record(
                "CLAS", formID: 0x301, data: ESMFixture.field("DATA", Data(count: 8))
            )),
            localized: false
        )
        #expect(decoded.attributeWeights.sum == 0)
        #expect(decoded.bleedoutDefault == 0)
    }

    @Test func classRejectsOtherRecordTypes() throws {
        #expect(throws: ESMError.self) {
            _ = try CharacterClass(
                record: record(ESMFixture.record("NPC_", formID: 1, data: Data())),
                localized: false
            )
        }
    }
}

struct ActorStatTemplateResolutionTests {
    /// Stats ride `useStats`, race rides `useTraits`: an actor delegating only
    /// its stats keeps its own race and takes the template's offsets and class.
    @Test func useStatsPullsStatFieldsFromTemplateOnly() throws {
        let template = try npc(
            formID: 0x200,
            flags: 0x0000_0010,
            magickaOffset: 30,
            level: 9,
            healthOffset: 20,
            characterClass: 0xC2,
            race: 0xA2
        )
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0002, // useStats
            template: 0x200,
            magickaOffset: 1,
            level: 2,
            healthOffset: 2,
            characterClass: 0xC1,
            race: 0xA1
        )
        let resolved = try resolver(npcs: [base, template]).resolveStats(base: FormID(0x100))
        #expect(resolved.stats.source == FormID(0x200))
        #expect(resolved.stats.value.healthOffset == 20)
        #expect(resolved.stats.value.levelWord == 9)
        #expect(resolved.stats.value.characterClass == FormID(0xC2))
        #expect(resolved.autoCalculatesStats.value)
        // Race is a trait, and `useTraits` is clear, so it stays local.
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA1), source: FormID(0x100)))
        // The starting attributes, though, come from the stats record's race.
        // Observed against `Skyrim.esm` rather than documented anywhere — see
        // `ResolvedActorStats.statsRace`.
        #expect(resolved.statsRace
            == ActorSourcedField(value: FormID(0xA2), source: FormID(0x200)))
    }

    /// The two race fields coincide whenever traits and stats resolve to the
    /// same record, which is every actor that delegates both or neither.
    @Test func theTwoRaceFieldsAgreeWhenBothFlagsMatch() throws {
        let template = try npc(formID: 0x200, race: 0xA2)
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0003, // useTraits + useStats
            template: 0x200,
            race: 0xA1
        )
        let resolved = try resolver(npcs: [base, template]).resolveStats(base: FormID(0x100))
        #expect(resolved.race == resolved.statsRace)
        #expect(resolved.statsRace.value == FormID(0xA2))
    }

    @Test func withoutUseStatsTheStatsStayLocal() throws {
        let template = try npc(formID: 0x200, healthOffset: 20, race: 0xA2)
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0001, // useTraits only
            template: 0x200,
            healthOffset: 2,
            race: 0xA1
        )
        let resolved = try resolver(npcs: [base, template]).resolveStats(base: FormID(0x100))
        #expect(resolved.stats == ActorSourcedField(
            value: base.stats, source: FormID(0x100)
        ))
        #expect(resolved.race.source == FormID(0x200))
    }

    @Test func statResolutionReportsABrokenChain() throws {
        let base = try npc(formID: 0x100, templateFlags: 0x0002, template: 0xDEAD)
        #expect(throws: ActorResolveError.missingTarget(
            FormID(0xDEAD), referencedBy: FormID(0x100)
        )) {
            _ = try resolver(npcs: [base]).resolveStats(base: FormID(0x100))
        }
    }
}

// MARK: - Fixture builders (file-scope: shared by both suites)

private func record(_ bytes: Data) throws -> ESMRecord {
    let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
    guard case let .record(record)? = children.first else {
        throw ESMError.malformed("fixture did not produce a record")
    }
    return record
}

/// ACBS, 24 bytes (UESP NPC_): uint32 flags, int16 magicka offset, int16
/// stamina offset, uint16 level, calc min, calc max, speed mult, disposition,
/// uint16 template flags, int16 health offset, uint16 bleedout override.
private func acbs(
    flags: UInt32 = 0,
    magickaOffset: Int16 = 0,
    staminaOffset: Int16 = 0,
    level: UInt16 = 1,
    calcMin: UInt16 = 0,
    calcMax: UInt16 = 0,
    templateFlags: UInt16 = 0,
    healthOffset: Int16 = 0
) -> Data {
    var data = Data()
    data.appendUInt32(flags)
    data.appendUInt16(UInt16(bitPattern: magickaOffset))
    data.appendUInt16(UInt16(bitPattern: staminaOffset))
    data.appendUInt16(level)
    data.appendUInt16(calcMin)
    data.appendUInt16(calcMax)
    data.appendUInt16(0) // speed multiplier
    data.appendUInt16(0) // disposition base
    data.appendUInt16(templateFlags)
    data.appendUInt16(UInt16(bitPattern: healthOffset))
    data.appendUInt16(0) // bleedout override
    return data
}

/// A health/magicka/stamina triple in a fixture, spelled as a type rather than
/// a tuple so the strict lint limits stay satisfied.
private struct Triple<Value> {
    let health: Value
    let magicka: Value
    let stamina: Value

    init(_ health: Value, _ magicka: Value, _ stamina: Value) {
        self.health = health
        self.magicka = magicka
        self.stamina = stamina
    }
}

/// DNAM, 52 bytes (UESP NPC_): 18 base skills, 18 skill mods, then the three
/// baked attribute words at 0x24.
private func dnam(_ baked: Triple<Int16>) -> Data {
    var data = Data(count: 0x24)
    data.appendUInt16(UInt16(bitPattern: baked.health))
    data.appendUInt16(UInt16(bitPattern: baked.magicka))
    data.appendUInt16(UInt16(bitPattern: baked.stamina))
    data.append(Data(count: 52 - data.count))
    return data
}

private func npc(
    formID: UInt32,
    flags: UInt32 = 0,
    templateFlags: UInt16 = 0,
    template: UInt32? = nil,
    magickaOffset: Int16 = 0,
    staminaOffset: Int16 = 0,
    level: UInt16 = 1,
    calcMin: UInt16 = 0,
    calcMax: UInt16 = 0,
    healthOffset: Int16 = 0,
    characterClass: UInt32? = nil,
    race: UInt32? = nil,
    baked: Triple<Int16>? = nil
) throws -> ActorBase {
    var fields = ESMFixture.field("ACBS", acbs(
        flags: flags,
        magickaOffset: magickaOffset,
        staminaOffset: staminaOffset,
        level: level,
        calcMin: calcMin,
        calcMax: calcMax,
        templateFlags: templateFlags,
        healthOffset: healthOffset
    ))
    if let template {
        fields += formIDField("TPLT", template)
    }
    if let race {
        fields += formIDField("RNAM", race)
    }
    if let characterClass {
        fields += formIDField("CNAM", characterClass)
    }
    if let baked {
        fields += ESMFixture.field("DNAM", dnam(baked))
    }
    return try ActorBase(
        record: record(ESMFixture.record("NPC_", formID: formID, data: fields)),
        localized: false
    )
}

/// RACE DATA, 128 bytes (UESP RACE): 14 skill bytes + 2 pad, four
/// height/weight floats, flags at 0x20, the three starting attributes at 0x24,
/// and the three regen floats at 0x54.
private func raceDATA(starting: Triple<Float>, regen: Triple<Float>) -> Data {
    var data = Data(count: 0x24)
    for value in [starting.health, starting.magicka, starting.stamina] {
        data.appendUInt32(value.bitPattern)
    }
    data.append(Data(count: 0x54 - data.count))
    for value in [regen.health, regen.magicka, regen.stamina] {
        data.appendUInt32(value.bitPattern)
    }
    data.append(Data(count: 128 - data.count))
    return data
}

private func race(
    formID: UInt32,
    starting: Triple<Float>,
    regen: Triple<Float>
) throws -> Race {
    try Race(
        record: record(ESMFixture.record(
            "RACE",
            formID: formID,
            data: ESMFixture.field("DATA", raceDATA(starting: starting, regen: regen))
        )),
        localized: false
    )
}

/// CLAS DATA, 36 bytes (UESP CLAS): uint32 unknown, trainer skill + level, 18
/// skill weights, float bleedout at 0x18, uint32 voice points, then the three
/// attribute weight bytes at 0x20 and a flag byte.
private func characterClass(
    formID: UInt32,
    weights: Triple<UInt8>,
    bleedout: Float
) throws -> CharacterClass {
    var data = Data(count: 0x18)
    data.appendUInt32(bleedout.bitPattern)
    data.appendUInt32(0) // voice points
    data.append(contentsOf: [weights.health, weights.magicka, weights.stamina, 0])
    let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestClass"))
        + ESMFixture.field("DATA", data)
    return try CharacterClass(
        record: record(ESMFixture.record("CLAS", formID: formID, data: fields)),
        localized: false
    )
}

private func formIDField(_ type: String, _ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(value)
    return ESMFixture.field(type, data)
}

private func resolver(npcs: [ActorBase]) -> ActorTemplateResolver {
    ActorTemplateResolver(
        actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
        leveledActors: [:]
    )
}
