// Vanilla presentation layer for the container and barter menus: the measured
// AS2 contract of `Interface\containermenu.swf` and `Interface\bartermenu.swf`.
// One bridge for both, because they share the `ItemMenu` class, components,
// and list paths; only the engine calls differ, selected by
// `ContainerMenuModel.Mode`. Every name was read off the installed movies with
// `openskycli swf action-run` (docs/engine/barter.md).

import Foundation
import OpenSkyFormatsSWF

/// What the movie asked the engine to do.
nonisolated public enum ContainerMenuAction: Equatable, Sendable {
    /// Move the row at this index across: take, store, buy or sell, according
    /// to the model's mode and side.
    case transfer(index: Int)
    /// The container menu's `TakeAllItems`.
    case takeAll
    /// Equip the row at this index, which the container menu offers on the
    /// player's side.
    case equip(index: Int)
    case close
}

nonisolated public enum ContainerMenuMovieBridge: Sendable {
    // MARK: - Movies

    public static let containerMoviePath = "interface\\containermenu.swf"
    public static let barterMoviePath = "interface\\bartermenu.swf"

    public static func moviePath(for mode: ContainerMenuModel.Mode) -> String {
        mode == .barter ? barterMoviePath : containerMoviePath
    }

    // MARK: - Measured paths

    /// The same subtree `inventorymenu.swf` presents, confirmed present on both
    /// of these movies after the cross-movie import merge: 374 display nodes for
    /// the container menu and 369 for the barter menu, each with 0 unresolved
    /// placeholders.
    public static let menuPath = "/Menu_mc"
    public static let listsPath = "\(menuPath)/InventoryLists_mc"
    public static let categoryListPath = "\(listsPath)/CategoriesListHolder/List_mc"
    public static let itemListPath = "\(listsPath)/ItemsListHolder/List_mc"
    public static let bottomBarPath = "\(menuPath)/BottomBar_mc"
    public static let playerInfoPath = "\(bottomBarPath)/PlayerInfoCard_mc"
    public static let goldFieldPath = "\(playerInfoPath)/PlayerGoldValue"
    public static let carryWeightFieldPath = "\(playerInfoPath)/CarryWeightValue"
    /// The merchant's purse. It lives on the player info card's `Barter` frame,
    /// so it does not exist until `SetBarterInfo` has moved the card there.
    public static let vendorGoldFieldPath = "\(playerInfoPath)/VendorGoldValue"

    /// `PLATFORM_PC_KBMOUSE`, the same constant the other two menus pass.
    public static let pcPlatform = 0.0

    public static let invalidateCallback = InventoryMenuMovieBridge.invalidateCallback

    // MARK: - The barter contract

    /// Purse properties `BarterMenu` defines on its menu instance, read back off
    /// the movie after bring-up (docs/engine/barter.md).
    public static let playerGoldName = "iPlayerGold"
    public static let vendorGoldName = "iVendorGold"
    /// `BarterMenu.SetBarterMultipliers(afBuyMult, afSellMult)`, a method on the
    /// menu instance rather than a `GameDelegate` callback, so it is invoked
    /// with a path.
    public static let barterMultiplierCallback = "SetBarterMultipliers"
    /// `BottomBar.SetBarterInfo(aiPlayerGold, aiVendorGold, aiGoldDelta,
    /// astrVendorName)` — the call that moves the player info card onto its
    /// `Barter` frame and fills the vendor purse.
    public static let barterInfoCallback = "SetBarterInfo"

    // MARK: - Host functions

    /// Movie-to-engine calls that change nothing OpenSky models yet. Every name
    /// is in the movie's own constant pool; `PlaySound`, `RequestItemCardInfo`
    /// and `myLog` are in both movies, and bring-up alone makes 20 unanswered
    /// `myLog` calls, which is why this list is installed by `prepare` rather
    /// than by `activate`.
    public static let sinkHostFunctions = [
        "myLog", "PlaySound", "RequestItemCardInfo", "UpdateItem3D", "ShowRawDealWarning"
    ]
    /// `GetRawDealWarningString` is the barter menu's "are you sure" text. Its
    /// only vanilla string is `sNotEnoughVendorGold` — the sell-for-less
    /// warning — and this engine refuses such a sale instead, so it answers the
    /// empty string rather than being left unanswered (docs/engine/barter.md).
    public static let emptyStringHostFunctions = ["GetRawDealWarningString"]

    /// The calls that reach an engine action, per mode. `ItemTransfer`,
    /// `TakeAllItems` and `EquipItem` are in `containermenu.swf`'s pool and not
    /// in `bartermenu.swf`'s; `ItemSelect` and `CloseMenu` are in both.
    public static func actionHostFunctions(for mode: ContainerMenuModel.Mode) -> [String] {
        let shared = ["CloseMenu", "ItemSelect"]
        guard mode == .container else { return shared }
        return shared + ["ItemTransfer", "TakeAllItems", "EquipItem"]
    }

    /// Scaleform's UI-sound hook, reached as a plain `_global` function.
    public static let globalSinkFunctions = ["gfxProcessSound"]

    // MARK: - Bring-up

    /// Installs what the movie reaches for during `start()`, so it must run
    /// before the runtime is started.
    public static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        for name in emptyStringHostFunctions {
            runtime.registerHostFunction(name) { _ in .string("") }
        }
        let global = runtime.runtime.globalObject
        for name in globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
    }

    /// Registers the outbound calls that mutate inventory and brings the movie's
    /// own menu object up. Runs after `start()`, because the entry points belong
    /// to the placed `ContainerMenuObj` or `BarterMenuObj` instance.
    public static func activate(
        runtime: SWFMovieRuntime,
        mode: ContainerMenuModel.Mode,
        onAction: @escaping @MainActor @Sendable (ContainerMenuAction) -> Void
    ) {
        for name in actionHostFunctions(for: mode) {
            runtime.registerHostFunction(name) { call in
                // Resolve before the hop: `call` is not Sendable, so the
                // decoded action is what crosses onto the main actor.
                let resolved = action(named: name, arguments: call.arguments)
                MainActor.assumeIsolated { onAction(resolved) }
                return .undefined
            }
        }
        runtime.callMovie("SetPlatform", arguments: [.number(pcPlatform)])
        runtime.callMovie("InitExtensions")
        focusItemList(runtime: runtime)
    }

    /// Points the movie's focus at the item list, which is the list up and down
    /// move. The same step `inventorymenu.swf` needs, and for the same reason:
    /// there is no live `InputDelegate`, so nothing else routes a key into CLIK.
    public static func focusItemList(runtime: SWFMovieRuntime) {
        runtime.focusTarget = runtime.node(atPath: itemListPath, from: runtime.root)
    }

    // MARK: - Publishing

    /// Fills the movie's lists and totals from the two-pane model.
    ///
    /// Only the active side reaches the item list, because these movies show one
    /// list at a time and swap which owner it belongs to. The bottom bar always
    /// shows the player's own gold and carry weight; the merchant's purse goes
    /// through `SetBarterInfo`.
    public static func publish(_ model: ContainerMenuModel, runtime: SWFMovieRuntime) {
        let pane = model.active
        let categories = pane.categoryLabels
        let entries = pane.entries
        InventoryMenuMovieBridge.publish(
            rows: categories.enumerated().map { index, label in
                ["text": .string(label), "index": .integer(index)]
            },
            atPath: categoryListPath,
            runtime: runtime
        )
        InventoryMenuMovieBridge.publish(
            rows: entries.enumerated().map { index, entry in
                row(for: entry, index: index, model: model)
            },
            atPath: itemListPath,
            runtime: runtime
        )
        runtime.callMovie(invalidateCallback)
        InventoryMenuMovieBridge.select(
            pane.selectedCategoryIndex, count: categories.count,
            atPath: categoryListPath, runtime: runtime
        )
        InventoryMenuMovieBridge.select(
            pane.selectedIndex, count: entries.count,
            atPath: itemListPath, runtime: runtime
        )
        publishTotals(model, runtime: runtime)
    }

    /// One `EntriesA` row: the inventory row plus the barter price. `value`
    /// stays the base value the movie's price factors expect; `price` carries
    /// what OpenSky charges, so tests compare the engine's arithmetic.
    public static func row(
        for entry: InventoryMenuEntry,
        index: Int,
        model: ContainerMenuModel
    ) -> [String: AS2Value] {
        var fields = InventoryMenuMovieBridge.row(for: entry, index: index)
        if let price = model.price(for: entry) {
            fields["price"] = .integer(Int(price))
        }
        return fields
    }
}
