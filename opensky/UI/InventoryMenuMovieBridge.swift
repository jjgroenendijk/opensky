// Vanilla presentation layer for the inventory menu (M12.2.2, issue #289): the
// measured AS2 contract of `Interface\inventorymenu.swf`. Device-free and
// AppKit-free so it builds into the CLI target and can be unit-tested against
// synthetic AS2 fixtures; it owns no renderer and no movie lifetime. The
// engine-side row list it presents is UI/InventoryMenuModel.swift.
//
// This is the phase-4 data contract `docs/decisions/swf-as2-scope.md` deferred
// to the milestone that owns inventory data: `_CategoriesList`, `EntriesA` and
// `iSelectedIndex`, filled from the player's stored inventory.
//
// Every path and name below was read back off the user's own installed movie
// through `openskycli swf action-run`, never reproduced from memory. See
// docs/engine/inventory-menu.md for the measurement.

import Foundation

/// What the movie asked the engine to do, as reported through its outbound
/// `GameDelegate` calls.
nonisolated enum InventoryMenuAction: Equatable, Sendable {
    /// Equip or unequip the row at this index of the current category.
    case equip(index: Int)
    case drop(index: Int)
    case close
}

/// What one bring-up left behind. All three are gates: the milestone's stated
/// target is zero of each, matching `startmenu.swf`'s 0-of-36 result.
nonisolated struct InventoryMenuDiagnostics: Equatable, Sendable {
    let faults: Int
    let missingNames: Int
    let unhandledInvokes: Int
}

