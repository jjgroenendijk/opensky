// One record by editor ID or FormID over a two-plugin load order: the last
// plugin that holds the record wins.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct LoadOrderPluginsLookupTests {
    private func stat(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record("STAT", formID: formID, data: ESMFixture.field(
            "EDID", ESMFixture.zstring(editorID)
        ))
    }

    /// `Mod.esp` overrides `0x10` and adds its own `0x01000800`.
    private func loadOrder() throws -> LoadOrderPlugins {
        let base = try ESMFile(data: ESMFixture.tes4()
            + ESMFixture.topGroup("STAT", contents: stat(0x10, "Rock")))
        let mod = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"])
            + ESMFixture.topGroup(
                "STAT", contents: stat(0x10, "RockEdited") + stat(0x0100_0800, "NewRock")
            ))
        return LoadOrderPlugins([("Skyrim.esm", base), ("Mod.esp", mod)])
    }

    @Test func theLastPluginWins() throws {
        let plugins = try loadOrder()
        #expect(plugins.record(withFormID: FormID(0x10))?.plugin.name == "Mod.esp")
        #expect(plugins.record(withEditorID: "rock")?.plugin.name == "Skyrim.esm")
        #expect(plugins.record(withEditorID: "NewRock")?.formID == FormID(0x0100_0800))
    }

    @Test func aTokenIsAFormIDOrAnEditorID() throws {
        let plugins = try loadOrder()
        #expect(plugins.record(named: "0x01000800").map { ESMWalk.editorID(of: $0.record) }
            == "NewRock")
        #expect(plugins.record(named: "RockEdited")?.formID == FormID(0x10))
        #expect(plugins.record(named: "Missing") == nil)
    }

    @Test func aFormIDTokenIsOneToEightHexDigits() {
        #expect(FormID(token: "0x1A26F") == FormID(0x1A26F))
        #expect(FormID(token: "1a26f") == FormID(0x1A26F))
        #expect(FormID(token: "0x") == nil)
        #expect(FormID(token: "123456789") == nil)
        #expect(FormID(token: "Rock") == nil)
    }
}
