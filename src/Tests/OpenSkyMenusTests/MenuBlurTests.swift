// Which open menus ask for the menu blur.

@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct MenuBlurTests {
    @Test func theTweenInventoryAndMagicMenusBlurAndOthersDoNot() {
        #expect(!MenuBlur.wanted(open: []))
        #expect(!MenuBlur.wanted(open: [.journalMenu, .systemMenu]))
        #expect(MenuBlur.wanted(open: [TweenMenuCoordinator.identifier]))
        #expect(MenuBlur.wanted(open: [.messageBoxMenu, .inventoryMenu]))
        #expect(MenuBlur.wanted(open: [MagicMenuCoordinator.identifier]))
    }
}
