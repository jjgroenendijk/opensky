// Race, sex, and name of any actor base, as the Papyrus identity natives read them.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ActorIdentityRecordsTests {
    private static let traits: UInt16 = 0x0001
    private static let baseData: UInt16 = 0x0080

    private static func base(
        _ formID: UInt32, name: String?, female: Bool, race: UInt32,
        template: UInt32? = nil, templateFlags: UInt16 = 0
    ) throws -> ActorBase {
        var stats = Data()
        stats.appendUInt32(female ? 1 : 0)
        stats.append(Data(count: 14))
        stats.appendUInt16(templateFlags)
        stats.append(Data(count: 4))
        var fields = ESMFixture.field("ACBS", stats)
        if let name {
            fields = ESMFixture.field("FULL", ESMFixture.zstring(name)) + fields
        }
        var raceWord = Data()
        raceWord.appendUInt32(race)
        fields += ESMFixture.field("RNAM", raceWord)
        if let template {
            var word = Data()
            word.appendUInt32(template)
            fields += ESMFixture.field("TPLT", word)
        }
        return try ActorBase(
            record: ESMFixture.parseRecord(ESMFixture.record("NPC_", formID: formID, data: fields)),
            localized: false
        )
    }

    private static func records() throws -> ActorIdentityRecords {
        let nord = try Race(
            record: ESMFixture.parseRecord(ESMFixture.record(
                "RACE", formID: 0x13746,
                data: ESMFixture.field("EDID", ESMFixture.zstring("NordRace"))
                    + ESMFixture.field("FULL", ESMFixture.zstring("Nord"))
            )),
            localized: false
        )
        let actors = try [
            base(0x100, name: "Hulda", female: true, race: 0x13746),
            base(
                0x200,
                name: "Bandit",
                female: false,
                race: 0x1,
                template: 0x100,
                templateFlags: traits | baseData
            )
        ]
        return ActorIdentityRecords(
            templates: ActorTemplateResolver(
                actors: Dictionary(uniqueKeysWithValues: actors.map { ($0.formID.rawValue, $0) }),
                leveledActors: [:]
            ),
            races: [nord.formID.rawValue: nord]
        )
    }

    @Test
    func answersFromTheActorsOwnRecord() throws {
        let records = try Self.records()
        #expect(records.race(ofBase: FormID(0x100)) == FormID(0x13746))
        #expect(records.isFemale(ofBase: FormID(0x100)) == true)
        #expect(records.name(of: FormID(0x100)) == .inline("Hulda"))
        #expect(records.name(of: FormID(0x13746)) == .inline("Nord"))
    }

    @Test
    func templateFlagsPassTraitsAndNameDown() throws {
        let records = try Self.records()
        #expect(records.race(ofBase: FormID(0x200)) == FormID(0x13746))
        #expect(records.isFemale(ofBase: FormID(0x200)) == true)
        #expect(records.name(of: FormID(0x200)) == .inline("Hulda"))
        #expect(records.race(ofBase: FormID(0x999)) == nil)
        #expect(records.name(of: FormID(0x999)) == nil)
    }
}
