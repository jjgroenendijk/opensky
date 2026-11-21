// Which HUD modes the player and the scripts put on the movie's stack.

@testable import OpenSkyMenus
import OpenSkyMenusInterface
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

    @Test func eachOpenMenuPutsItsModeOnInOrder() {
        let inputs = HUDModeInputs(
            sneaking: true, menus: ["TweenMenu", .inventoryMenu, .messageBoxMenu]
        )
        #expect(HUDModeRules.modes(inputs) == [.stealth, .tween, .inventory])
        #expect(HUDModeRules.modes(HUDModeInputs(menus: ["MapMenu"])) == [.worldMap])
        #expect(HUDModeRules.modes(HUDModeInputs(menus: ["Book Menu"])) == [.book])
        #expect(HUDModeRules.modes(HUDModeInputs(menus: ["Training Menu"])) == [.barter])
        #expect(HUDModeRules.modes(HUDModeInputs(menus: [.systemMenu])) == [.journal])
    }

    @Test func dialogueHidesUnderAPausingMenu() {
        let talking = HUDModeInputs(menus: [.dialogueMenu])
        #expect(HUDModeRules.modes(talking) == [.dialogue])
        let bartering = HUDModeInputs(menus: [.dialogueMenu, .barterMenu], worldPaused: true)
        #expect(HUDModeRules.modes(bartering) == [.inventory])
    }

    @Test func commandingAFollowerHidesOnlyTheMeters() {
        let modes = HUDModeRules.modes(HUDModeInputs(ridingHorse: true, favor: true))
        #expect(modes == [.favor, .horse])
        #expect(!HUDModeRules.shows(.health, under: [.favor]))
        #expect(HUDModeRules.shows(.itemInfo, under: [.favor]))
        #expect(!HUDModeRules.shows(.itemInfo, under: [.inventory]))
    }
}
