// A SpellStore over the shared spell fixture records.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyGameData

extension SpellStoreFixture {
    static func store(spellFields: Data) throws -> SpellStore {
        let file = try plugin(
            records: effectRecords + [ESMFixture.record("SPEL", formID: 0x42, data: spellFields)]
        )
        return SpellStore(plugins: [("Base.esm", file)])
    }
}
