// Vanilla presentation layer for the container and barter menus (M12.2.3,
// issue #179): the measured AS2 contract of `Interface\containermenu.swf` and
// `Interface\bartermenu.swf`.
//
// One bridge for two movies, because they are two skins on one class. Both
// import the same `InventoryLists`, `ItemCard` and `BottomBar` components that
// `inventorymenu.swf` imports, both derive their menu class from `ItemMenu`, and
// both address their lists at the same instance paths. What differs is the
// engine calls each one makes (`ItemTransfer` and `TakeAllItems` in the
// container, `SetBarterMultipliers` and the vendor purse in the barter menu),
// which is what `ContainerMenuModel.Mode` selects between.
//
// Every path and name below was read off the user's own installed movies, with
// `openskycli swf action-run --movie containermenu` and `--movie bartermenu` and
// from each movie's own AS2 constant pool. Nothing here is reproduced from
// memory. See docs/engine/barter.md for the measurement.
//
// Device-free and AppKit-free, so it builds into `openskycli` and is unit
// testable against synthetic AS2 fixtures.

import Foundation

/// What the movie asked the engine to do.
nonisolated enum ContainerMenuAction: Equatable, Sendable {
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

nonisolated enum ContainerMenuMovieBridge {
    // MARK: - Movies

    static let containerMoviePath = "interface\\containermenu.swf"
    static let barterMoviePath = "interface\\bartermenu.swf"

    static func moviePath(for mode: ContainerMenuModel.Mode) -> String {
        mode == .barter ? barterMoviePath : containerMoviePath
    }

    // MARK: - Measured paths

    /// The same subtree `inventorymenu.swf` presents, confirmed present on both
    /// of these movies after the cross-movie import merge: 374 display nodes for
    /// the container menu and 369 for the barter menu, each with 0 unresolved
    /// placeholders.
    static let menuPath = "/Menu_mc"
    static let listsPath = "\(menuPath)/InventoryLists_mc"
    static let categoryListPath = "\(listsPath)/CategoriesListHolder/List_mc"
    static let itemListPath = "\(listsPath)/ItemsListHolder/List_mc"
    static let bottomBarPath = "\(menuPath)/BottomBar_mc"
    static let playerInfoPath = "\(bottomBarPath)/PlayerInfoCard_mc"
    static let goldFieldPath = "\(playerInfoPath)/PlayerGoldValue"
    static let carryWeightFieldPath = "\(playerInfoPath)/CarryWeightValue"
    /// The merchant's purse. It lives on the player info card's `Barter` frame,
    /// so it does not exist until `SetBarterInfo` has moved the card there.
    static let vendorGoldFieldPath = "\(playerInfoPath)/VendorGoldValue"

    /// `PLATFORM_PC_KBMOUSE`, the same constant the other two menus pass.
    static let pcPlatform = 0.0

    static let entryArrayName = InventoryMenuMovieBridge.entryArrayName
    static let selectedIndexName = InventoryMenuMovieBridge.selectedIndexName
    static let invalidateCallback = InventoryMenuMovieBridge.invalidateCallback

    // MARK: - The barter contract

    /// Properties `BarterMenu` defines on its own menu instance, read back off
    /// the movie after bring-up (`swf action-run --movie bartermenu --dump
    /// /Menu_mc` reports `fBuyMult = 1.0`, `fSellMult = 1.0`, `iPlayerGold =
    /// 0.0`, `iVendorGold = 0.0`, `iConfirmAmount = 0.0`).
    ///
    /// The movie prices a row itself by scaling the row's `value` with these,
    /// which is why publishing keeps the base value in the row and puts the
    /// price factors here rather than pre-multiplying. That reading is inferred
    /// from the names and from the shape of `SetBarterMultipliers(afBuyMult,
    /// afSellMult)`, not measured against a priced row on screen — the engine's
    /// own prices come from `BarterPricing` and never from the movie.
    static let buyMultiplierName = "fBuyMult"
    static let sellMultiplierName = "fSellMult"
    static let playerGoldName = "iPlayerGold"
    static let vendorGoldName = "iVendorGold"
    /// `BarterMenu.SetBarterMultipliers(afBuyMult, afSellMult)`, a method on the
    /// menu instance rather than a `GameDelegate` callback, so it is invoked
    /// with a path.
    static let barterMultiplierCallback = "SetBarterMultipliers"
    /// `BottomBar.SetBarterInfo(aiPlayerGold, aiVendorGold, aiGoldDelta,
    /// astrVendorName)` — the call that moves the player info card onto its
    /// `Barter` frame and fills the vendor purse.
    static let barterInfoCallback = "SetBarterInfo"

    // MARK: - Host functions

    /// Movie-to-engine calls that change nothing OpenSky models yet. Every name
    /// is in the movie's own constant pool; `PlaySound`, `RequestItemCardInfo`
    /// and `myLog` are in both movies, and bring-up alone makes 20 unanswered
    /// `myLog` calls, which is why this list is installed by `prepare` rather
    /// than by `activate`.
    static let sinkHostFunctions = [
        "myLog", "PlaySound", "RequestItemCardInfo", "UpdateItem3D", "ShowRawDealWarning"
    ]
    /// `GetRawDealWarningString` is the barter menu's "are you sure" text. There
    /// is no raw-deal rule in OpenSky yet, so it answers the empty string rather
    /// than being left unanswered.
    static let emptyStringHostFunctions = ["GetRawDealWarningString"]

    /// The calls that reach an engine action, per mode. `ItemTransfer`,
    /// `TakeAllItems` and `EquipItem` are in `containermenu.swf`'s pool and not
    /// in `bartermenu.swf`'s; `ItemSelect` and `CloseMenu` are in both.
    static func actionHostFunctions(for mode: ContainerMenuModel.Mode) -> [String] {
        let shared = ["CloseMenu", "ItemSelect"]
        guard mode == .container else { return shared }
        return shared + ["ItemTransfer", "TakeAllItems", "EquipItem"]
    }

    /// Scaleform's UI-sound hook, reached as a plain `_global` function.
    static let globalSinkFunctions = ["gfxProcessSound"]

    // MARK: - Bring-up

    /// Installs what the movie reaches for during `start()`, so it must run
    /// before the runtime is started.
    static func prepare(runtime: SWFMovieRuntime) {
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
    static func activate(
        runtime: SWFMovieRuntime,
        mode: ContainerMenuModel.Mode,
        onAction: @escaping @MainActor @Sendable (ContainerMenuAction) -> Void
    ) {
        for name in actionHostFunctions(for: mode) {
            runtime.registerHostFunction(name) { call in
                MainActor.assumeIsolated {
                    onAction(action(named: name, arguments: call.arguments))
                }
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
    static func focusItemList(runtime: SWFMovieRuntime) {
        runtime.focusTarget = runtime.node(atPath: itemListPath, from: runtime.root)
    }

    // MARK: - Publishing

    /// Fills the movie's lists and totals from the two-pane model.
    ///
    /// Only the active side reaches the item list, because these movies show one
    /// list at a time and swap which owner it belongs to. The bottom bar always
    /// shows the player's own gold and carry weight; the merchant's purse goes
    /// through `SetBarterInfo`.
    static func publish(_ model: ContainerMenuModel, runtime: SWFMovieRuntime) {
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

    /// One `EntriesA` row: #289's inventory row plus the barter price.
    ///
    /// The base `value` stays as the movie's own price factors expect to find
    /// it, and `price` carries what OpenSky charges, so the engine's arithmetic
    /// is what a test compares against rather than the movie's.
    static func row(
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
