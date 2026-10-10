// The plugin index an import reads: record types, editor IDs, global types, interior and
// exterior cells, and the base of a changed reference, from one synthetic plugin.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkySave
import Testing

struct ESSPluginRecordsTests {
    private typealias ESM = ESMFixture

    private static func editorID(_ text: String) -> Data {
        ESM.field("EDID", ESM.zstring(text))
    }

    /// Interior CELL 0x5000 with a persistent REFR 0x5001 of CONT 0x6000, and Tamriel
    /// 0x3C with one exterior CELL 0x7000.
    private static func plugin() throws -> ESMFile {
        let reference = ESM.record(
            "REFR",
            formID: 0x5001,
            data: ESM.field("NAME", ESM.words([0x6000]))
        )
        let interior = ESM.record("CELL", formID: 0x5000, data: editorID("HelgenKeep01"))
            + ESM.childGroup(parent: 0x5000, groupType: 6, contents: ESM.childGroup(
                parent: 0x5000, groupType: 8, contents: reference
            ))
        let interiorBlocks = ESM.group(label: Data([0, 0, 0, 0]), groupType: 2, contents: ESM.group(
            label: Data([0, 0, 0, 0]), groupType: 3, contents: interior
        ))
        let exterior = ESM.exteriorBlock(x: 0, y: 0, groupType: 4, contents: ESM.exteriorBlock(
            x: 0, y: 0, groupType: 5, contents: ESM.record("CELL", formID: 0x7000, data: Data())
        ))
        var data = ESM.tes4()
        data += ESM.topGroup("GLOB", contents: ESM.record(
            "GLOB", formID: 0x39,
            data: editorID("GameDaysPassed") + ESM.field("FNAM", Data("s".utf8))
        ))
        data += ESM.topGroup(
            "RACE",
            contents: ESM.record("RACE", formID: 0x13746, data: editorID("NordRace"))
        )
        data += ESM.topGroup("CELL", contents: interiorBlocks)
        data += ESM.topGroup("CONT", contents: ESM.record("CONT", formID: 0x6000, data: Data()))
        data += ESM.topGroup(
            "WRLD",
            contents: ESM.record("WRLD", formID: 0x3C, data: editorID("Tamriel"))
                + ESM.childGroup(parent: 0x3C, groupType: 1, contents: exterior)
        )
        return try ESMFile(data: data)
    }

    private static func save() throws -> ESSFile {
        var fixture = ESSFixture()
        fixture.plugins = ["Skyrim.esm"]
        let inventory = ESSBytes.build { ESSBytes.vsval(0, into: &$0) }
        fixture.changeForms = [ESSFixtureChangeForm(
            kind: 1, value: 0x5001, flags: ESSChangeFlag.Reference.inventory, typeIndex: 0,
            data: inventory
        )]
        return try ESSFile(data: fixture.build())
    }

    private static func skyrim(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID)
    }

    @Test func indexesTheFormsAnImportChecks() throws {
        let index = try ESSPluginIndex.build(
            for: Self.save(),
            plugins: [("Skyrim.esm", Self.plugin())]
        )
        let records = ESSPluginRecords(index: index)
        #expect(records.loadOrder == ["Skyrim.esm"])
        #expect(records.signature(of: Self.skyrim(0x39)) == "GLOB")
        #expect(records.editorID(of: Self.skyrim(0x39)) == "GameDaysPassed")
        #expect(records.globalType(of: Self.skyrim(0x39)) == .short)
        #expect(records.race(editorID: "nordrace") == Self.skyrim(0x13746))
        #expect(records.editorID(of: Self.skyrim(0x3C)) == "Tamriel")
        #expect(records.signature(of: Self.skyrim(0x6000)) == "CONT")
        #expect(records.signature(of: Self.skyrim(0x5001)) == nil)
        #expect(index.referenceBases[ESSPluginIndex.Key(Self.skyrim(0x5001))] == Self
            .skyrim(0x6000))
        #expect(records.declaredVariables(ofScript: "MQ101Script") == nil)
    }

    @Test func cellLocationsSplitInteriorAndExterior() throws {
        let index = try ESSPluginIndex.build(
            for: Self.save(),
            plugins: [("Skyrim.esm", Self.plugin())]
        )
        let records = ESSPluginRecords(index: index)
        #expect(records.cellLocation(space: Self.skyrim(0x5000), position: .zero)
            == .interior(FormID(0x5000)))
        #expect(records.cellLocation(space: Self.skyrim(0x3C), position: SIMD3(-1, 8192, 0))
            == .exterior(CellCoordinate(x: -1, y: 2)))
        #expect(records.cellLocation(space: Self.skyrim(0x7000), position: SIMD3(4096, 0, 0))
            == .exterior(CellCoordinate(x: 1, y: 0)))
        #expect(records.cellLocation(space: Self.skyrim(0x9999), position: .zero) == nil)
    }

    @Test func settingReadsTheEnvironmentFirst() throws {
        let suite = "ess-setting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ESSSaveFolderSetting.folder(environment: [:], userDefaults: defaults) == nil)
        ESSSaveFolderSetting.store(URL(filePath: "/tmp/saves"), in: defaults)
        #expect(ESSSaveFolderSetting.folder(environment: [:], userDefaults: defaults)?.path()
            .hasPrefix("/tmp/saves") == true)
        let environment = [ESSSaveFolderSetting.environmentKey: "/tmp/other"]
        #expect(ESSSaveFolderSetting.folder(environment: environment, userDefaults: defaults)?
            .path()
            .hasPrefix("/tmp/other") == true)
        ESSSaveFolderSetting.clear(in: defaults)
        #expect(ESSSaveFolderSetting.folder(environment: [:], userDefaults: defaults) == nil)
    }
}
