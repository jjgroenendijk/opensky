// Synthetic PERK decode coverage, fault half: the unknown ids, the truncated
// payloads and the stray subrecords a mod can author. The well-formed cases
// live in PerkRecordTests. Fixtures contain no bytes from the game install.

import Foundation
@testable import opensky
import Testing

struct PerkRecordFaultTests {
    /// An id the name table does not cover is kept as the byte it is: the perk
    /// runtime still indexes it, and only its name is missing.
    @Test
    func unknownEntryPointAndFunctionIDsSurvive() throws {
        let fields = PerkFixture.fields(
            editorID: "FutureGamePerk",
            effects: [PerkFixture.entryPointEffect(
                entryPoint: 200,
                function: 99,
                tabs: [(runOn: 0, conditions: [])],
                functionType: 9,
                functionData: PerkFixture.word(0xDEAD)
            )]
        )

        let perk = try Perk(record: PerkFixture.record(fields: fields), localized: false)
        let effect = try #require(perk.effects.first)
        let entryPoint = try #require(effect.entryPoint)

        #expect(perk.skipped.total == 0)
        #expect(entryPoint.rawValue == 200)
        #expect(!entryPoint.isKnown)
        #expect(entryPoint.name == nil)
        #expect(entryPoint.description == "unknown entry point (200)")
        #expect(effect.data == .entryPoint(PerkEntryPointEffect(
            entryPoint: entryPoint,
            function: .unknown(raw: 99),
            conditionTabCount: 1
        )))
        #expect(effect.functionType == .unknown(raw: 9))
        // An EPFD under a type this build cannot read is kept verbatim.
        #expect(effect.functionData == .raw(PerkFixture.word(0xDEAD)))
    }

    @Test
    func namesEveryEntryPointTheEnumerationCovers() {
        #expect(PerkEntryPoint.names.count == 92)
        #expect(PerkEntryPoint(rawValue: 0).name == "Calculate Weapon Damage")
        #expect(PerkEntryPoint(rawValue: 35).name == "Mod Attack Damage")
        #expect(PerkEntryPoint(rawValue: 91).name == "Allow Mount Actor")
        #expect(PerkEntryPoint(rawValue: 92).isKnown == false)
    }

    @Test
    func truncatedPayloadsAreTalliedAndTheRestOfTheRecordSurvives() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("BrokenPerk"))
        fields += ESMFixture.field("DATA", Data([1, 2])) // header, too short
        fields += PerkFixture.prke(type: 2)
        fields += ESMFixture.field("DATA", Data([5])) // entry-point data, too short
        fields += ESMFixture.field("PRKC", Data()) // empty tab index
        fields += ESMFixture.field("EPFT", Data([1]))
        fields += ESMFixture.field("EPFD", Data([0, 0])) // float, too short
        fields += PerkFixture.prkf()

        let perk = try Perk(record: PerkFixture.record(fields: fields), localized: false)

        #expect(perk.editorID == "BrokenPerk")
        #expect(perk.data == nil)
        #expect(perk.effects.count == 1)
        let effect = try #require(perk.effects.first)
        #expect(effect.data == nil)
        #expect(effect.conditionTabs.isEmpty)
        // The malformed EPFD is kept raw rather than dropped or guessed at.
        #expect(effect.functionData == .raw(Data([0, 0])))
        #expect(perk.skipped.counts[.malformedField("DATA")] == 2)
        #expect(perk.skipped.counts[.malformedField("PRKC")] == 1)
    }

    @Test
    func straySubrecordsAndMissingMarkersAreTallied() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("StrayPerk"))
        fields += ESMFixture.field("EPFT", Data([1])) // effect-only, no PRKE open
        fields += ESMFixture.field("PRKF", Data()) // end marker, no PRKE open
        fields += ESMFixture.field("ZZZZ", Data([1])) // unknown to the format
        fields += PerkFixture.entryPointEffect(
            entryPoint: 0,
            function: 1,
            tabs: [],
            functionType: 1,
            functionData: PerkFixture.float(1),
            terminated: false
        )
        // A CTDA inside the effect that no PRKC opened a tab for.
        fields += DialogueFixture.condition(functionIndex: 448)

        let perk = try Perk(record: PerkFixture.record(fields: fields), localized: false)

        #expect(perk.effects.count == 1)
        #expect(perk.effects[0].isTerminated == false)
        #expect(perk.skipped.counts[.fieldOutsideEffect("EPFT")] == 1)
        #expect(perk.skipped.counts[.fieldOutsideEffect("PRKF")] == 1)
        #expect(perk.skipped.counts[.unknownField("ZZZZ")] == 1)
        #expect(perk.skipped.counts[.conditionOutsideTab] == 1)
        #expect(perk.skipped.counts[.unterminatedEffect] == 1)
    }

    @Test
    func rejectsARecordOfAnotherType() throws {
        let record = try ActorValueInformationFixture.record(
            type: "AVIF",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("AVOneHanded"))
        )
        #expect(throws: ESMError.self) {
            try Perk(record: record, localized: false)
        }
    }
}
