// The place list over synthetic plugins: named interiors, map markers, a later
// plugin's copy of a cell, and the search.

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
        _ formID: UInt32, named: (editorID: String, name: String), cell: UInt32, markers: Data
    ) -> Data {
        let (editorID, name) = named
        let record = Fixture.recordBytes("WRLD", formID: formID, fields: [
            ("EDID", Fixture.zstring(editorID)), ("FULL", Fixture.zstring(name))
        ])
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
            "Raven Dock", "Riverwood", "The Drunken Mare", "Whiterun"
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
        #expect(list.search("").count == 4)
        #expect(list.search("whiterun").map(\.name) == ["Whiterun", "The Drunken Mare"])
        #expect(list.search("mare interior").map(\.name) == ["The Drunken Mare"])
        #expect(list.search("ISLAND dock").map(\.name) == ["Raven Dock"])
        #expect(list.search("town").map(\.name) == ["Riverwood"])
        #expect(list.search("nowhere").isEmpty)
    }

    @Test func weathersAreListedByName() throws {
        #expect(try list().weathers == ["SkyrimClear", "SkyrimStormRain"])
        #expect(StartPlaceList.empty.places.isEmpty)
    }

    @Test func recentPlacesKeepTheNewestFirstUpToTheLimit() throws {
        let suite = "StartPlaceListTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LaunchPreferences.savedRecentPlaces(userDefaults: defaults).isEmpty)
        for index in 0 ..< LaunchPreferences.recentPlaceLimit + 2 {
            LaunchPreferences.rememberRecent(
                LaunchRecentPlace(start: .cell("Cell\(index)"), name: "Place\t\(index)"),
                userDefaults: defaults
            )
        }
        LaunchPreferences.rememberRecent(
            LaunchRecentPlace(start: .cell("Cell5"), name: "Again"), userDefaults: defaults
        )
        let recent = LaunchPreferences.savedRecentPlaces(userDefaults: defaults)
        #expect(recent.count == LaunchPreferences.recentPlaceLimit)
        #expect(recent.first == LaunchRecentPlace(start: .cell("Cell5"), name: "Again"))
        #expect(recent[1] == LaunchRecentPlace(start: .cell("Cell9"), name: "Place 9"))
        #expect(recent.filter { $0.start == .cell("Cell5") }.count == 1)
    }
}
