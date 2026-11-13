// The notices of a refused spell and the spell that waits for the other hand.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicInterface
import Testing

@MainActor
struct MagicHitNoticeTests {
    private let texts = GameSettingTexts<MagicHitNoticeText>.vanilla

    private func notice(capped: Bool, nothing: Bool, touch: Bool = false) -> String? {
        MagicHitNoticeText.notice(
            for: SpellTargetRefusal(target: .player, aboveLevelCap: capped, nothingLanded: nothing),
            names: ("Bandit", "Calm"), isTouch: touch, texts: texts
        )
    }

    @Test func aLevelCapSaysTheTargetIsTooPowerful() {
        #expect(notice(capped: true, nothing: true) == "Bandit is too powerful for Calm.")
    }

    @Test func aWholeRefusalSaysResistedExceptByTouch() {
        #expect(notice(capped: false, nothing: true) == "Bandit resisted Calm.")
        #expect(notice(capped: false, nothing: true, touch: true) == nil)
        #expect(notice(capped: false, nothing: false) == nil)
    }

    @Test func aSelfInvisibilitySpellWaitsForTheOtherHand() throws {
        typealias Fixture = SpellbookFixture
        let effect: UInt32 = 0x0A00
        let spell: UInt32 = 0x0A10
        let index = try Fixture.index(extraRecords: [
            Fixture.magicEffect(
                formID: effect, editorID: "InvisibilityEffect",
                data: Fixture.effectData(archetype: 11)
            ),
            Fixture.spell(
                formID: spell, editorID: "Invisibility", equipType: Fixture.Slot.eitherHand,
                spit: Fixture.spit(type: 0, chargeTime: 1, casting: 1, delivery: 0),
                effects: [.init(effect, 0, 30)]
            )
        ])
        let store = SpellStore(index: index)
        let invisibility = try #require(store.spell(editorID: "Invisibility"))
        let healing = try #require(store.spell(editorID: "Healing"))
        #expect(MultiCastRule.refuses(invisibility, otherHandCasting: true))
        #expect(!MultiCastRule.refuses(invisibility, otherHandCasting: false))
        #expect(!MultiCastRule.refuses(healing, otherHandCasting: true))
        #expect(CastNoticeText.notice(for: .castingAnother) == .castingAnother)
    }
}
