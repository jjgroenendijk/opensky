// The record-dump inspector context over one enchantment fixture plugin.

import FormatsTestSupport
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormats
import OpenSkyGameData

extension EnchantmentFixture {
    /// The inspector context every ENCH dump assertion needs, over one plugin.
    static func inspectorContext(
        for file: ESMFile
    ) throws -> RecordTextDump.MagicInspectorContext {
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: ["MGEF", "SPEL", "SCRL", "ENCH", "FLST", "WEAP", "ARMO"]
        )
        let effects = MagicEffectStore(index: index)
        return RecordTextDump.MagicInspectorContext(
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            magicEffectStore: effects,
            spellStore: SpellStore(index: index, effects: effects),
            enchantmentStore: EnchantmentStore(index: index, effects: effects),
            shoutStore: ShoutStore(index: index),
            equipSlotStore: EquipSlotStore(index: index),
            sourcePlugin: "Base.esm"
        )
    }
}
