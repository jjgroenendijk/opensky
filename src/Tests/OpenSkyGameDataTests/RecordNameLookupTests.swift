// Magic record names in a localized plugin, read from a string table built in code.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct RecordNameLookupTests {
    /// A localized plugin with one effect and one disease spell, both named by string ID.
    private static func index() throws -> RecordIndex {
        let effect = ESMFixture.record(
            "MGEF", formID: 0x50,
            data: ESMFixture.field("EDID", ESMFixture.zstring("DiseaseEffect"))
                + ESMFixture.field("FULL", ESMFixture.words([0x43]))
                + ESMFixture.field("DATA", MagicEffectFixture.data(baseCost: 1))
        )
        let spell = ESMFixture.record(
            "SPEL", formID: 0x42,
            data: ESMFixture.field("EDID", ESMFixture.zstring("DiseaseSanguinareVampiris"))
                + ESMFixture.field("FULL", ESMFixture.words([0x42]))
                + ESMFixture.field("SPIT", SpellFixture.spit(baseCost: 0))
        )
        let file = try ESMFile(
            data: ESMFixture.tes4(flags: 0x81)
                + ESMFixture.topGroup("MGEF", contents: effect)
                + ESMFixture.topGroup("SPEL", contents: spell)
        )
        return RecordIndex(plugins: [("Test.esm", file)], recordTypes: ["MGEF", "SPEL"])
    }

    private static let names = RecordNameLookup(strings: LocalizedStrings(
        vfs: InMemoryFileSource(files: [
            "Strings/Test_English.strings": StringTableFixture.table(
                kind: .strings,
                entries: [(id: 0x42, text: "Sanguinare Vampiris"), (id: 0x43, text: "Vampirism")]
            )
        ]),
        pluginName: "Test.esm"
    ))

    @Test
    func spellAndEffectNamesComeFromTheStringTable() throws {
        let index = try Self.index()
        let effects = MagicEffectStore(index: index, names: Self.names)
        let spells = SpellStore(index: index, effects: effects, names: Self.names)
        let spell = try #require(spells.spell(editorID: "DiseaseSanguinareVampiris"))
        #expect(spell.displayName == "Sanguinare Vampiris")
        #expect(effects.effects.values.first?.displayName == "Vampirism")
    }

    @Test
    func withoutTablesTheEditorIDStands() throws {
        let spells = try SpellStore(index: Self.index())
        let spell = try #require(spells.spell(editorID: "DiseaseSanguinareVampiris"))
        #expect(spell.displayName == "DiseaseSanguinareVampiris")
    }
}
