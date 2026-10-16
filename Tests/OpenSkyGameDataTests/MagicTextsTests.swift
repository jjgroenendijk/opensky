// Spell words from the magic string settings, and OpenSky's own names without them.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct MagicTextsTests {
    @Test func theSettingsNameTypesCastingsAndDeliveries() throws {
        let store = try GameSettingFixture.store([
            "sMagicTypeVoicePower": .text("Shout"),
            "sMagicConcentration": .text("Held"),
            "sMagicDeliveryTouch": .text("Contact")
        ])
        let texts = MagicTexts.resolve(store: store) { text in
            guard case let .inline(value) = text else { return nil }
            return value
        }
        #expect(texts.name(of: SpellType.voice) == "Shout")
        #expect(texts.name(of: MagicEffectCastingType.concentration) == "Held")
        #expect(texts.name(of: MagicEffectDelivery.touch) == "Contact")
        #expect(texts.name(of: MagicEffectDelivery.aimed) == MagicEffectDelivery.aimed.description)
        #expect(MagicTexts.settings.count == 15)
    }
}
