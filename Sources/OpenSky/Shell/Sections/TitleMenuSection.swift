// World > Character > Title Menu: open the title menu and step its rows.

import AppKit
import OpenSkyMenus

final class TitleMenuSection: MenuButtonSection {
    weak var provider: (any TitleMenuControlProviding)?
    let cellControl = NSTextField(string: "")

    init() {
        super.init(statsIdentifier: "TitleMenuStatsLabel")
    }

    override var sectionTitle: String {
        "Title Menu"
    }

    override var sectionIdentifier: String {
        "titleMenu"
    }

    override var isOverridden: Bool {
        provider?.titleMenuSnapshot.isOpen == true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            cellControl, identifier: "TitleMenuNewGameCellControl", width: 180,
            placeholder: "Cell editor ID"
        )
        cellControl.toolTip = "Cell for New Game Here. Empty starts at the vanilla opening."
        return super.makeContentViews() + [cellControl]
    }

    override func makeActions() -> [[Action]] {
        let rows = [
            Action(
                title: "Open", identifier: "TitleMenuOpenControl",
                toolTip: "Show the title menu over a paused world."
            ) { [weak self] in self?.provider?.openTitleMenu() },
            send("Up", "TitleMenuUpControl", .move(.up)),
            send("Down", "TitleMenuDownControl", .move(.down)),
            send("Choose", "TitleMenuChooseControl", .button(.accept))
        ]
        let movie = Action(
            title: "Movie", identifier: "TitleMenuMovieControl",
            toolTip: "Switch between the game's main menu movie and OpenSky's rows."
        ) { [weak self] in
            guard let provider = self?.provider else { return }
            provider.setTitleMenuMovieEnabled(!provider.titleMenuSnapshot.movie.isEnabled)
        }
        let newGame = Action(
            title: "New Game Here", identifier: "TitleMenuNewGameHereControl",
            toolTip: "Start a new game in the cell typed below."
        ) { [weak self] in
            guard let self else { return }
            provider?.startNewGame(atCell: cellControl.stringValue)
        }
        return [rows, [movie, newGame]]
    }

    private func send(_ title: String, _ id: String, _ event: MenuInputEvent) -> Action {
        let tip = "Send \(title) to the title menu."
        return Action(title: title, identifier: id, toolTip: tip) { [weak self] in
            self?.provider?.sendTitleMenuInput(event)
        }
    }

    override func isEnabled(_ identifier: String) -> Bool {
        let isOpen = provider?.titleMenuSnapshot.isOpen == true
        switch identifier {
        case "TitleMenuOpenControl": return provider != nil && !isOpen
        case "TitleMenuMovieControl", "TitleMenuNewGameHereControl": return provider != nil
        default: return isOpen
        }
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.titleMenuSnapshot else { return "Title menu: unavailable" }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: TitleMenuSnapshot) -> String {
        let result = snapshot.lastResult.map { "\nLast result: \($0)" } ?? ""
        let movie = "\n" + movieLine(snapshot.movie)
        guard snapshot.isOpen else { return "Title menu: closed\(movie)\(result)" }
        let page = snapshot.isLoadPageOpen ? "Load" : "Main"
        return "Title menu: open, \(page) page\n"
            + list(snapshot.rows, selected: snapshot.selectedIndex) + movie + result
    }

    nonisolated static func movieLine(_ movie: TitleMenuMovieSnapshot) -> String {
        guard movie.isEnabled else { return "Movie: off" }
        if let error = movie.error {
            return "Movie: on, \(error)"
        }
        guard movie.isLoaded else { return "Movie: on" }
        let rows = movie.rows.joined(separator: " ")
        return "Movie: \(movie.state ?? "no state"), rows \(rows)"
    }
}
