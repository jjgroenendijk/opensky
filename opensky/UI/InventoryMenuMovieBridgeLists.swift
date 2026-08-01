// List plumbing for the inventory menu bridge (M12.2.2, issue #289). Satellite
// of UI/InventoryMenuMovieBridge.swift, which holds the measured contract; this
// file holds the AS2 object work that reads and writes `EntriesA` and
// `iSelectedIndex` through it.
//
// Everything here degrades: a list the movie has not built, a row that is not
// an object, a selection index that is not a number — each answers nil or does
// nothing rather than throwing. A vanilla movie whose shape moved must leave a
// tally entry and an empty readout, never take the app down.

import Foundation

extension InventoryMenuMovieBridge {
    // MARK: - Writing

    /// Replaces one list's `EntriesA` with `rows`.
    ///
    /// The selection is *not* written here. `InvalidateListData` rebuilds the
    /// list from the new data and resets `iSelectedIndex` to its own
    /// nothing-selected sentinel of -1 as it goes, so a selection written
    /// before the rebuild is discarded — measured, not assumed. `select` runs
    /// afterwards instead.
    static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else {
            return
        }
        let entries = runtime.runtime.makeArray(
            rows.map { .object(makeRow($0, runtime: runtime)) }
        )
        list.object.assign(.object(entries), for: entryArrayName)
    }

    /// Points one list at `index`, after the rebuild. An empty list keeps the
    /// movie's own -1 rather than pointing at a row that is not there.
    static func select(_ index: Int, count: Int, atPath path: String, runtime: SWFMovieRuntime) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else {
            return
        }
        let clamped = count > 0 ? min(max(index, 0), count - 1) : -1
        list.object.assign(.integer(clamped), for: selectedIndexName)
    }

    /// One plain AS2 object per row. Field order follows the dictionary's own
    /// sorted keys so two publishes of equal rows build identical objects,
    /// which is what makes a published list comparable in a test.
    private static func makeRow(
        _ fields: [String: AS2Value],
        runtime: SWFMovieRuntime
    ) -> AS2Object {
        let row = runtime.runtime.makeObject()
        for name in fields.keys.sorted() {
            row.assign(fields[name] ?? .undefined, for: name)
        }
        return row
    }

    /// Publishes the two totals the vanilla menu keeps on screen.
    ///
    /// `PlayerGoldValue` and `CarryWeightValue` are `TextField` instances on
    /// the player info card, not properties on the bottom bar, so they are
    /// filled with the GFx `SetText` extension rather than assigned. A field
    /// the movie has not built is skipped rather than synthesized.
    static func publishTotals(_ model: InventoryMenuModel, runtime: SWFMovieRuntime) {
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
    static func invalidate(runtime: SWFMovieRuntime) {
        runtime.callMovie(invalidateCallback)
    }

    // MARK: - Reading

    /// Row `text` values in numeric row order.
    ///
    /// `EntriesA` is an AS2 array, so its rows are numeric property names and
    /// have to be sorted numerically — lexical order puts row 10 before row 2.
    static func entryLabels(runtime: SWFMovieRuntime, atPath path: String) -> [String] {
        guard
            let list = runtime.node(atPath: path, from: runtime.root),
            let entries = list.object.lookup(entryArrayName)?.property.value.objectValue
        else {
            return []
        }
        return entries.ownPropertyNames
            .compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    static func selectedIndex(runtime: SWFMovieRuntime, atPath path: String) -> Int? {
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
    static func action(named name: String, arguments: [AS2Value]) -> InventoryMenuAction {
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

    /// Key equivalents for the four navigation directions plus accept and
    /// cancel. Left and right switch category in a vanilla inventory, which is
    /// why they are navigation rather than unmapped.
    static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        switch event {
        case .move(.up): (SWFKeyCode.up, 0)
        case .move(.down): (SWFKeyCode.down, 0)
        case .move(.left): (SWFKeyCode.left, 0)
        case .move(.right): (SWFKeyCode.right, 0)
        case .button(.accept): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.escape, 0)
        case .pointer: nil
        }
    }
}