nonisolated enum InventoryMenuMovieBridge {
    static let moviePath = "interface\\inventorymenu.swf"

    /// The `InventoryMenuObj` instance, and the two `Shared.BSScrollingList`
    /// instances underneath it.
    ///
    /// `InventoryLists_mc`, `ItemCard_mc` and `BottomBar_mc` are **imported**
    /// characters — the movie places them but defines none of them, taking each
    /// from a sibling movie under `interface\inventory components\` through
    /// `ImportAssets2`. Without cross-movie import resolution
    /// (`SWFMovieImportMerger`) the whole subtree is absent and the menu comes
    /// up as eleven display nodes with no list at all. Measured paths, read
    /// back with `openskycli swf action-run --movie inventorymenu`.
    static let menuPath = "/Menu_mc"
    static let listsPath = "\(menuPath)/InventoryLists_mc"
    static let categoryListPath = "\(listsPath)/CategoriesListHolder/List_mc"
    static let itemListPath = "\(listsPath)/ItemsListHolder/List_mc"
    static let bottomBarPath = "\(menuPath)/BottomBar_mc"
    /// The two totals are `TextField` instances on the player info card.
    static let playerInfoPath = "\(bottomBarPath)/PlayerInfoCard_mc"
    static let goldFieldPath = "\(playerInfoPath)/PlayerGoldValue"
    static let carryWeightFieldPath = "\(playerInfoPath)/CarryWeightValue"

    /// `PLATFORM_PC_KBMOUSE`, the value the movie's platform switch expects for
    /// keyboard and mouse. Same constant the system menu passes.
    static let pcPlatform = 0.0

    /// `Shared.BSScrollingList`'s backing array of row objects, and the index it
    /// keeps its selection in — the phase-4 contract the scope decision named,
    /// confirmed present on both list objects after bring-up.
    static let entryArrayName = "EntriesA"
    static let selectedIndexName = "iSelectedIndex"

    /// The engine-to-movie callback the lists register with `GameDelegate`.
    /// Writing `EntriesA` changes the data; this is what makes the list rebuild
    /// its rows from it.
    static let invalidateCallback = "InvalidateListData"

    /// Movie-to-engine calls that do not mutate OpenSky state. The boolean
    /// queries answer false; the rest are notifications whose consumers are
    /// outside the row-list surface.
    ///
    /// `myLog` is measured, not guessed: bring-up alone makes 20 unanswered
    /// `myLog` calls from `Components.CrossPlatformButtons`, which is why this
    /// list is installed by `prepare` rather than by `activate`.
    ///
    /// `UpdateItem3D` is the rotating item preview pane, deferred out of this
    /// milestone. Answering it as a no-op is what keeps the deferral visible as
    /// a named decision rather than as an unhandled call in the tally.
    static let sinkHostFunctions = [
        "myLog", "PlaySound", "PlayOKSound", "RequestPlayerInfo",
        "RequestItemCardInfo", "SetSelectedItem", "ShowShoutFistHelp",
        "UpdateItem3D", "EndItem3D"
    ]
    static let falseHostFunctions = ["ShouldShowMod", "GetIsRemoteDevice"]

    /// The outbound calls that reach an engine action. Registered in `activate`
    /// rather than `prepare`, because each needs the callback the caller
    /// supplies.
    ///
    /// Only `CloseMenu` is confirmed: driving the movie through bring-up,
    /// publication and navigation produced 46 outbound calls and none of them
    /// was an equip or a drop. `ItemSelect` and `DropItem` are registered on
    /// the same evidence a name gets anywhere else here — they appear in the
    /// movie's own bytecode — but no measured run has invoked either, so the
    /// engine drives equip and drop from the selection rather than waiting for
    /// them. Treat both as unconfirmed until a run logs one.
    static let actionHostFunctions = ["CloseMenu", "ItemSelect", "DropItem"]

    /// Scaleform's UI-sound hook, reached as a plain `_global` function rather
    /// than through `GameDelegate`. OpenSky has no UI sound bank yet, so it is a
    /// no-op rather than a missing name.
    static let globalSinkFunctions = ["gfxProcessSound"]

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        for name in falseHostFunctions {
            runtime.registerHostFunction(name) { _ in .boolean(false) }
        }
        let global = runtime.runtime.globalObject
        for name in globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
    }

    /// Brings the movie's own menu object up and registers the outbound calls
    /// that mutate inventory. Runs after `start()` because the entry points are
    /// installed by the placed `InventoryMenuObj` instance.
    ///
    /// Nothing here throws. A movie that does not match the measured contract
    /// leaves entries in the missing-API tally, which the panel reports.
    static func activate(
        runtime: SWFMovieRuntime,
        onAction: @escaping @MainActor @Sendable (InventoryMenuAction) -> Void
    ) {
        for name in actionHostFunctions {
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
        // The engine performs the step the absent `InputDelegate` would: a key
        // reaches a CLIK list only through the focus path, so an unfocused
        // movie consumes every arrow key and moves nothing.
        focusItemList(runtime: runtime)
    }

    /// Points the movie's focus at the item list, which is the list up and down
    /// move.
    ///
    /// Focusing the *category* list instead was measured and does not work: the
    /// movie routes left and right through `InventoryLists_mc`'s own
    /// `strHideItemsCode` / `strShowItemsCode` panel states rather than through
    /// the focus path, and with no `InputDelegate` alive nothing drives that
    /// transition, so an up or down key delivered to the category list moves
    /// nothing. Category changes are therefore engine-driven and republished;
    /// see docs/engine/inventory-menu.md.
    static func focusItemList(runtime: SWFMovieRuntime) {
        runtime.focusTarget = runtime.node(atPath: itemListPath, from: runtime.root)
    }

    // MARK: - Publishing

    /// Fills the movie's category and item lists from the engine's row list.
    ///
    /// Each list is written the way the movie writes it itself: replace
    /// `EntriesA` with one plain object per row, set `iSelectedIndex`, then ask
    /// the list to rebuild. A list the movie has not built yet is skipped
    /// rather than fabricated — a menu with no lists is a measurement result,
    /// not something to paper over.
    static func publish(_ model: InventoryMenuModel, runtime: SWFMovieRuntime) {
        let categories = model.categoryLabels
        let entries = model.entries
        publish(
            rows: categories.enumerated().map { index, label in
                ["text": .string(label), "index": .integer(index)]
            },
            atPath: categoryListPath,
            runtime: runtime
        )
        publish(
            rows: entries.enumerated().map { row(for: $1, index: $0) },
            atPath: itemListPath,
            runtime: runtime
        )
        invalidate(runtime: runtime)
        select(
            model.selectedCategoryIndex, count: categories.count,
            atPath: categoryListPath, runtime: runtime
        )
        select(
            model.selectedIndex, count: entries.count,
            atPath: itemListPath, runtime: runtime
        )
        publishTotals(model, runtime: runtime)
    }

    /// One `EntriesA` row. `text`, `count`, `weight`, `value` and `equipped`
    /// are what a vanilla item row displays; `index` is what the movie hands
    /// back on an outbound call.
    static func row(for entry: InventoryMenuEntry, index: Int) -> [String: AS2Value] {
        [
            "text": .string(entry.name),
            "index": .integer(index),
            "count": .integer(Int(entry.count)),
            "weight": .number(Double(entry.weight)),
            "value": .integer(Int(entry.value)),
            "equipped": .boolean(entry.isEquipped),
            "enabled": .boolean(true)
        ]
    }

    // MARK: - Input

    /// Routes the toolkit-free engine menu event into the Flash key model, so
    /// the movie's own CLIK focus path moves the selection. Pointer deltas have
    /// no absolute stage position and remain unsupported here.
    @discardableResult
    static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = key(for: event) else {
            return false
        }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    // MARK: - Readout

    /// Faults, distinct unresolved names and unhandled bridge calls, for the
    /// verification readout and the acceptance gate.
    static func diagnostics(runtime: SWFMovieRuntime) -> InventoryMenuDiagnostics {
        InventoryMenuDiagnostics(
            faults: runtime.tally.faultTotal,
            missingNames: runtime.tally.missingNames.count,
            unhandledInvokes: runtime.invokeLog.unhandled
        )
    }

    /// The row labels the movie actually holds, read back out of its own list.
    /// These prove the engine's rows crossed the bridge rather than that the
    /// engine still has them.
    static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: itemListPath)
    }

    static func categoryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: categoryListPath)
    }

    static func selectedIndex(runtime: SWFMovieRuntime) -> Int? {
        selectedIndex(runtime: runtime, atPath: itemListPath)
    }

    static func selectedCategoryIndex(runtime: SWFMovieRuntime) -> Int? {
        selectedIndex(runtime: runtime, atPath: categoryListPath)
    }
}
