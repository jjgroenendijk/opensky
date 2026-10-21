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
            "sMagicDeliveryTouch": .text("Contact"),
            "sMagicSchoolDestruction": .text("Ruin")
        ])
        let texts = MagicTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.name(of: SpellType.voice) == "Shout")
        #expect(texts.name(of: MagicEffectCastingType.concentration) == "Held")
        #expect(texts.name(of: MagicEffectDelivery.touch) == "Contact")
        #expect(texts.name(of: MagicEffectDelivery.aimed) == MagicEffectDelivery.aimed.description)
        #expect(MagicTexts.settings.count == 36)
        let destruction = try #require(ActorValueIdentity.index(named: "Destruction"))
        let health = try #require(ActorValueIdentity.index(named: "Health"))
        #expect(texts.school(of: destruction) == "Ruin")
        #expect(texts.school(of: health) == nil)
    }

    @Test func timeLeftCountsInTheLargestUnitRoundedUp() throws {
        let store = try GameSettingFixture.store(["sEffectsListDisplayMins": .text("minutes")])
        let texts = MagicTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        #expect(texts.timeLeft(0.4) == "1 sec")
        #expect(texts.timeLeft(12.2) == "13 secs")
        #expect(texts.timeLeft(61) == "2 minutes")
        #expect(texts.timeLeft(3600) == "1 hour")
        #expect(texts.word("sIngredient", or: "ingredient") == "ingredient")
        #expect(texts.level(minimumSkill: 0) == "Novice")
        #expect(texts.level(minimumSkill: 50) == "Adept")
        #expect(texts.level(minimumSkill: 250) == "Master")
    }
}
