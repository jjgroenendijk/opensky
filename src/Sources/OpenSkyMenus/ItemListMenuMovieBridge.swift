// The list plumbing `magicmenu.swf` and `giftmenu.swf` share with the inventory movie:
// the same `/Menu_mc/InventoryLists_mc` lists, filled through `EntriesA`. The movie's
// `ItemSelect` acts on the row its list has selected. See docs/engine/inventory-menu.md.

import Foundation
import OpenSkyFormatsSWF

/// A call a list menu's movie makes.
nonisolated public enum ItemListMovieEvent: Equatable, Sendable {
    /// Acts on the row the movie's item list has selected.
    case select
    case close
}

/// Where a list movie keeps its category list and its item list.
nonisolated struct ItemListMovieLayout: Equatable, Sendable {
    let categoryListPath: String
    let itemListPath: String

    init(listsPath: String) {
        categoryListPath = "\(listsPath)/CategoriesListHolder/List_mc"
        itemListPath = "\(listsPath)/ItemsListHolder/List_mc"
    }

    static let inventory = ItemListMovieLayout(listsPath: InventoryMenuMovieBridge.listsPath)
}

nonisolated public enum ItemListMenuMovieBridge: Sendable {
    public static let magicMoviePath = "interface\\magicmenu.swf"
    public static let giftMoviePath = "interface\\giftmenu.swf"
    /// Calls the two movies make that change nothing in OpenSky.
    static let sinkHostFunctions = [
        "ZoomItemModel", "StartMouseRotation", "StopMouseRotation", "SaveIndices",
        "QuantitySliderOpen", "DisabledItemSelect", "ShowTweenMenu", "CloseTweenMenu",
        "ShowShoutFail"
    ]

    static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (ItemListMovieEvent) -> Void
    ) {
        InventoryMenuMovieBridge.prepare(runtime: runtime)
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("ItemSelect") { _ in
            MainActor.assumeIsolated { onEvent(.select) }
            return .undefined
        }
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onEvent(.close) }
            return .undefined
        }
    }

    static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie("SetPlatform", arguments: [.number(SystemMenuMovieBridge.pcPlatform)])
        runtime.callMovie("InitExtensions")
        InventoryMenuMovieBridge.focusItemList(runtime: runtime)
    }

    /// The row the movie's item list has selected, or nil before it has one.
    static func selectedRow(
        layout: ItemListMovieLayout = .inventory, runtime: SWFMovieRuntime
    ) -> Int? {
        InventoryMenuMovieBridge.selectedIndex(runtime: runtime, atPath: layout.itemListPath)
    }

    static func publish(
        _ model: ItemListMenuModel,
        layout: ItemListMovieLayout = .inventory,
        runtime: SWFMovieRuntime
    ) {
        let bridge = InventoryMenuMovieBridge.self
        bridge.publish(
            rows: model.categories.enumerated().map { index, category in
                ["text": .string(category.label), "index": .integer(index)]
            },
            atPath: layout.categoryListPath, runtime: runtime
        )
        bridge.publish(
            rows: model.rows.enumerated().map { index, row in
                [
                    "text": .string(row.name), "index": .integer(index),
                    "count": .integer(Int(row.count)), "equipped": .boolean(row.isEquipped),
                    "enabled": .boolean(true)
                ]
            },
            atPath: layout.itemListPath, runtime: runtime
        )
        bridge.invalidate(runtime: runtime)
        bridge.select(
            model.selectedCategory, count: model.categories.count,
            atPath: layout.categoryListPath, runtime: runtime
        )
        bridge.select(
            model.selectedRow, count: model.rows.count,
            atPath: layout.itemListPath, runtime: runtime
        )
        runtime.focus(runtime.node(atPath: layout.itemListPath, from: runtime.root))
    }
}
