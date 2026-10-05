// ARTO lookup and the MGEF and DUAL art links over synthetic plugins.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct ArtObjectStoreTests {
    private static func art(_ formID: UInt32, _ editorID: String, type: UInt32 = 0) -> Data {
        var dnam = Data()
        dnam.appendUInt32(type)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DNAM", dnam)
        return ESMFixture.record("ARTO", formID: formID, data: fields)
    }

    private static func effect(_ formID: UInt32) -> Data {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("FireEffect"))
            + ESMFixture.field("DATA", MagicEffectFixture.data())
        return ESMFixture.record("MGEF", formID: formID, data: fields)
    }

    private static func dual(_ formID: UInt32, hitEffectArt: UInt32) -> Data {
        var data = Data()
        for link in [0, 0, 0, hitEffectArt, 0] {
            data.appendUInt32(link)
        }
        data.appendUInt32(0)
        return ESMFixture.record("DUAL", formID: formID, data: ESMFixture.field("DATA", data))
    }

    private static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "Base.esm", objectID: objectID)
    }

    @Test func looksUpArtByFormIDAndEditorID() throws {
        let file = try ESMFixture.plugin(records: [
            Self.art(0x202, "CastArt"), Self.art(0x203, "HitArt", type: 1)
        ])
        let store = ArtObjectStore(plugins: [("Base.esm", file)])
        #expect(store.artObjects.count == 2)
        #expect(store.artObject(Self.id(0x202))?.art.editorID == "CastArt")
        #expect(store.artObject(editorID: "hitart")?.art.artType == .magicHitEffect)
        #expect(store.skippedRecords.isEmpty)
    }

    /// The fixture MGEF names casting art 0x202, hit art 0x203, and enchant art 0x206.
    @Test func resolvesTheThreeMagicEffectArtLinks() throws {
        let file = try ESMFixture.plugin(records: [
            Self.effect(0x10), Self.art(0x202, "CastArt"), Self.art(0x203, "HitArt", type: 1)
        ])
        let plugins = [("Base.esm", file)]
        let effect = try #require(MagicEffectStore(plugins: plugins).effect(Self.id(0x10)))
        let art = try #require(ArtObjectStore(plugins: plugins).art(of: effect))
        #expect(art.casting?.id == Self.id(0x202))
        #expect(art.hitEffect?.art.editorID == "HitArt")
        #expect(art.enchant == nil)
    }

    @Test func resolvesTheDualCastHitEffectArt() throws {
        let file = try ESMFixture.plugin(records: [Self.art(0x203, "HitArt")])
        let store = ArtObjectStore(plugins: [("Base.esm", file)])
        let dual = try DualCastData(record: ESMFixture.parseRecord(Self.dual(
            0x20,
            hitEffectArt: 0x203
        )))
        #expect(store.hitEffectArt(of: dual, fromPlugin: "Base.esm")?.art.editorID == "HitArt")
        #expect(store.resolve(nil, fromPlugin: "Base.esm") == nil)
    }

    @Test func laterPluginOverridesTheArt() throws {
        let base = try ESMFixture.plugin(records: [Self.art(0x202, "CastArt", type: 0)])
        let patch = try ESMFixture.plugin(
            masters: ["Base.esm"],
            records: [Self.art(0x202, "CastArt", type: 2)]
        )
        let store = ArtObjectStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])
        let art = try #require(store.artObject(Self.id(0x202)))
        #expect(art.art.artType == .enchantmentEffect)
        #expect(art.sourcePlugin == "Patch.esp")
    }
}
