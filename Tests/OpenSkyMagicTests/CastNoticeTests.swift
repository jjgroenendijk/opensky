// The HUD notice of a refused cast, and the disenchanting experience setting.

import OpenSkyMagic
import OpenSkyMagicInterface
import Testing

struct CastNoticeTests {
    @Test func onlyPlayerFacingFailuresShowANotice() {
        #expect(CastNoticeText
            .notice(for: .insufficientMagicka(cost: 30, available: 10)) == .insufficientMagicka)
        #expect(CastNoticeText.notice(for: .powerAlreadyUsedToday(day: 2)) == .powerUsed)
        #expect(CastNoticeText.notice(for: .notCharged(remaining: 0.2)) == nil)
        #expect(CastNoticeText.notice(for: .noSpellReadied(.left)) == nil)
    }

    @Test func disenchantingGivesOnePerFourHundredGold() {
        #expect(EnchantingSettings.vanilla.disenchantExperience(worth: 800) == 2)
        #expect(EnchantingSettings.vanilla.disenchantExperience(worth: -5) == 0)
        var settings = EnchantingSettings.vanilla
        settings.disenchantSkillUse = 0.01
        #expect(settings.disenchantExperience(worth: 100) == 1)
    }
}
