// The item card's quantity slider and confirm message: which key each menu event
// sends, and what the three item movies' answers mean to the engine.

import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

struct ItemCardSubMenuBridgeTests {
    @Test func acceptAndCancelSendTheCardsEnterAndTab() {
        #expect(ItemCardSubMenuBridge.key(for: .button(.accept))?.code == SWFKeyCode.enter)
        #expect(ItemCardSubMenuBridge.key(for: .button(.xButton))?.code == SWFKeyCode.enter)
        #expect(ItemCardSubMenuBridge.key(for: .button(.cancel))?.code == SWFKeyCode.tab)
        #expect(ItemCardSubMenuBridge.key(for: .move(.left))?.code == SWFKeyCode.left)
        #expect(ItemCardSubMenuBridge.key(for: .move(.right))?.code == SWFKeyCode.right)
        #expect(ItemCardSubMenuBridge.key(for: .move(.up)) == nil)
    }

    @Test func theInventoryMovieDropsTheSliderAmount() {
        #expect(
            InventoryMenuMovieBridge.action(named: "ItemDrop", arguments: [.number(9)])
                == .drop(count: 9)
        )
        #expect(InventoryMenuMovieBridge
            .action(named: "ItemDrop", arguments: []) == .drop(count: 1))
    }

    @Test func itemSelectEquipsTheSelectionWhateverTheHandSlot() {
        #expect(
            InventoryMenuMovieBridge.action(named: "ItemSelect", arguments: [.number(1)])
                == .equipSelected
        )
    }

    @Test func theSliderAndThe3DItemReportTheirFlag() {
        #expect(
            InventoryMenuMovieBridge.action(
                named: "QuantitySliderOpen",
                arguments: [.boolean(true)]
            )
                == .quantitySlider(open: true)
        )
        #expect(
            InventoryMenuMovieBridge.action(named: "UpdateItem3D", arguments: [.boolean(false)])
                == .item3D(visible: false)
        )
    }

    @Test func containerAndBarterAnswersCarryTheAmountFirst() {
        #expect(
            ContainerMenuMovieBridge.action(
                named: "ItemTransfer", arguments: [.number(6), .boolean(true)]
            ) == .transfer(count: 6)
        )
        #expect(
            ContainerMenuMovieBridge.action(
                named: "ItemSelect", arguments: [.number(3), .number(25), .boolean(false)]
            ) == .transfer(count: 3)
        )
        #expect(
            ContainerMenuMovieBridge.action(
                named: "QuantitySliderOpen",
                arguments: [.boolean(false)]
            )
                == .subMenu(open: false)
        )
    }
}
