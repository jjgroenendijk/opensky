// Cross-plugin KYWD lookup and KWDA resolution over synthetic ESM fixtures.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct KeywordStoreTests {
    @Test
    func laterOverrideWinsAndEditorIDLookupIsCaseInsensitive() throws {
        let base = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x42, editorID: "VendorItemWeapon", hasColor: true)
        ])
        let patch = try KeywordFixture.plugin(
            masters: ["Base.esm"],
            keywords: [KeywordFixture.recordBytes(
                formID: 0x42,
                editorID: "PatchedVendorKeyword",
                hasColor: true
            )]
        )
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.keyword(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.keyword.editorID == "PatchedVendorKeyword")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.keyword(editorID: "patchedvendorkeyword")?.id == resolved.id)
        #expect(store.keyword(editorID: "VENDORITEMWEAPON") == nil)
    }

    @Test
    func laterPluginWinsWhenDifferentIdentitiesShareAnEditorID() throws {
        let base = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x10, editorID: "SharedKeyword", hasColor: true)
        ])
        let patch = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x20, editorID: "SharedKeyword", hasColor: true)
        ])
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        #expect(
            store.keyword(editorID: "sharedkeyword")?.id
                == ResolvedFormID(plugin: "Patch.esp", objectID: 0x20)
        )
    }

    @Test
    func keywordListResolvesTwoPluginLinksAndTestsByName() throws {
        let base = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 1, editorID: "VendorItemWeapon", hasColor: true),
            KeywordFixture.recordBytes(formID: 2, editorID: "WeapTypeSword", hasColor: true)
        ])
        let child = try KeywordFixture.plugin(
            masters: ["Base.esm"],
            keywords: [KeywordFixture.recordBytes(
                formID: 0x0100_0003,
                editorID: "PatchOnlyKeyword",
                hasColor: true
            )]
        )
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", child)])
        var list = KeywordList()
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(0x0100_0003)
        let consumed = try list.decode(field: ESMField(type: "KWDA", data: payload))
        #expect(consumed)

        #expect(
            list.displayStrings(fromPlugin: "Patch.esp", using: store)
                == ["VendorItemWeapon", "PatchOnlyKeyword"]
        )
        #expect(list.contains(editorID: "vendoritemweapon", fromPlugin: "Patch.esp", using: store))
        #expect(list.contains(editorID: "PATCHONLYKEYWORD", fromPlugin: "Patch.esp", using: store))
        #expect(!list.contains(editorID: "WeapTypeSword", fromPlugin: "Patch.esp", using: store))
    }

    @Test
    func danglingKeywordRemainsVisibleInDisplayText() throws {
        let file = try KeywordFixture.plugin(keywords: [])
        let store = KeywordStore(plugins: [("Base.esm", file)])

        #expect(
            store.displayString(for: FormID(0x00AB_CDEF), fromPlugin: "Base.esm")
                == "[UNRESOLVED] 00ABCDEF"
        )
    }
}
