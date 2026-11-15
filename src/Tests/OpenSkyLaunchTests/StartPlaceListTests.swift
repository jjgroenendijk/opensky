// The place list over synthetic plugins: named interiors, map markers, a later
// plugin's copy of a cell, a city worldspace under its parent, and the search.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyLaunch
import Testing

struct StartPlaceListTests {
    private typealias Fixture = ESMFixture

    private static func label(_ value: UInt32) -> Data {
        Fixture.u32(value)
    }

    /// An interior cell inside its block and sub-block, with an empty children group.
    private static func interior(_ formID: UInt32, editorID: String, name: String?) -> Data {
        var fields: [(String, Data)] = [("EDID", Fixture.zstring(editorID))]
        if let name {
            fields.append(("FULL", Fixture.zstring(name)))
        }
        fields.append(("DATA", Fixture.u16(1)))
        let cell = Fixture.recordBytes("CELL", formID: formID, fields: fields)
        let children = Fixture.childGroup(parent: formID, groupType: 6, contents: Data())
        let sub = Fixture.group(label: label(0), groupType: 3, contents: cell + children)
        return Fixture.group(label: label(0), groupType: 2, contents: sub)
    }

    private static func marker(_ formID: UInt32, name: String, type: UInt8) -> Data {
        Fixture.recordBytes("REFR", formID: formID, fields: [
            ("NAME", Fixture.u32(0x10)),
            ("XMRK", Data()),
            ("FNAM", Fixture.u8(0x03)),
            ("FULL", Fixture.zstring(name)),
            ("TNAM", Fixture.u8(type, 0)),
            ("DATA", Fixture.f32(100, 200, 300, 0, 0, 0))
        ])
    }

    /// A worldspace whose persistent cell holds `markers`.
    private static func world(
        _ formID: UInt32, named: (editorID: String, name: String), cell: UInt32, markers: Data,
        parent: UInt32? = nil
    ) -> Data {
        let (editorID, name) = named
        var fields = [("EDID", Fixture.zstring(editorID)), ("FULL", Fixture.zstring(name))]
        if let parent {
            fields.append(("WNAM", Fixture.u32(parent)))
        }
        let record = Fixture.recordBytes("WRLD", formID: formID, fields: fields)
        let persistentCell = Fixture.recordBytes("CELL", formID: cell, fields: [
            ("DATA", Fixture.u16(0))
        ])
        let persistent = Fixture.childGroup(parent: cell, groupType: 8, contents: markers)
        let children = Fixture.childGroup(parent: cell, groupType: 6, contents: persistent)
        return record
            + Fixture.childGroup(parent: formID, groupType: 1, contents: persistentCell + children)
    }

    private static func weather(_ formID: UInt32, editorID: String) -> Data {
        Fixture.recordBytes("WTHR", formID: formID, fields: [("EDID", Fixture.zstring(editorID))])
    }

    private static var baseBytes: Data {
        Fixture.tes4()
            + Fixture.topGroup(
                "CELL",
                contents: interior(0x1234, editorID: "WhiterunInn", name: "The Bannered Mare")
                    + interior(0x1235, editorID: "TestCellNoName", name: nil)
            )
            + Fixture.topGroup(
                "WRLD",
                contents: world(
                    0x3C, named: ("Tamriel", "Skyrim"), cell: 0xD74,
                    markers: marker(0x900, name: "Riverwood", type: 2)
                        + marker(0x901, name: "Whiterun", type: 1)
                )
            )
            + Fixture.topGroup(
                "WTHR",
                contents: weather(0x700, editorID: "SkyrimStormRain")
                    + weather(0x701, editorID: "SkyrimClear")
            )
    }

    private func loadOrder() throws -> LoadOrderPlugins {
        let base = try ESMFile(data: Self.baseBytes)
        let mod = try ESMFile(data: Fixture.tes4(masters: ["Skyrim.esm"])
            + Fixture.topGroup(
                "CELL",
                contents: Self.interior(0x1234, editorID: "WhiterunInn", name: "The Drunken Mare")
            )
            + Fixture.topGroup(
                "WRLD",
                contents: Self.world(
                    0x0100_0800, named: ("ModIsland", "The Island"), cell: 0x0100_0801,
                    markers: Self.marker(0x0100_0802, name: "Raven Dock", type: 33)
                )
                    + Self.world(
                        0x0100_0810, named: ("WhiterunWorld", "Whiterun"), cell: 0x0100_0811,
                        markers: Self.marker(0x0100_0812, name: "Whiterun Gate", type: 40),
                        parent: 0x3C
                    )
            ))
        return LoadOrderPlugins([("Skyrim.esm", base), ("Mod.esp", mod)])
    }

    private func list() throws -> StartPlaceList {
        try StartPlaceList(loadOrder: loadOrder()) { text, _ in
            if case let .inline(string) = text {
                return string
            }
            return nil
        }
    }

