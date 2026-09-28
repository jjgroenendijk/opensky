// A SpellStore over the shared spell fixture records.

import FormatsTestSupport
import Foundation
@testable import OpenSkyFormats
@testable import OpenSkyGameData

extension SpellStoreFixture {
    static func store(spellFields: Data) throws -> SpellStore {
        let file = try plugin(
            records: effectRecords + [ESMFixture.record("SPEL", formID: 0x42, data: spellFields)]
        )
        return SpellStore(plugins: [("Base.esm", file)])
    }
}
