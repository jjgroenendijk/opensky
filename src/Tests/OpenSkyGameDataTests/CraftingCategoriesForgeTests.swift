// The `FORG` default object names the keyword that files a potion under the inventory's
// Misc tab. Synthetic DOBJ record.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct CraftingCategoriesForgeTests {
    private static func categories(dobj tag: String) throws -> CraftingCategories {
        var dobj = Data(tag.utf8)
        dobj.appendUInt32(0x50)
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("DOBJ", contents: ESMFixture.record(
                "DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", dobj)
            ))
        return try CraftingCategories(
            loadOrder: LoadOrderPlugins([("Base.esm", ESMFile(data: data))]),
            itemPlugin: FormIDResolver(pluginName: "Base.esm", masters: [])
        )
    }

    @Test func theForgeDefaultObjectNamesTheMiscPotionKeyword() throws {
        #expect(try Self.categories(dobj: "FORG").forgeKeyword == FormID(stored: 0x50))
        #expect(try Self.categories(dobj: "LSIS").forgeKeyword == nil)
    }
}
