// PackageStore built from a synthetic plugin: malformed PACK records are counted.

import FormatsESMTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

struct PackageStoreTests {
    @Test func countsMalformedPackageRecord() throws {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "PACK",
                contents: ESMFixture.malformedRecord("PACK", formID: 0x100)
            )
        let store = try PackageStore(file: ESMFile(data: plugin))

        #expect(store.packages.isEmpty)
        #expect(store.skippedRecords.count(of: "PACK") == 1)
        #expect(store.skippedRecords.byType["PACK"]?.firstError.contains("XXXX") == true)
    }
}
