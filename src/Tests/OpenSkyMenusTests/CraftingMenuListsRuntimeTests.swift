// The crafting movie keeps its lists under `/Menu/InventoryLists`, not the inventory's
// `/Menu_mc/InventoryLists_mc`. The list redraw and the item panel slide must reach them.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
struct CraftingMenuListsRuntimeTests {
    @discardableResult
    private static func clip(_ name: String, in parent: SWFDisplayObject) -> SWFDisplayObject {
        let child = SWFDisplayObject(content: .clip(nil))
        child.name = name
        parent.addChild(child, atDepth: UInt16(parent.children.count + 1))
        return child
    }

    @Test func publishingRowsRedrawsAndOpensTheCraftingLists() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let lists = Self.clip("InventoryLists", in: Self.clip("Menu", in: runtime.root))
        let categories = Self.clip("List_mc", in: Self.clip("CategoriesListHolder", in: lists))
        Self.clip("List_mc", in: Self.clip("ItemsListHolder", in: lists))
        lists.object.assign(.integer(1), for: "iCurrentState")
        let listCalls = MenuMovieCallLog(runtime: runtime, names: ["ShowItemsList"], on: lists)
        let categoryCalls = MenuMovieCallLog(
            runtime: runtime, names: ["InvalidateData"], on: categories
        )
        let model = ItemListMenuModel(categories: [
            ItemListCategory(label: "Disenchant", rows: [ItemListRow(tag: 0, name: "Sword")])
        ])

        ItemListMenuMovieBridge.publish(
            model, layout: CraftingMenuMovieBridge.layout, runtime: runtime
        )

        #expect(categoryCalls.arguments(of: "InvalidateData")?.isEmpty == true)
        #expect(listCalls.arguments(of: "ShowItemsList") == [.boolean(false), .boolean(true)])
        let path = CraftingMenuMovieBridge.layout.listsPath
        #expect(ItemCardSubMenuBridge.listsState(atPath: path, runtime: runtime) == 1)
    }
}
