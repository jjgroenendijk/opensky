// The list plumbing `magicmenu.swf` and `giftmenu.swf` share with the inventory movie:
// the same `/Menu_mc/InventoryLists_mc` lists, filled through `EntriesA`. The movie's
// `ItemSelect` acts on the row its list has selected. See docs/engine/inventory-menu.md.

import Foundation
public import OpenSkyFormatsSWF

/// A call a list menu's movie makes.
nonisolated public enum ItemListMovieEvent: Equatable, Sendable {
    /// Acts on the row the movie's item list has selected.
    case select
    case close
    /// The movie's third bottom-bar button.
    case aux
    /// The enchanting slider moved to this value.
    case sliderMoved(Int)
    /// The enchanting slider closed at this value; `accepted` is false on cancel.
    case sliderClosed(Int, accepted: Bool)
}

/// Where a list movie keeps its category list and its item list.
nonisolated struct ItemListMovieLayout: Equatable, Sendable {
    let listsPath: String
    let categoryListPath: String
    let itemListPath: String

    init(listsPath: String) {
        self.listsPath = listsPath
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

    public static func activate(runtime: SWFMovieRuntime) {
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

    /// Writes the rows. The first write with rows also slides the item panel out, as
    /// the inventory does, then writes again, because the slide resets the selection.
    static func publish(
        _ model: ItemListMenuModel,
        layout: ItemListMovieLayout = .inventory,
        runtime: SWFMovieRuntime
    ) {
        write(model, layout: layout, runtime: runtime)
        let card = ItemCardSubMenuBridge.self
        guard let selected = model.selected else { return }
        if card.listsState(atPath: layout.listsPath, runtime: runtime) != card.twoPanelsState {
            card.showItemsList(atPath: layout.listsPath, runtime: runtime)
            write(model, layout: layout, runtime: runtime)
        }
        card.fadeInCard(runtime: runtime)
        let listsSpells = model.categories.contains { $0.rows.contains { $0.spellCard != nil } }
        if listsSpells {
            InventoryMenuMovieBridge.publishSpellCard(
                selected.spellCard, name: selected.name, runtime: runtime
            )
        }
    }

    /// The CLI's way in: `categories` with the first tab and row `row` selected.
    public static func publish(
        _ categories: [ItemListCategory], row: Int = 0, runtime: SWFMovieRuntime
    ) {
        var model = ItemListMenuModel(categories: categories)
        model.selectRow(row)
        publish(model, runtime: runtime)
    }

    public static func prepare(runtime: SWFMovieRuntime) {
        prepare(runtime: runtime) { _ in }
    }

    /// The row labels and the selection the movie holds, for the CLI.
    public static func rowLabels(runtime: SWFMovieRuntime)
        -> (categories: [String], rows: [String])
    {
        let layout = ItemListMovieLayout.inventory
        let bridge = InventoryMenuMovieBridge.self
        return (
            bridge.entryLabels(runtime: runtime, atPath: layout.categoryListPath),
            bridge.entryLabels(runtime: runtime, atPath: layout.itemListPath)
        )
    }

    private static func write(
        _ model: ItemListMenuModel, layout: ItemListMovieLayout, runtime: SWFMovieRuntime
    ) {
        let bridge = InventoryMenuMovieBridge.self
        bridge.publish(
            rows: model.categories.enumerated().map { index, category in
                [
                    "text": .string(category.label), "index": .integer(index),
                    "flag": .integer(InventoryMenuModel.categoryFlag(index)),
                    "bDontHide": .boolean(true), "savedItemIndex": .integer(0)
                ]
            },
            atPath: layout.categoryListPath, runtime: runtime
        )
        bridge.publish(
            rows: model.rows.enumerated().map { index, row in
                [
                    "text": .string(row.name), "index": .integer(index),
                    "count": .integer(Int(row.count)), "equipped": .boolean(row.isEquipped),
                    "equipState": .integer(
                        InventoryEquipState(isEquipped: row.isEquipped, hands: row.hands).rawValue
                    ),
                    "negativeEffect": .boolean(row.isNegative), "enabled": .boolean(true)
                ]
            },
            atPath: layout.itemListPath, runtime: runtime
        )
        bridge.invalidate(categoryListAt: layout.categoryListPath, runtime: runtime)
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
