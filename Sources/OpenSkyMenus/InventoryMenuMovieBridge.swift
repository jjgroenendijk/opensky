// The measured AS2 contract of `Interface\inventorymenu.swf`. It has no AppKit
// and no renderer, so the CLI builds it and tests drive it with synthetic AS2.
// The row list it shows is InventoryMenuModel.swift. Every path below was read
// back with `openskycli swf action-run`; see docs/engine/inventory-menu.md.

import Foundation
import OpenSkyFormatsSWF

/// What the movie asked the engine to do, as reported through its outbound
/// `GameDelegate` calls.
nonisolated public enum InventoryMenuAction: Equatable, Sendable {
    /// Equip or unequip the row at this index of the current category.
    case equip(index: Int)
    case drop(index: Int)
    case close
}

/// What one bring-up left behind. All three are gates: the milestone's stated
/// target is zero of each, matching `startmenu.swf`'s 0-of-36 result.
nonisolated public struct InventoryMenuDiagnostics: Equatable, Sendable {
    public let faults: Int
    public let missingNames: Int
    public let unhandledInvokes: Int
}

nonisolated public enum InventoryMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\inventorymenu.swf"

    /// The `InventoryMenuObj` instance and its two `Shared.BSScrollingList`s.
    /// The lists are imported from sibling movies, so they exist only after
    /// `SWFMovieImportMerger` resolves the imports.
    public static let menuPath = "/Menu_mc"
    public static let listsPath = "\(menuPath)/InventoryLists_mc"
    public static let categoryListPath = "\(listsPath)/CategoriesListHolder/List_mc"
    public static let itemListPath = "\(listsPath)/ItemsListHolder/List_mc"
    public static let bottomBarPath = "\(menuPath)/BottomBar_mc"
    /// The two totals are `TextField` instances on the player info card.
    public static let playerInfoPath = "\(bottomBarPath)/PlayerInfoCard_mc"
    public static let goldFieldPath = "\(playerInfoPath)/PlayerGoldValue"
    public static let carryWeightFieldPath = "\(playerInfoPath)/CarryWeightValue"

    /// `PLATFORM_PC_KBMOUSE`, the value the movie's platform switch expects for
    /// keyboard and mouse. Same constant the system menu passes.
    public static let pcPlatform = 0.0

    /// `Shared.BSScrollingList`'s backing array of row objects, and the index it
    /// keeps its selection in — the phase-4 contract the scope decision named,
    /// confirmed present on both list objects after bring-up.
    public static let entryArrayName = MenuMovieEntryList.arrayName
    public static let selectedIndexName = "iSelectedIndex"

    /// The engine-to-movie callback the lists register with `GameDelegate`.
    /// Writing `EntriesA` changes the data; this is what makes the list rebuild
    /// its rows from it.
    public static let invalidateCallback = "InvalidateListData"

    /// Movie-to-engine calls that change no OpenSky state. Boolean queries answer
    /// false. Installed in `prepare`, because bring-up already makes `myLog` calls.
    /// `UpdateItem3D` (the item preview) is deferred and answered as a no-op.
    public static let sinkHostFunctions = [
        "myLog", "PlaySound", "PlayOKSound", "RequestPlayerInfo",
        "RequestItemCardInfo", "SetSelectedItem", "ShowShoutFistHelp",
        "UpdateItem3D", "EndItem3D"
    ]
    public static let falseHostFunctions = ["ShouldShowMod", "GetIsRemoteDevice"]

    /// The outbound calls that reach an engine action, registered in `activate`
    /// because each needs the caller's callback. Only `CloseMenu` has been seen
    /// in a run; `ItemSelect` and `DropItem` come from the movie's bytecode.
    public static let actionHostFunctions = ["CloseMenu", "ItemSelect", "DropItem"]

    /// Scaleform's UI-sound hook, reached as a plain `_global` function rather
    /// than through `GameDelegate`. OpenSky has no UI sound bank yet, so it is a
    /// no-op rather than a missing name.
    public static let globalSinkFunctions = ["gfxProcessSound"]

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    public static func prepare(runtime: SWFMovieRuntime) {
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
    public static func activate(
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

    /// Focuses the item list, which up and down move. Focusing the category list
    /// moves nothing (measured), so the engine changes category and republishes.
    public static func focusItemList(runtime: SWFMovieRuntime) {
        runtime.focusTarget = runtime.node(atPath: itemListPath, from: runtime.root)
    }

    // MARK: - Publishing

    /// Fills the category and item lists the way the movie does: replace
    /// `EntriesA`, set `iSelectedIndex`, rebuild. A list not built yet is skipped.
    public static func publish(_ model: InventoryMenuModel, runtime: SWFMovieRuntime) {
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
    public static func row(for entry: InventoryMenuEntry, index: Int) -> [String: AS2Value] {
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
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
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
    public static func diagnostics(runtime: SWFMovieRuntime) -> InventoryMenuDiagnostics {
        InventoryMenuDiagnostics(
            faults: runtime.tally.faultTotal,
            missingNames: runtime.tally.missingNames.count,
            unhandledInvokes: runtime.invokeLog.unhandled
        )
    }

    /// The row labels the movie actually holds, read back out of its own list.
    /// These prove the engine's rows crossed the bridge rather than that the
    /// engine still has them.
    public static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: itemListPath)
    }

    public static func categoryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: categoryListPath)
    }

    public static func selectedIndex(runtime: SWFMovieRuntime) -> Int? {
        selectedIndex(runtime: runtime, atPath: itemListPath)
    }

    public static func selectedCategoryIndex(runtime: SWFMovieRuntime) -> Int? {
        selectedIndex(runtime: runtime, atPath: categoryListPath)
    }
}
