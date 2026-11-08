// The lock survey pairs a save's ExtraLock with the plugin's XLOC, from one synthetic
// plugin and save.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyFormatsTesting
@testable import OpenSkySave
import Testing

struct ESSLockSurveyTests {
    private typealias ESM = ESMFixture

    /// Interior CELL 0x5000 with a REFR 0x5001 that holds a leveled Adept XLOC.
    private static func plugin() throws -> ESMFile {
        let lock = ESM.u8(50, 0, 0, 0) + ESM.u32(0) + ESM.u8(0x04, 0, 0, 0) + Data(count: 8)
        let fields = ESM.field("NAME", ESM.words([0x6000]))
            + ESM.field("DATA", ESM.f32(0, 0, 0, 0, 0, 0)) + ESM.field("XLOC", lock)
        let reference = ESM.record("REFR", formID: 0x5001, data: fields)
        let interior = ESM.record("CELL", formID: 0x5000, data: Data())
            + ESM.childGroup(parent: 0x5000, groupType: 6, contents: ESM.childGroup(
                parent: 0x5000, groupType: 8, contents: reference
            ))
        let blocks = ESM.group(label: Data([0, 0, 0, 0]), groupType: 2, contents: ESM.group(
            label: Data([0, 0, 0, 0]), groupType: 3, contents: interior
        ))
        return try ESMFile(data: ESM.tes4() + ESM.topGroup("CELL", contents: blocks))
    }

    /// A level 17 save whose ExtraLock on 0x5001 stores Expert with the leveled flag.
    private static func save() throws -> ESSFile {
        var fixture = ESSFixture()
        fixture.plugins = ["Skyrim.esm"]
        fixture.playerLevel = 17
        let extra = ESSBytes.build { writer in
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt8(42)
            writer.writeUInt8(75)
            writer.writeUInt8(0x04)
            ESSBytes.refID(kind: 0, value: 0, into: &writer)
            writer.write(Data(count: 8))
        }
        fixture.changeForms = [ESSFixtureChangeForm(
            kind: 1, value: 0x5001, flags: ESSChangeFlag.Object.extraLock, typeIndex: 0,
            data: extra
        )]
        return try ESSFile(data: fixture.build())
    }

    @Test func aLeveledLockPairsTheStoredLevelWithTheAuthoredOne() throws {
        let file = try Self.save()
        let records = try ESSPluginRecords(index: ESSPluginIndex.build(
            for: file, plugins: [("Skyrim.esm", Self.plugin())]
        ))
        let mapping = ESSLoadOrderMapping(file: file, currentPlugins: records.loadOrder)
        let survey = ESSLockSurvey(file: file, mapping: mapping, authored: records.authoredLock)
        #expect(survey.playerLevel == 17)
        #expect(survey.rows.count == 1)
        #expect(survey.rows.first?.storedLevel == 75)
        #expect(survey.rows.first?.storedFlags == 0x04)
        #expect(survey.rows.first?.authored?.level == .adept)
        #expect(survey.leveledPairs == [ESSLeveledLockPair(authored: 50, stored: 75): 1])
    }
}
