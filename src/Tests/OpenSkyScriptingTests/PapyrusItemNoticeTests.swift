// The notice a non-silent item or spell change shows: the player only, named items only.

import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusItemNoticeTests {
    @Test func onlyThePlayerSeesANoticeForANamedItem() {
        let menus = FakeMenuBridge()
        menus.names = [0x12: "Iron Arrow"]
        let presenter = FakePresenter()
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        bridge.ports.menus = menus
        bridge.ports.presenter = presenter
        bridge.stores.itemNotices.added = "Added"

        bridge.itemNoticeLines.postItemNotice(FormID(0x12), count: 12, to: .player, word: \.added)
        bridge.itemNoticeLines.postItemNotice(FormID(0x12), to: .player, word: \.equipped)
        bridge.itemNoticeLines.postItemNotice(FormID(0x13), to: .player, word: \.added)
        let npc = ReferenceKey.plugin(name: "test.esm", objectID: 0x800)
        bridge.itemNoticeLines.postItemNotice(FormID(0x12), to: npc, word: \.removed)

        #expect(presenter.notifications == ["Iron Arrow (12) Added", "Iron Arrow was equipped"])
    }
}