    @Test func namedInteriorsAndMarkersAreListedByName() throws {
        let list = try list()
        #expect(list.places.map(\.name) == [
            "Raven Dock", "Riverwood", "The Drunken Mare", "Whiterun", "Whiterun Gate"
        ])
        let inn = try #require(list.place(for: .cell("WhiterunInn")))
        #expect(inn.detail == "Interior")
        #expect(inn.editorID == "WhiterunInn")
    }

    @Test func aMarkerNamesItsWorldspaceItsPluginAndItsType() throws {
        let list = try list()
        let riverwood = try #require(list.places.first { $0.name == "Riverwood" })
        #expect(riverwood.start
            == .marker(worldspace: "Tamriel", plugin: "Skyrim.esm", objectID: 0x900))
        #expect(riverwood.detail == "Skyrim, Town")
        let dock = try #require(list.places.first { $0.name == "Raven Dock" })
        #expect(dock.start
            == .marker(worldspace: "ModIsland", plugin: "Mod.esp", objectID: 0x802))
        #expect(dock.detail == "The Island, Docks")
    }

    @Test func theListLoadsFromAnInstallFolder() throws {
        let install = FileManager.default.temporaryDirectory
            .appending(
                path: "StartPlaceListTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let data = install.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: install) }
        try Self.baseBytes.write(to: data.appending(path: "Skyrim.esm"))
        let root = GameDataRoot(installURL: install, dataURL: data, source: .environment)
        let list = try StartPlaceList.load(root: root)
        #expect(list.places.map(\.name) == ["Riverwood", "The Bannered Mare", "Whiterun"])
        #expect(list.weathers == ["SkyrimClear", "SkyrimStormRain"])
        try FileManager.default.removeItem(at: data.appending(path: "Skyrim.esm"))
        #expect(throws: (any Error).self) { try StartPlaceList.load(root: root) }
    }

    @Test func aMarkerIsFoundByItsReference() throws {
        let markers = try MapMarkerIndex(plugins: [("Skyrim.esm", ESMFile(data: Self.baseBytes))])
        let first = try #require(markers.all.first)
        #expect(markers.marker(first.reference) == first)
        #expect(markers.all.count == 2)
    }

    @Test func aStartOutsideTheLoadOrderIsNotContained() throws {
        let list = try list()
        #expect(list.contains(.cell("WhiterunInn")))
        #expect(!list.contains(.cell("TestCellNoName")))
        #expect(!list.contains(.marker(worldspace: "Tamriel", plugin: "Gone.esp", objectID: 1)))
        #expect(list.place(for: .normal) == nil)
    }

    @Test func searchMatchesEveryWordInNameEditorIDAndDetail() throws {
        let list = try list()
        #expect(list.search("").count == 5)
        #expect(list.search("whiterun").map(\.name)
            == ["Whiterun", "Whiterun Gate", "The Drunken Mare"])
        #expect(list.search("mare interior").map(\.name) == ["The Drunken Mare"])
        #expect(list.search("ISLAND dock").map(\.name) == ["Raven Dock"])
        #expect(list.search("town").map(\.name) == ["Riverwood"])
        #expect(list.search("nowhere").isEmpty)
    }

    @Test func settlementsKeepTownsAndCitiesGroupedByWorldspace() throws {
        let list = try list()
        let settlements = list.settlements
        #expect(settlements.places.map(\.name) == ["Riverwood", "Whiterun", "Whiterun Gate"])
        #expect(settlements.weathers == list.weathers)
        let riverwood = try #require(settlements.places.first)
        #expect(riverwood.worldspace == "Skyrim")
        #expect(riverwood.isSettlement)
        #expect(settlements.groups.map(\.title) == ["Skyrim"])
        #expect(list.groups.map(\.title) == ["Interior", "Skyrim", "The Island"])
        #expect(list.groups[1].places.map(\.name) == ["Riverwood", "Whiterun", "Whiterun Gate"])
        let gate = try #require(settlements.places.last)
        #expect(gate.detail == "Whiterun, Whiterun Capitol")
        #expect(gate.worldspace == "Skyrim")
    }

    @Test func aMarkerTypeIsASettlementOnlyWhenPeopleLiveThere() {
        func place(type: UInt8) -> StartPlace {
            StartPlace(
                start: .normal, name: "A", detail: "", worldspace: "Skyrim",
                markerType: MapMarkerType(rawValue: type)
            )
        }
        // City, Town, Settlement, Orc Stronghold, Riften and Whiterun Capitol, Raven Rock,
        // Tel Mithryn.
        for type: UInt8 in [1, 2, 3, 28, 36, 40, 54, 56] {
            #expect(place(type: type).isSettlement, "\(type)")
        }
        // None, Cave, Fort, Docks, Whiterun Castle.
        for type: UInt8 in [0, 4, 6, 33, 39] {
            #expect(!place(type: type).isSettlement, "\(type)")
        }
        #expect(!StartPlace(start: .normal, name: "A", detail: "Interior").isSettlement)
    }

    @Test func weathersAreListedByName() throws {
        #expect(try list().weathers == ["SkyrimClear", "SkyrimStormRain"])
        #expect(StartPlaceList.empty.places.isEmpty)
    }
}
