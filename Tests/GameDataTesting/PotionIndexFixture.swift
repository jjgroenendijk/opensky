// A two-plugin load order whose potion names an effect from its master.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

public enum PotionIndexFixture {
    /// `Base.esm` defines MGEF 1 "Restore Health". `Patch.esp` adds ALCH
    /// 0x0100_0002 "TestPotion", whose one effect links back to that MGEF.
    public static func index() throws -> (index: RecordIndex, patch: ESMFile) {
        let base = try ESMFixture.plugin(records: [
            ESMFixture.record(
                "MGEF",
                formID: 1,
                data: ESMFixture.field("EDID", ESMFixture.zstring("RestoreHealth"))
                    + ESMFixture.field("FULL", ESMFixture.zstring("Restore Health"))
                    + ESMFixture.field("DATA", MagicEffectFixture.data())
            )
        ])
        let alchemyFields = ESMFixture.field("EDID", ESMFixture.zstring("TestPotion"))
            + InventoryFixture.effectFields(effect: 1, magnitude: 10, area: 0, duration: 0)
        let patch = try ESMFixture.plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record("ALCH", formID: 0x0100_0002, data: alchemyFields)]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", patch)],
            recordTypes: ["MGEF", "ALCH"]
        )
        return (index, patch)
    }
}
