// The `.ess` writer against the reader: a written file reads back to what was written,
// the same contents give the same bytes, and contents the format cannot hold throw.

import Foundation
@testable import OpenSkyFormatsESS
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSFileWriterTests {
    static func header(compression: ESSCompression = .lz4) -> ESSHeader {
        ESSHeader(
            version: 12, saveNumber: 9, playerName: "Prisoner", playerLevel: 4,
            playerLocation: "Riverwood", gameDate: "Sundas, 17th of Last Seed, 4E 201",
            playerRaceEditorID: "NordRace", isFemale: true, experience: 12.5,
            experienceForNextLevel: 175, fileTime: 133_000_000_000_000_000,
            screenshotWidth: 2, screenshotHeight: 1, compression: compression
        )
    }

    static func contents(compression: ESSCompression = .lz4) throws -> ESSFileContents {
        let location = ESSPlayerLocation(
            nextObjectID: 3, worldspace: ESSRefID(kind: .default, value: 0x3C),
            cell: SIMD2(4, -2), space: ESSRefID(kind: .default, value: 0x3C),
            position: SIMD3(17000, -7000, 120)
        )
        let globals = [ESSGlobalVariable(global: ESSRefID(kind: .default, value: 0x39), value: 2.5)]
        let papyrus = ESSPapyrusWriter(
            scripts: [ESSPapyrusScript(
                name: "MyQuestScript", parent: "Quest",
                members: [ESSPapyrusMember(name: "count", type: "Int")]
            )],
            instances: [ESSPapyrusInstance(
                id: 7, scriptName: "MyQuestScript", form: ESSRefID(kind: .formIDArray, value: 1),
                variables: [.integer(5)]
            )]
        )
        var table1 = try ESSGlobalData.group1Types.map(ESSGlobalData.empty)
        table1[1] = try location.table()
        table1[3] = try ESSGlobalVariable.table(globals)
        var table3 = try ESSGlobalData.group3Types.map(ESSGlobalData.empty)
        table3[1] = try papyrus.table()
        return try ESSFileContents(
            header: header(compression: compression),
            screenshot: ESSScreenshot(width: 2, height: 1, rgba: Data(0 ..< 8)),
            plugins: ["Skyrim.esm", "Update.esm"], lightPlugins: ["ccbgssse001-fish.esm"],
            globalData1: table1,
            globalData2: ESSGlobalData.group2Types.map(ESSGlobalData.empty),
            changeForms: [ESSTopicChange(
                form: ESSRefID(kind: .default, value: 0x1234), saidOnce: true
            ).changeForm()],
            globalData3: table3, formIDArray: [0x0100_0D62], visitedWorldspaces: [0x3C]
        )
    }

    @Test(arguments: [ESSCompression.lz4, .none])
    func writtenFileReadsBack(_ compression: ESSCompression) throws {
        let written = try Self.contents(compression: compression)
        let file = try ESSFile(data: written.encoded())
        #expect(file.header == written.header)
        #expect(file.screenshot == written.screenshot)
        #expect(file.formVersion == 78)
        #expect(file.plugins == written.plugins)
        #expect(file.lightPlugins == written.lightPlugins)
        #expect(file.globalData1 == written.globalData1)
        #expect(file.globalData2 == written.globalData2)
        #expect(file.globalData3 == written.globalData3)
        #expect(file.changeForms == written.changeForms)
        #expect(file.formIDArray == written.formIDArray)
        #expect(file.visitedWorldspaces == written.visitedWorldspaces)
        #expect(file.offsetBase == file.expectedOffsetBase)
        #expect(file.locationTable.counts.globalData3 == 5)
        #expect(try file.playerLocation()?.cell == SIMD2(4, -2))
        #expect(try file.globalVariables().first?.value == 2.5)
        let papyrus = try #require(try file.papyrus())
        #expect(papyrus.instances.first?.variables == [.integer(5)])
        #expect(papyrus.script(named: "MyQuestScript")?.parent == "Quest")
        #expect(papyrus.stackStatus == .complete)
    }

    @Test func sameContentsWriteSameBytes() throws {
        let contents = try Self.contents()
        #expect(try contents.encoded() == contents.encoded())
    }

    @Test func everyEmptyTableDecodesAsEmpty() throws {
        var contents = try Self.contents()
        contents.globalData1 = try ESSGlobalData.group1Types.map(ESSGlobalData.empty)
        contents.globalData3 = try ESSGlobalData.group3Types.map(ESSGlobalData.empty)
        let file = try ESSFile(data: contents.encoded())
        #expect(try file.miscStats().isEmpty)
        #expect(try file.globalVariables().isEmpty)
        #expect(try file.createdObjects().isEmpty)
        #expect(try file.weather()?.climate.isNull == true)
        #expect(try file.papyrus()?.instances.isEmpty == true)
        #expect(file.globalData.count == 9 + 15 + 6)
    }

    @Test func refusesWhatTheFormatCannotHold() throws {
        var contents = try Self.contents()
        contents.screenshot = ESSScreenshot(width: 1, height: 1, rgba: Data(count: 4))
        #expect(throws: ESSError.self) { try contents.encoded() }
        contents = try Self.contents(compression: .zlib)
        #expect(throws: ESSError.unsupportedCompression(1)) { try contents.encoded() }
        contents = try Self.contents()
        contents.plugins = (0 ..< 256).map { "plugin\($0).esp" }
        #expect(throws: ESSError.self) { try contents.encoded() }
        var writer = ESSWriter()
        #expect(throws: ESSError.self) { try writer.vsval(0x400000, "too wide") }
    }

    @Test(arguments: [UInt32(0), 0x3F, 0x40, 0x3FFF, 0x4000, 0x3FFFFF])
    func vsvalReadsBack(_ value: UInt32) throws {
        var writer = ESSWriter()
        try writer.vsval(value, "test")
        var reader = ESSReader(writer.data)
        #expect(try reader.vsval("test") == value)
        #expect(reader.isAtEnd)
    }
}
