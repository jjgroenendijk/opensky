// The open menu as rows an agent can read and select by label. Selection moves
// through the same menu input path as the arrow keys.

import AppKit
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyRendering

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
            let snapshot = game.inventoryMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.entryLines,
                selected: snapshot.selectedIndex
            )
        case ContainerMenuController.containerIdentifier, ContainerMenuController.barterIdentifier:
            let snapshot = game.containerMenu.snapshot
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
            return titleMenuRows(top)
        case SystemMenuCoordinator.identifier:
            let menu = game.systemMenu
            let page = menu.movieMainPage ?? menu.snapshot.page
            return AgentMenuRows(menu: top.name, rows: page.rows, selected: page.selectedIndex)
        case RaceMenuCoordinator.identifier:
            let snapshot = game.raceMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows,
                selected: snapshot.selectedIndex
            )
        case SkillsMenuCoordinator.identifier:
            let snapshot = game.skillsMenu.snapshot
            return AgentMenuRows(
                menu: top.name,
                rows: snapshot.rows,
                selected: snapshot.selectedIndex ?? -1
            )
        case MessageCoordinator.identifier:
            guard let box = game.messages.presentation else { return nil }
            return AgentMenuRows(
                menu: top.name,
                rows: box.request.buttons.map(\.text),
                selected: box.selection
            )
        default:
            return nil
        }
    }

    private func titleMenuRows(_ top: MenuIdentifier) -> AgentMenuRows {
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
    }

    var menuState: AgentJSON {
        var result: [String: AgentJSON] = [
            "open": .array(game.menuMode.stack.identifiers.map { .string($0.name) }),
            "top": .init(game.menuMode.topMenu?.name),
            "worldPaused": .bool(game.menuMode.isWorldSimPaused),
            "hud": hudState,
            "loading": loadingState,
            "movie": movieFocusState,
            "bink": binkState,
            "titles": titlesState
        ]
        if let rows = menuRows() {
            result["rows"] = .array(rows.rows.map { .string($0) })
            result["selected"] = .init(rows.selected)
        }
        if game.menuMode.topMenu == SkillsMenuCoordinator.identifier {
            result["skills"] = skillsMenuState(game.skillsMenu.snapshot)
        }
        if game.systemMenu.isOpen {
            result["systemPage"] = .string(game.systemMenu.model.page.rawValue)
            result["topic"] = .init(game.systemMenu.topicPage?.openTopic?.title)
            if let movie = game.systemMenu.movieDiagnostics {
                result["systemMovie"] = [
                    "state": movie.state.map { .init($0) } ?? .null, "faults": .init(movie.faults),
                    "missing": .array(movie.missingNames.map { .string($0) })
                ]
            }
        }
        if game.titleMenu.isOpen {
            result["credits"] = .bool(game.titleMenu.creditsShown)
        }
        return .object(result)
    }

    /// The opening titles: shown, loaded, and the clip asked for last.
    var titlesState: AgentJSON {
        let titles = game.titleSequence
        return [
            "shown": .bool(titles.isShown), "loaded": .bool(titles.isLoaded),
            "sequence": .init(titles.lastSequence)
        ]
    }

    /// The Bink movie on screen, and how the last one ended.
    var binkState: AgentJSON {
        let readout = game.movies.readout
        let outcome: AgentJSON = switch readout.lastOutcome {
        case .finished: "finished"
        case .skipped: "skipped"
        case let .failed(reason): .string("failed: \(reason)")
        case nil: .null
        }
        let frame: AgentJSON = readout.frame.map { AgentJSON($0) } ?? .null
        let frameCount: AgentJSON = readout.frameCount.map { AgentJSON($0) } ?? .null
        return .object([
            "file": AgentJSON(readout.fileName), "loading": .bool(readout.loading),
            "frame": frame, "frameCount": frameCount,
            "interruptible": .bool(readout.interruptible), "lastOutcome": outcome
        ])
    }

    /// The menu movie's focused clip, its frame label, controllers, and button-art platform.
    var movieFocusState: AgentJSON {
        guard let runtime = game.renderer?.swfRuntime else { return .null }
        let focus = runtime.focusTarget
        return [
            "focus": .init(focus?.targetPath),
            "focusLabel": .init(focus.flatMap(runtime.currentFrameLabel(of:))),
            "controllers": .init(runtime.controllerCount),
            "platform": .number(runtime.inputPlatform)
        ]
    }

    /// `debug gamepad`: the reported gamepads change at once; presses arrive next frame.
    func driveGamepad(count: Int?, press: [String]) throws(AgentFailure) -> AgentJSON {
        let gamepads = game.menuRouter.gamepads
        var buttons: Set<GamepadButton> = []
        for name in press {
            guard let button = Self.gamepadButtons[name] else {
                throw AgentFailure(.invalidArgument, "unknown gamepad button: \(name)")
            }
            buttons.insert(button)
        }
        if let count {
            gamepads.simulatedCount = count
        }
        gamepads.simulatedPress.formUnion(buttons)
        return ["simulated": .init(gamepads.simulatedCount), "pressed": .init(buttons.count)]
    }

    private static let gamepadButtons: [String: GamepadButton] = [
        "a": .a, "b": .b, "x": .x, "y": .y,
        "up": .dpadUp, "down": .dpadDown, "left": .dpadLeft, "right": .dpadRight
    ]

    /// The loading screen: whether it covers, which screen, and its movie.
    var loadingState: AgentJSON {
        let loading = game.loadingScreens
        let session = loading.session
        return [
            "covering": .bool(loading.isCovering),
            "waiting": .bool(loading.isWaitingForDestination),
            "screen": .init(session?.screen?.record.editorID),
            "cameraPath": .init(session?.screen?.record.cameraPath),
            "turn": .number(Double(session?.turnDegrees ?? 0)),
            "movieLoaded": .bool(game.loadingWorld.isMovieLoaded),
            "shown": .init(loading.shownCount)
        ]
    }

    var hudState: AgentJSON {
        [
            "loaded": .bool(game.hud.isLoaded), "cartMode": .bool(game.hud.isCartMode),
            "modes": .array(game.hud.shownModes.map { .string($0.rawValue) }),
            "notifications": .array(game.hud.shownNotifications.map { .string($0) }),
            "bigNotices": .array(game.hud.shownBigNotices.map { notice in
                .string("\(notice.title) | \(notice.status)")
            })
        ]
    }

    /// The page, the movies, and the perk sky line, such as "812 draws, turned 40°, ring".
    func skillsMenuState(_ snapshot: SkillsMenuSnapshot) -> AgentJSON {
        [
            "page": .string(snapshot.page),
            "movie": .init(snapshot.movie.state),
            "levelUpMovie": .bool(snapshot.isLevelUpMovieLoaded),
            "skyEnabled": .bool(snapshot.isSkyEnabled),
            "sky": .init(snapshot.sky)
        ]
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
        let bounds = game.hostView.bounds
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
