// The CLAS store above `RecordIndex`: cross-plugin overrides, and the
// resolution `ActorValueResolver` derives an actor's attribute spread through.
// Layout: UESP "Skyrim Mod:Mod File Format/CLAS"; see docs/formats/actors.md.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CharacterClassStoreTests {
    /// A patch plugin redefining a class wins, and the derivation reads the
    /// winning record.
    @Test func aLaterPluginsClassWinsAndTheEditorLookupIsCaseInsensitive() throws {
        let store = try overriddenStore()

        let resolved = try #require(
            store.characterClass(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.editorID == "PatchedWarrior")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(resolved.characterClass.attributeWeights.health == 5)
        #expect(resolved.characterClass.attributeWeights.stamina == 5)
        #expect(store.characterClass(editorID: "PATCHEDWARRIOR")?.id == resolved.id)
        #expect(store.characterClass(editorID: "combatwarrior") == nil)
    }

    /// A link resolves relative to the plugin carrying it, so an NPC_ in the
    /// base plugin naming class `0x42` reaches the patched definition.
    @Test func aLinkResolvesRelativeToThePluginThatCarriesIt() throws {
        let store = try overriddenStore()

        let resolved = try #require(
            store.resolve(FormID(0x42), fromPlugin: "Base.esm")
        )
        #expect(resolved.editorID == "PatchedWarrior")
        #expect(store.resolve(nil, fromPlugin: "Base.esm") == nil)
        // A plugin the store never saw cannot resolve anything, and says so
        // rather than guessing the base plugin.
        #expect(store.resolve(FormID(0x42), fromPlugin: "Absent.esp") == nil)
        #expect(store.displayString(for: FormID(0x99), fromPlugin: "Base.esm")
            .hasPrefix("[UNRESOLVED]"))
    }

    /// The empty store is what a synthetic scene and a benchmark drive the
    /// derivation with, and it answers nothing rather than failing.
    @Test func theEmptyStoreResolvesNothing() {
        let store = CharacterClassStore()
        #expect(store.isEmpty)
        #expect(store.resolve(FormID(0x42), fromPlugin: "Base.esm") == nil)
        #expect(store.characterClass(editorID: "anything") == nil)
    }

    // MARK: - Fixtures

    /// `Base.esm` defines class 0x42 and `Patch.esp` redefines it.
    private func overriddenStore() throws -> CharacterClassStore {
        let base = try plugin(records: [characterClass(
            formID: 0x42, editorID: "CombatWarrior", health: 2, stamina: 1
        )])
        let patch = try plugin(masters: ["Base.esm"], records: [characterClass(
            formID: 0x42, editorID: "PatchedWarrior", health: 5, stamina: 5
        )])
        return CharacterClassStore(
            plugins: [("Base.esm", base), ("Patch.esp", patch)]
        )
    }

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        data += ESMFixture.topGroup("CLAS", contents: records.reduce(Data(), +))
        return try ESMFile(data: data)
    }

    /// CLAS DATA, 36 bytes (UESP CLAS): uint32 unknown, trainer skill + level,
    /// 18 skill weights, float bleedout at 0x18, uint32 voice points, then the
    /// three attribute weight bytes at 0x20 and a flag byte.
    private func characterClass(
        formID: UInt32,
        editorID: String,
        health: UInt8,
        stamina: UInt8
    ) -> Data {
        let weights = CharacterClass.AttributeWeights(
            health: health,
            magicka: 0,
            stamina: stamina
        )
        var data = Data(count: 0x18)
        data.appendUInt32(Float(0.2).bitPattern)
        data.appendUInt32(0) // voice points
        data.append(contentsOf: [weights.health, weights.magicka, weights.stamina, 0])
        return ESMFixture.record(
            "CLAS",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", data)
        )
    }
}
