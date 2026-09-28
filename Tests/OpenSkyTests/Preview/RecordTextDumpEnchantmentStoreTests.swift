// Record dumps that name linked records through `EnchantmentStore`. In-code plugin fixtures only.

import FormatsESMTesting
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsCore
@testable import OpenSkyGameData
import Testing

struct RecordTextDumpEnchantmentStoreTests {
    @Test
    func enchantmentDumpNamesItsEffectsAndItsLinks() throws {
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [
                EnchantmentFixture.record(
                    formID: 0x42,
                    editorID: "TestEnchFire",
                    name: "Burning",
                    enit: EnchantmentFixture.enit(
                        cost: 60,
                        amount: 1500,
                        baseEnchantment: 0x43
                    ),
                    effects: [.init(0x50, magnitude: 25)]
                ),
                EnchantmentFixture.record(
                    formID: 0x43,
                    editorID: "TestEnchFireBase",
                    name: "Burning base",
                    enit: EnchantmentFixture.enit()
                )
            ]
        )
        let dump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "ENCH", in: file),
            localized: false,
            magicInspectorContext: EnchantmentFixture.inspectorContext(for: file)
        )

        #expect(dump.contains("decoded ENCH: editorID TestEnchFire"))
        #expect(dump.contains("type enchantment"))
        #expect(dump.contains("delivery touch"))
        #expect(dump.contains("amount 1500"))
        #expect(dump.contains("base enchantment Burning base"))
        #expect(dump.contains("cost 344 (auto-calc"))
        #expect(dump.contains("Fire Damage — magnitude 25.00"))
    }

    // MARK: - Fixtures
}
