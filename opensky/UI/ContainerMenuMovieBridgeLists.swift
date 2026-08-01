// Totals, input and readback for the container and barter menu bridge (M12.2.3,
// issue #179). Satellite of UI/ContainerMenuMovieBridge.swift, which holds the
// measured contract.
//
// Everything here degrades: a movie whose shape moved leaves a tally entry and
// an empty readout rather than throwing. The list reading and writing itself is
// #289's, called through rather than copied, so the three menus cannot disagree
// about what an `EntriesA` row is.

import Foundation

nonisolated extension ContainerMenuMovieBridge {
    // MARK: - Totals

    /// The bottom bar. The player's gold and carry weight are the two
    /// `TextField` instances #289 measured, filled with the GFx `SetText`
    /// extension; the merchant's purse goes through `SetBarterInfo`, which is
    /// also what moves the player info card onto its `Barter` frame so that
    /// `VendorGoldValue` exists at all.
    static func publishTotals(_ model: ContainerMenuModel, runtime: SWFMovieRuntime) {
        if model.mode == .barter {
            publishBarterInfo(model, runtime: runtime)
        }
        setText("\(model.playerGold)", atPath: goldFieldPath, runtime: runtime)
        setText(
            String(format: "%.0f", model.player.carriedWeight),
            atPath: carryWeightFieldPath,
            runtime: runtime
        )
    }

    /// `BottomBar.SetBarterInfo(aiPlayerGold, aiVendorGold, aiGoldDelta,
    /// astrVendorName)` plus `BarterMenu.SetBarterMultipliers(afBuyMult,
    /// afSellMult)`.
    ///
    /// The gold delta is what the pending transaction would move, which is zero
    /// here: quantity selection and the confirm step are not driven, so nothing
    /// is ever pending. See docs/engine/barter.md.
    static func publishBarterInfo(_ model: ContainerMenuModel, runtime: SWFMovieRuntime) {
        runtime.callMovie(
            barterInfoCallback,
            atPath: bottomBarPath,
            arguments: [
                .integer(Int(model.playerGold)),
                .integer(Int(model.containerGold)),
                .integer(0),
                .string(model.containerName)
            ]
        )
        let factor = model.pricing.basePriceFactor
        runtime.callMovie(
            barterMultiplierCallback,
            atPath: menuPath,
            arguments: [
                .number(factor * model.pricing.buyModifier),
                .number(factor > 0 ? model.pricing.sellModifier / factor : 0)
            ]
        )
        guard let menu = runtime.node(atPath: menuPath, from: runtime.root) else { return }
        menu.object.assign(.integer(Int(model.playerGold)), for: playerGoldName)
        menu.object.assign(.integer(Int(model.containerGold)), for: vendorGoldName)
    }

    private static func setText(_ text: String, atPath path: String, runtime: SWFMovieRuntime) {
        guard runtime.node(atPath: path, from: runtime.root) != nil else { return }
        runtime.callMovie("SetText", atPath: path, arguments: [.string(text)])
    }

    // MARK: - Readback

    /// Faults, distinct unresolved names and unhandled bridge calls. Reuses
    /// #289's shape so the two acceptance gates report the same three numbers.
    static func diagnostics(runtime: SWFMovieRuntime) -> InventoryMenuDiagnostics {
        InventoryMenuMovieBridge.diagnostics(runtime: runtime)
    }

    /// The row labels the movie holds, read back out of its own list. These
    /// prove the engine's rows crossed the bridge.
    static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        InventoryMenuMovieBridge.entryLabels(runtime: runtime, atPath: itemListPath)
    }

    static func categoryLabels(runtime: SWFMovieRuntime) -> [String] {
        InventoryMenuMovieBridge.entryLabels(runtime: runtime, atPath: categoryListPath)
    }

    static func selectedIndex(runtime: SWFMovieRuntime) -> Int? {
        InventoryMenuMovieBridge.selectedIndex(runtime: runtime, atPath: itemListPath)
    }

    static func selectedCategoryIndex(runtime: SWFMovieRuntime) -> Int? {
        InventoryMenuMovieBridge.selectedIndex(runtime: runtime, atPath: categoryListPath)
    }

    /// The merchant purse the movie is showing, read back off the vendor gold
    /// field's own drawn text. Nil when the player info card is not on its
    /// `Barter` frame, which is what a container-mode movie looks like — the
    /// field is placed by that frame and does not exist before it.
    static func vendorGoldText(runtime: SWFMovieRuntime) -> String? {
        guard let field = runtime.node(atPath: vendorGoldFieldPath, from: runtime.root) else {
            return nil
        }
        return runtime.text(of: field)
    }

    // MARK: - Outbound calls

    /// Maps one outbound call onto an engine action.
    ///
    /// The row index is the first numeric argument, as it is for
    /// `inventorymenu.swf`. A call carrying none acts on the selected row, which
    /// index 0 stands for only because the caller re-selects before acting.
    static func action(named name: String, arguments: [AS2Value]) -> ContainerMenuAction {
        let index = arguments.lazy.compactMap { value -> Int? in
            guard case let .number(number) = value, number.isFinite, number >= 0 else {
                return nil
            }
            return Int(number)
        }.first ?? 0
        switch name {
        case "ItemTransfer", "ItemSelect": return .transfer(index: index)
        case "TakeAllItems": return .takeAll
        case "EquipItem": return .equip(index: index)
        default: return .close
        }
    }

    // MARK: - Input

    /// Routes an engine menu event into the Flash key model so the movie's own
    /// CLIK focus path moves the selection.
    @discardableResult
    static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = InventoryMenuMovieBridge.key(for: event) else {
            return false
        }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    /// Delivers one menu event through the renderer, which resynchronizes the
    /// drawn command stream with whatever the movie changed. Routing a live
    /// movie's input any other way repaints late; see #300.
    @MainActor
    @discardableResult
    static func send(_ event: MenuInputEvent, renderer: Renderer) throws -> Bool {
        try InventoryMenuMovieBridge.send(event, renderer: renderer)
    }
}
