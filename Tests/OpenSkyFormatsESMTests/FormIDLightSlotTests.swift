// The load-order FormID space with light plugins: full plugins number 00 upward,
// light plugins share `FE` with a 12-bit slot, and translation moves FormIDs into it.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct FormIDLightSlotTests {
    private let space = FormIDResolver.loadOrder(
        ["Skyrim.esm", "Small.esl", "Mod.esp", "Flagged.esp"],
        light: ["small.esl", "FLAGGED.ESP"]
    )

    @Test func fullPluginsSkipTheLightOnes() {
        #expect(space.masters == ["Skyrim.esm"])
        #expect(space.pluginName == "Mod.esp")
        #expect(space.lightPlugins == ["Small.esl", "Flagged.esp"])
        let mod = space.localFormID(of: ResolvedFormID(plugin: "mod.esp", objectID: 0x800))
        #expect(mod == FormID(stored: 0x0100_0800))
    }

    @Test func lightPluginTakesItsSlot() {
        let small = ResolvedFormID(plugin: "Small.esl", objectID: 0x801)
        let flagged = ResolvedFormID(plugin: "Flagged.esp", objectID: 0xFFF)
        #expect(space.localFormID(of: small) == FormID(stored: 0xFE00_0801))
        #expect(space.localFormID(of: flagged) == FormID(stored: 0xFE00_1FFF))
        #expect(space.resolve(FormID(stored: 0xFE00_0801)) == small)
        #expect(space.resolve(FormID(stored: 0xFE00_1FFF)) == flagged)
    }

    @Test func lightSlotRejectsWhatItCannotName() {
        let tooLarge = ResolvedFormID(plugin: "Small.esl", objectID: 0x1000)
        #expect(space.localFormID(of: tooLarge) == nil)
        #expect(space.resolve(FormID(stored: 0xFE00_2800)) == nil)
    }

    @Test func spaceWithoutLightPluginsKeepsFEAsAPosition() {
        let plain = FormIDResolver.loadOrder(["Skyrim.esm", "Mod.esp"])
        #expect(plain.lightPlugins.isEmpty)
        #expect(plain.resolve(FormID(stored: 0xFE00_0801))?.plugin == "Mod.esp")
    }

    @Test func translationMovesALightPluginIntoItsSlot() {
        let small = FormIDResolver(pluginName: "Small.esl", masters: ["Skyrim.esm"])
        let translation = FormIDTranslation(source: small, target: space)
        #expect(!translation.isIdentity)
        #expect(translation(FormID(stored: 0x0100_0801)) == FormID(stored: 0xFE00_0801))
        #expect(translation(FormID(stored: 0x0001_2345)) == FormID(stored: 0x0001_2345))
        #expect(translation(FormID(stored: 0x0100_1000)).isNull)
    }

    @Test func translationReadsALightMasterSlot() {
        let patch = FormIDResolver(pluginName: "Patch.esp", masters: ["Skyrim.esm", "Flagged.esp"])
        let translation = FormIDTranslation(source: patch, target: space)
        #expect(translation(FormID(stored: 0x0100_0802)) == FormID(stored: 0xFE00_1802))
    }

    @Test func translationOutOfTheLoadOrderSpace() {
        let mod = FormIDResolver(pluginName: "Mod.esp", masters: ["Skyrim.esm", "Small.esl"])
        let translation = FormIDTranslation(source: space, target: mod)
        #expect(translation(FormID(stored: 0xFE00_0801)) == FormID(stored: 0x0100_0801))
        #expect(translation(FormID(stored: 0xFE00_1801)).isNull)
    }

    @Test func pluginsOpenAsLightFromFlagOrExtension() throws {
        let base = try ESMFile(data: ESMFixture.tes4())
        let flagged = try ESMFile(data: ESMFixture.tes4(flags: 0x201, masters: ["Skyrim.esm"]))
        let plain = try ESMFile(data: ESMFixture.tes4(flags: 0, masters: ["Skyrim.esm"]))
        #expect(!base.isLight(named: "Skyrim.esm"))
        #expect(flagged.isLight(named: "Flagged.esm"))
        #expect(plain.isLight(named: "Unflagged.ESL"))
        let plugins = LoadOrderPlugins([
            ("Skyrim.esm", base), ("Flagged.esm", flagged), ("Mod.esp", plain)
        ])
        #expect(plugins.space.lightPlugins == ["Flagged.esm"])
        #expect(plugins.space.pluginName == "Mod.esp")
    }
}
