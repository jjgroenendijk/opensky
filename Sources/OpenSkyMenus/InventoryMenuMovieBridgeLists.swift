// `EntriesA` and `iSelectedIndex` plumbing for InventoryMenuMovieBridge.swift.
// A missing list, row, or index answers nil or does nothing, never throws.

import Foundation
import OpenSkyFormatsSWF

nonisolated extension InventoryMenuMovieBridge {
    // MARK: - Writing

    /// Replaces one list's `EntriesA` with `rows`. The selection is written
    /// later by `select`, because `InvalidateListData` resets it to -1.
    public static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        MenuMovieEntryList.publish(rows, atPath: path, runtime: runtime)
    }

    /// Points one list at `index`, after the rebuild. An empty list keeps the
    /// movie's own -1 rather than pointing at a row that is not there.
    public static func select(
        _ index: Int,
        count: Int,
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else {
            return
        }
        let clamped = count > 0 ? min(max(index, 0), count - 1) : -1
        list.object.assign(.integer(clamped), for: selectedIndexName)
    }

    /// Publishes the two totals the vanilla menu keeps on screen.
    ///
    /// `PlayerGoldValue` and `CarryWeightValue` are `TextField` instances on
    /// the player info card, not properties on the bottom bar, so they are
    /// filled with the GFx `SetText` extension rather than assigned. A field
    /// the movie has not built is skipped rather than synthesized.
    public static func publishTotals(_ model: InventoryMenuModel, runtime: SWFMovieRuntime) {
        setText("\(model.gold)", atPath: goldFieldPath, runtime: runtime)
        setText(
            String(format: "%.0f", model.carriedWeight),
            atPath: carryWeightFieldPath,
            runtime: runtime
        )
    }

    private static func setText(_ text: String, atPath path: String, runtime: SWFMovieRuntime) {
        guard runtime.node(atPath: path, from: runtime.root) != nil else {
            return
        }
        runtime.callMovie("SetText", atPath: path, arguments: [.string(text)])
    }

    /// Rebuilds both lists' rows from the `EntriesA` arrays just written.
    ///
    /// `InvalidateListData` is a `GameDelegate` callback the movie registers
    /// for itself, so it is invoked by name through the delegate rather than as
    /// a function on a display instance — calling it `atPath:` finds nothing
    /// and lands in the unhandled-invoke count.
    public static func invalidate(runtime: SWFMovieRuntime) {
        runtime.callMovie(invalidateCallback)
    }

    // MARK: - Reading

    /// Row `text` values of one list in numeric row order.
    public static func entryLabels(runtime: SWFMovieRuntime, atPath path: String) -> [String] {
        MenuMovieEntryList.labels(atPath: path, runtime: runtime)
    }

    public static func selectedIndex(runtime: SWFMovieRuntime, atPath path: String) -> Int? {
        guard
            let list = runtime.node(atPath: path, from: runtime.root),
            case let .number(index) = list.object.lookup(selectedIndexName)?.property.value,
            index.isFinite, index >= 0
        else {
            return nil
        }
        return Int(index)
    }

    // MARK: - Outbound calls

    /// Maps one outbound `GameDelegate` call onto an engine action.
    ///
    /// The movie passes the row index as its first ordinary argument. A call
    /// that carries none acts on whatever is selected, which is index 0's
    /// meaning here only because the caller re-selects before acting.
    public static func action(named name: String, arguments: [AS2Value]) -> InventoryMenuAction {
        let index = arguments.lazy.compactMap { value -> Int? in
            guard case let .number(number) = value, number.isFinite, number >= 0 else {
                return nil
            }
            return Int(number)
        }.first ?? 0
        switch name {
        case "ItemSelect": return .equip(index: index)
        case "DropItem": return .drop(index: index)
        default: return .close
        }
    }

    /// Left and right switch category in a vanilla inventory, so they are
    /// navigation rather than unmapped.
    public static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        event.swfKey
    }
}
