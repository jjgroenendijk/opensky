// Synthetic two-plugin MGEF override and EFID resolution coverage.

import FormatsESMTesting
import Foundation
import GameDataTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct MagicEffectStoreTests {
    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try ESMFixture.plugin(records: [
            magicEffect(formID: 0x42, editorID: "BaseEffect", name: "Base name")
        ])
        let patch = try ESMFixture.plugin(
            masters: ["Base.esm"],
            records: [magicEffect(formID: 0x42, editorID: "PatchedEffect", name: "Winner")]
        )
        let store = MagicEffectStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.effect(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.effect.editorID == "PatchedEffect")
        #expect(resolved.displayName == "Winner")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.effect(editorID: "PATCHEDEFFECT")?.id == resolved.id)
        #expect(store.effect(editorID: "baseeffect") == nil)
    }

    @Test
    func alchemyEffectResolvesAcrossTwoPluginIndex() throws {
        let (index, child) = try PotionIndexFixture.index()
        let store = MagicEffectStore(index: index)
        let alchemyRecord = try SpellStoreFixture.firstRecord(type: "ALCH", in: child)
        let item = try Ingestible(record: alchemyRecord, localized: false)
        let resolved = try #require(item.effects.first?.resolved(
            fromPlugin: "Patch.esp",
            using: store
        ))
        #expect(resolved.effect.editorID == "RestoreHealth")
        #expect(resolved.displayName == "Restore Health")
    }

    @Test
    func malformedOverrideFallsBackToEarlierReadableDefinition() throws {
        let base = try ESMFixture.plugin(records: [
            magicEffect(formID: 0x42, editorID: "BaseEffect", name: "Readable")
        ])
        let patch = try ESMFixture.plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record(
                "MGEF",
                formID: 0x42,
                data: ESMFixture.field("EDID", ESMFixture.zstring("BrokenOverride"))
                    + ESMFixture.field("DATA", Data(count: 151))
            )]
        )
        let store = MagicEffectStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let effect = try #require(
            store.effect(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(effect.effect.editorID == "BaseEffect")
        #expect(effect.sourcePlugin == "Base.esm")
    }

    private func magicEffect(formID: UInt32, editorID: String, name: String) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", MagicEffectFixture.data())
        )
    }
}
