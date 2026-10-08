// The `.ess` container over synthetic saves: every supported version and compression,
// and each way a file can be broken.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSFileTests {
    @Test(arguments: [UInt16(0), 1, 2])
    func readsSpecialEditionWithEachCompression(_ compression: UInt16) throws {
        var fixture = ESSFixture()
        fixture.compression = compression
        fixture.lightPlugins = ["ccbgssse001-fish.esm"]
        fixture.formIDArray = [0x0001_2345, 0xFE00_1ABC]
        fixture.globalData1 = [(type: 3, data: Data([0]))]
        let file = try ESSFile(data: fixture.build())
        #expect(file.header.version == 12)
        #expect(file.header.compression.rawValue == compression)
        #expect(file.header.playerName == "Prisoner")
        #expect(file.header.playerLevel == 3)
        #expect(file.header.playerRaceEditorID == "NordRace")
        #expect(file.formVersion == 78)
        #expect(file.plugins == ["Skyrim.esm", "Update.esm"])
        #expect(file.lightPlugins == ["ccbgssse001-fish.esm"])
        #expect(file.formIDArray == [0x0001_2345, 0xFE00_1ABC])
        #expect(file.visitedWorldspaces == [0x3C])
        #expect(file.globalData1 == [ESSGlobalData(type: 3, data: Data([0]))])
        #expect(file.screenshot.rgba.count == 2 * 4)
        #expect(file.offsetBase == file.expectedOffsetBase)
    }

    @Test func sectionPositionsCountFromTheFirstGlobalTable() throws {
        let table = ESSFileLocationTable(
            offsets: ESSSectionOffsets(
                formIDArrayCount: 400, unknownTable3: 500, globalData1: 100, globalData2: 200,
                changeForms: 250, globalData3: 300
            ),
            counts: ESSSectionCounts(globalData1: 0, globalData2: 0, globalData3: 0, changeForms: 0)
        )
        let positions = try table.sections(tableEnd: 40, bodyLength: 600)
        #expect(positions.base == 60)
        #expect(positions.formIDArray == 340)
        #expect(positions.unknownTable3 == 440)
    }

    @Test func readsLegendaryEditionWithRGBScreenshot() throws {
        var fixture = ESSFixture()
        fixture.version = 9
        fixture.formVersion = 74
        let file = try ESSFile(data: fixture.build())
        #expect(!file.header.isSpecialEdition)
        #expect(file.header.compression == .none)
        #expect(file.lightPlugins.isEmpty)
        #expect(file.screenshot.rgba == Data([0, 1, 2, 0xFF, 3, 4, 5, 0xFF]))
    }

    @Test func formVersion74HasNoLightPluginList() throws {
        var fixture = ESSFixture()
        fixture.formVersion = 74
        let file = try ESSFile(data: fixture.build())
        #expect(file.lightPlugins.isEmpty)
        #expect(file.plugins.count == 2)
    }

    @Test func summaryReadsHeaderWithoutBody() throws {
        var data = ESSFixture().build()
        let summary = try ESSSummary(data: data)
        data.removeSubrange(summary.bodyOffset...)
        let cut = try ESSSummary(data: data)
        #expect(cut.header.gameDate == "Sundas, 17th of Last Seed, 4E 201")
        #expect(cut.screenshot.width == 2)
        #expect(throws: ESSError.self) { try ESSFile(data: data) }
    }

    @Test func rejectsBadMagic() {
        var data = ESSFixture().build()
        data[data.startIndex] = UInt8(ascii: "X")
        #expect(throws: ESSError.badMagic) { try ESSFile(data: data) }
    }

    @Test func rejectsUnknownVersion() {
        var fixture = ESSFixture()
        fixture.version = 11
        #expect(throws: ESSError.unsupportedVersion(11)) { try ESSFile(data: fixture.build()) }
    }

    @Test func rejectsUnknownFormVersion() {
        var fixture = ESSFixture()
        fixture.formVersion = 200
        #expect(throws: ESSError.unsupportedFormVersion(200)) {
            try ESSFile(data: fixture.build())
        }
    }

    @Test func rejectsUnknownCompression() {
        var fixture = ESSFixture()
        fixture.compression = 7
        #expect(throws: ESSError.unsupportedCompression(7)) { try ESSFile(data: fixture.build()) }
    }

    @Test(arguments: [10, 100, 300])
    func truncationThrowsTypedError(_ cut: Int) {
        var fixture = ESSFixture()
        fixture.compression = 0
        fixture.globalData2 = [(type: 100, data: Data(count: 400))]
        let data = fixture.build()
        #expect(throws: ESSError.self) { try ESSFile(data: data.prefix(data.count - cut)) }
    }

    @Test func rejectsSectionPastTheBody() {
        var fixture = ESSFixture()
        fixture.offsetSkew = [2: 10000]
        #expect {
            try ESSFile(data: fixture.build())
        } throws: { error in
            guard case let ESSError.sectionOutOfRange(section, _) = error else { return false }
            return section == "change forms"
        }
    }

    @Test func rejectsSectionsOutOfOrder() {
        var fixture = ESSFixture()
        fixture.globalData1 = [(type: 0, data: Data(count: 8))]
        fixture.offsetSkew = [1: -40]
        #expect(throws: ESSError.self) { try ESSFile(data: fixture.build()) }
    }

    @Test func keepsUnknownTablesAsBytes() throws {
        var fixture = ESSFixture()
        fixture.globalData2 = [(type: 104, data: Data([1, 2, 3])), (type: 555, data: Data([9]))]
        let file = try ESSFile(data: fixture.build())
        #expect(file.globalData2.map(\.type) == [104, 555])
        #expect(file.globalData2[1].knownType == nil)
        #expect(file.globalData2[1].data == Data([9]))
    }

    /// The game writes one less than the third group holds, so it is read by position.
    @Test func readsEveryThirdGroupTableDespiteTheShortCount() throws {
        var fixture = ESSFixture()
        fixture.globalData3 = [
            (type: 1000, data: Data()),
            (type: 1001, data: Data([4])),
            (type: 1005, data: Data())
        ]
        let file = try ESSFile(data: fixture.build())
        #expect(file.locationTable.counts.globalData3 == 2)
        #expect(file.globalData3.map(\.type) == [1000, 1001, 1005])
    }
}
