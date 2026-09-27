// The CLAS store above `RecordIndex` (issue #496, roadmap item 20.3): the
// cross-plugin override handling the old single-file `CharacterClassIndex` had
// none of, and the resolution `ActorValueResolver` now derives an actor's
// attribute spread through.
//
// Records are synthetic and built in code (ESMFixture) — never extracted game
// files (AGENTS.md "Legal & IP boundary"). Layout: UESP "Skyrim Mod:Mod File
// Format/CLAS"; see docs/formats/actors.md.

import Foundation
@testable import opensky
import Testing

struct CharacterClassStoreTests {
    /// A patch plugin redefining a class wins, and the winning record is what
    /// the derivation reads — which is the whole point of the move: the old
    /// index keyed raw FormIDs inside one file, so this override was invisible.
    @Test func aLaterPluginsClassWinsAndTheEditorLookupIsCaseInsensitive() throws {
        let base = try plugin(records: [characterClass(
            formID: 0x42, editorID: "CombatWarrior", health: 2, stamina: 1
        )])
        let patch = try plugin(masters: ["Base.esm"], records: [characterClass(
            formID: 0x42, editorID: "PatchedWarrior", health: 5, stamina: 5
        )])
        let store = CharacterClassStore(
            plugins: [("Base.esm", base), ("Patch.esp", patch)]
        )

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
        let base = try plugin(records: [characterClass(
            formID: 0x42, editorID: "CombatWarrior", health: 2, stamina: 1
        )])
        let patch = try plugin(masters: ["Base.esm"], records: [characterClass(
            formID: 0x42, editorID: "PatchedWarrior", health: 5, stamina: 5
        )])
        let store = CharacterClassStore(
            plugins: [("Base.esm", base), ("Patch.esp", patch)]
        )

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
