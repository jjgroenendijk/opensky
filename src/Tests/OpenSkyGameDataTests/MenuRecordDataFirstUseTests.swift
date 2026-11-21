// The menu records over synthetic plugins: no part is decoded until a menu reads it,
// and reading one part leaves the others alone.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct MenuRecordDataFirstUseTests {
    /// A RACE whose DATA carries the playable flag at 0x20 (UESP RACE DATA).
    private static func playableRace(_ formID: UInt32, editorID: String) -> Data {
        var data = Data(count: 0x20)
        data.appendUInt32(Race.Flags.playable.rawValue)
        return ESMFixture.record(
            "RACE", formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", data)
        )
    }

    private static func records() throws -> MenuRecordData {
        let file = try ESMFixture.plugin(records: [
            Self.playableRace(0x20, editorID: "NordRace"),
            Self.playableRace(0x10, editorID: "BretonRace")
        ])
        return MenuRecordData(
            loadOrder: LoadOrderPlugins([("Base.esm", file)]),
            settings: GameSettingStore(plugins: [])
        )
    }

    @Test func noPartIsDecodedUntilAMenuReadsIt() throws {
        let records = try Self.records()
        #expect(!records.isDecoded(.races))
        #expect(!records.isDecoded(.map))
        #expect(!records.isDecoded(.chargen))
        #expect(!records.isDecoded(.content))
    }

    @Test func readingTheRacesDecodesThemOnceAndLeavesTheRest() throws {
        let records = try Self.records()
        #expect(records.playableRaces.map(\.editorID) == ["BretonRace", "NordRace"])
        #expect(records.isDecoded(.races))
        #expect(!records.isDecoded(.map))
        #expect(!records.isDecoded(.content))
        let copy = records
        #expect(copy.isDecoded(.races))
        #expect(copy.playableRaces.count == 2)
    }

    /// Each part decodes on its first read: the map, the chargen parts, and the System
    /// page's lists. The synthetic plugin has none of their records.
    @Test func eachPartDecodesOnItsFirstRead() throws {
        let records = try Self.records()
        #expect(records.player == nil)
        #expect(records.markers.all.isEmpty)
        #expect(records.worldspaces.isEmpty)
        #expect(records.worldspaceIDs.isEmpty)
        #expect(records.mapWorldspace(of: "Tamriel") == nil)
        #expect(records.isDecoded(.map))
        #expect(!records.isDecoded(.chargen))
        #expect(records.chargen.headParts.isEmpty)
        #expect(records.isDecoded(.chargen))
        #expect(records.installedContent == nil)
        #expect(records.helpManual == nil)
        #expect(records.isDecoded(.content))
    }

    @Test func chargenTypesAreReadTheFirstTimeTheyAreAsked() throws {
        var records = try Self.records()
        #expect(records.chargenTypes.isEmpty)
        let key = ChargenTypeKey(race: FormID(0x20), isFemale: false)
        records.readChargenTypes { _ in [key: [0: 3]] }
        #expect(records.chargenTypes[key] == [0: 3])
    }
}
