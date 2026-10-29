// Which HUD modes the player and the scripts put on the movie's stack.

@testable import OpenSkyMenus
import Testing

struct HUDModeRulesTests {
    @Test func noInputLeavesTheBaseMode() {
        #expect(HUDModeRules.modes(HUDModeInputs()).isEmpty)
    }

    @Test func oneMovementModeAtATimeRidingFirst() {
        let all = HUDModeInputs(sneaking: true, swimming: true, ridingHorse: true)
        #expect(HUDModeRules.modes(all) == [.horse])
        var drawn = all
        drawn.weaponDrawn = true
        #expect(HUDModeRules.modes(drawn) == [.warHorse])
        #expect(HUDModeRules.modes(HUDModeInputs(sneaking: true, swimming: true)) == [.swimming])
        #expect(HUDModeRules.modes(HUDModeInputs(sneaking: true)) == [.stealth])
    }

    @Test func disabledMovementSitsAboveCartMode() {
        let inputs = HUDModeInputs(cart: true, movementDisabled: true, sneaking: true)
        #expect(HUDModeRules.modes(inputs) == [.stealth, .cart, .movementDisabled])
    }

    @Test func theTopModeDecidesWhatOpenSkyMayShow() {
        #expect(HUDModeRules.shows(.health, under: []))
        #expect(!HUDModeRules.shows(.health, under: [.stealth, .cart]))
        #expect(!HUDModeRules.shows(.enemyHealth, under: [.movementDisabled]))
        #expect(HUDModeRules.shows(.health, under: [.cart, .horse]))
        #expect(!HUDModeRules.shows(.stamina, under: [.horse]))
        #expect(HUDModeRules.shows(.stamina, under: [.warHorse]))
        #expect(!HUDModeRules.shows(.itemInfo, under: [.warHorse]))
    }
}
