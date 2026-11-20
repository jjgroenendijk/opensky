// The item card calls on a synthetic `/Menu_mc` tree: the panel slide, the card fade,
// the slider and confirm calls, the keys, and the row clips a list shows.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct ItemCardSubMenuRuntimeTests {
    private struct Movie {
        let runtime: SWFMovieRuntime
        let menu: SWFDisplayObject
        let lists: SWFDisplayObject
        let card: SWFDisplayObject
        let categories: SWFDisplayObject
    }

    @discardableResult
    private static func clip(_ name: String, in parent: SWFDisplayObject) -> SWFDisplayObject {
        let child = SWFDisplayObject(content: .clip(nil))
        child.name = name
        parent.addChild(child, atDepth: UInt16(parent.children.count + 1))
        return child
    }

    private static func movie() throws -> Movie {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let menu = clip("Menu_mc", in: runtime.root)
        let lists = clip("InventoryLists_mc", in: menu)
        let holder = clip("CategoriesListHolder", in: lists)
        let categories = clip("List_mc", in: holder)
        let card = clip("ItemCard_mc", in: clip("ItemCardFadeHolder_mc", in: menu))
        return Movie(
            runtime: runtime, menu: menu, lists: lists, card: card, categories: categories
        )
    }

    @Test func showItemsListPlaysTheSlideToTwoPanels() throws {
        let movie = try Self.movie()
        let calls = MenuMovieCallLog(
            runtime: movie.runtime, names: ["ShowItemsList"], on: movie.lists
        )
        movie.lists.object.assign(.integer(1), for: "iCurrentState")
        #expect(ItemCardSubMenuBridge.listsState(runtime: movie.runtime) == 1)
        ItemCardSubMenuBridge.showItemsList(runtime: movie.runtime)
        #expect(calls.arguments(of: "ShowItemsList") == [.boolean(false), .boolean(true)])

        movie.lists.object.assign(.integer(2), for: "iCurrentState")
        ItemCardSubMenuBridge.showItemsList(runtime: movie.runtime)
        #expect(ItemCardSubMenuBridge.listsState(runtime: movie.runtime) == 2)
    }

    @Test func theCardCallsReachTheItemCard() throws {
        let movie = try Self.movie()
        let calls = MenuMovieCallLog(
            runtime: movie.runtime,
            names: ["FadeInCard", "ShowQuantityMenu", "ShowConfirmMessage"],
            on: movie.card
        )
        ItemCardSubMenuBridge.fadeInCard(runtime: movie.runtime)
        ItemCardSubMenuBridge.showQuantity(maximum: 12, runtime: movie.runtime)
        ItemCardSubMenuBridge.showConfirm("Sell?", amount: 3, runtime: movie.runtime)
        #expect(calls.names == ["FadeInCard", "ShowQuantityMenu", "ShowConfirmMessage"])
        #expect(calls.arguments(of: "ShowQuantityMenu") == [.integer(12)])
        #expect(
            movie.menu.object.lookup(ItemCardSubMenuBridge.confirmAmountName)?.property.value
                == .integer(3)
        )
    }

    @Test func theCardIsShownOnlyWhenItAndItsHolderAre() throws {
        let movie = try Self.movie()
        #expect(ItemCardSubMenuBridge.isCardVisible(runtime: movie.runtime))
        movie.card.parent?.isVisible = false
        #expect(!ItemCardSubMenuBridge.isCardVisible(runtime: movie.runtime))
        let empty = try MenuMovieCallLog.emptyRuntime()
        #expect(!ItemCardSubMenuBridge.isCardVisible(runtime: empty))
        #expect(ItemCardSubMenuBridge.listsState(runtime: empty) == nil)
    }

    @Test func onlySubMenuKeysAreSent() throws {
        let movie = try Self.movie()
        #expect(!ItemCardSubMenuBridge.handle(.move(.up), runtime: movie.runtime))
        _ = ItemCardSubMenuBridge.handle(.button(.accept), runtime: movie.runtime)

        let renderer = try #require(FakeRendererPort())
        renderer.swfRuntime = movie.runtime
        #expect(try !ItemCardSubMenuBridge.send(.move(.down), renderer: renderer))
        #expect(try ItemCardSubMenuBridge.send(.button(.cancel), renderer: renderer))
        #expect(renderer.swfInputs.count == 2)
    }

    @Test func shownClipsCountVisibleEntriesOnly() throws {
        let movie = try Self.movie()
        Self.clip("Entry0", in: movie.categories).object.assign(.integer(0), for: "itemIndex")
        let hidden = Self.clip("Entry1", in: movie.categories)
        hidden.object.assign(.integer(1), for: "itemIndex")
        hidden.isVisible = false
        Self.clip("Entry2", in: movie.categories)
        Self.clip("border", in: movie.categories)
        let path = InventoryMenuMovieBridge.categoryListPath
        #expect(InventoryMenuMovieBridge.shownClipCount(runtime: movie.runtime, atPath: path) == 1)
    }

    @Test func aMovieWithoutDropItemLeavesTheDropToTheEngine() throws {
        let movie = try Self.movie()
        #expect(!InventoryMenuMovieBridge.requestDrop(runtime: movie.runtime))
    }
}
