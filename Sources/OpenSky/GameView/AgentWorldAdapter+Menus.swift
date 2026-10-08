// The open menu as rows an agent can read and select by label. Selection moves
// through the same menu input path as the arrow keys.

import AppKit
import OpenSkyAgentControl
import OpenSkyMenus

struct AgentMenuRows: Equatable {
    let menu: String
    let rows: [String]
    let selected: Int
}

extension AgentWorldAdapter {
    /// Nil when no menu is open or the top menu has no row list.
    func menuRows() -> AgentMenuRows? {
        guard let top = game.menuMode.topMenu else { return nil }
        switch top {
        case InventoryMenuController.identifier:
            let snapshot = game.inventoryMenuSnapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.entryLines,
                selected: snapshot.selectedIndex
            )
        case ContainerMenuController.containerIdentifier, ContainerMenuController.barterIdentifier:
            let snapshot = game.containerMenuSnapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.entryLines,
                selected: snapshot.selectedIndex
            )
        case JournalMenuController.identifier:
            let snapshot = game.journalMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows.map(\.title),
                selected: snapshot.selectedIndex
            )
        case DialogueMenuController.identifier:
            let snapshot = game.dialogueMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows.map(\.text),
                selected: snapshot.selectedIndex
            )
        case TitleMenuCoordinator.identifier:
            let snapshot = game.titleMenu.snapshot
            guard snapshot.movie.isLoaded, !snapshot.isLoadPageOpen else {
                return AgentMenuRows(
                    menu: top.name, rows: snapshot.rows, selected: snapshot.selectedIndex
                )
            }
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.movie.rows,
                selected: snapshot.movie.selectedIndex ?? -1
            )
        case RaceMenuCoordinator.identifier:
            let snapshot = game.raceMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows,
                selected: snapshot.selectedIndex
            )
        default:
            return nil
        }
    }

    var menuState: AgentJSON {
        var result: [String: AgentJSON] = [
            "open": .array(game.menuMode.stack.identifiers.map { .string($0.name) }),
            "top": .init(game.menuMode.topMenu?.name),
            "worldPaused": .bool(game.menuMode.isWorldSimPaused)
        ]
        if let rows = menuRows() {
            result["rows"] = .array(rows.rows.map { .string($0) })
            result["selected"] = .init(rows.selected)
        }
        return .object(result)
    }

    func selectMenuRow(label: String) throws(AgentFailure) -> AgentJSON {
        guard let start = menuRows() else {
            throw AgentFailure(.notFound, "no open menu has a row list")
        }
        guard let target = Self.rowIndex(of: label, in: start.rows) else {
            throw AgentFailure(.notFound, "no row '\(label)' in \(start.menu)")
        }
        var current = start.selected
        while current != target {
            let action: GameInputAction = target > current ? .menuDown : .menuUp
            dispatcher.apply(action, .press)
            dispatcher.apply(action, .release)
            guard let next = menuRows()?.selected, next != current else { break }
            current = next
        }
        guard current == target else {
            throw AgentFailure(.failed, "the selection stopped at row \(current), not \(target)")
        }
        return [
            "menu": .string(start.menu),
            "index": .init(target),
            "label": .string(start.rows[target])
        ]
    }

    /// The same pointer events the view sends for a real cursor.
    func pointMenu(x: Float, y: Float, click: Bool) throws(AgentFailure) -> AgentJSON {
        guard game.menuMode.isMenuMode else {
            throw AgentFailure(.invalidArgument, "no menu is open")
        }
        let bounds = game.view.bounds
        let size = SIMD2(Float(bounds.width), Float(bounds.height))
        let location = SIMD2(x, y) * size
        let phases: [MenuPointerEvent.Phase] = click ? [.moved, .pressed, .released] : [.moved]
        for phase in phases {
            game.menuMode.routeMenuPointer(MenuPointerEvent(
                phase,
                location: location,
                viewSize: size
            ))
        }
        return ["x": .init(x), "y": .init(y), "clicked": .bool(click)]
    }

    func typeText(_ text: String) throws(AgentFailure) -> AgentJSON {
        guard game.raceMenu.type(text) else {
            throw AgentFailure(.notFound, "no open menu takes text now")
        }
        return ["typed": .string(text)]
    }

    /// An exact match wins, then a row that starts with the label, then one that
    /// contains it. Case is ignored.
    static func rowIndex(of label: String, in rows: [String]) -> Int? {
        let wanted = label.lowercased()
        let lowered = rows.map { $0.lowercased() }
        return lowered.firstIndex(of: wanted)
            ?? lowered.firstIndex { $0.hasPrefix(wanted) }
            ?? lowered.firstIndex { $0.contains(wanted) }
    }
}
