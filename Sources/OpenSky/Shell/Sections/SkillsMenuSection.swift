// World > Character > Skills Menu: open the level-up and skills menu, step it,
// and switch between the game's movies and OpenSky's rows.

import AppKit
import OpenSkyMenus

final class SkillsMenuSection: MenuButtonSection {
    weak var provider: (any SkillsMenuControlProviding)?

    init() {
        super.init(statsIdentifier: "SkillsMenuStatsLabel")
    }

    override var sectionTitle: String {
        "Skills Menu"
    }

    override var sectionIdentifier: String {
        "skillsMenu"
    }

    override var isOverridden: Bool {
        provider?.skillsMenuSnapshot.isOpen == true
    }

    override func makeActions() -> [[Action]] {
        [
            [
                Action(
                    title: "Open", identifier: "SkillsMenuOpenControl",
                    toolTip: "Open the skills menu, as the Quick Stats key does."
                ) { [weak self] in self?.provider?.openSkillsMenu() },
                Action(
                    title: "Movie", identifier: "SkillsMenuMovieControl",
                    toolTip: "Switch between the game's menu movies and OpenSky's rows."
                ) { [weak self] in
                    guard let provider = self?.provider else { return }
                    provider.setSkillsMenuMovieEnabled(!provider.skillsMenuSnapshot.movie.isEnabled)
                }
            ],
            [
                send("Up", "SkillsMenuUpControl", .move(.up)),
                send("Down", "SkillsMenuDownControl", .move(.down)),
                send("Left", "SkillsMenuLeftControl", .move(.left)),
                send("Right", "SkillsMenuRightControl", .move(.right))
            ],
            [
                send("Accept", "SkillsMenuAcceptControl", .button(.accept)),
                send("Legendary", "SkillsMenuLegendaryControl", .button(.yButton)),
                send("Back", "SkillsMenuBackControl", .button(.cancel))
            ]
        ]
    }

    private func send(_ title: String, _ id: String, _ event: MenuInputEvent) -> Action {
        let tip = "Send \(title) to the skills menu."
        return Action(title: title, identifier: id, toolTip: tip) { [weak self] in
            self?.provider?.sendSkillsMenuInput(event)
        }
    }

    override func isEnabled(_ identifier: String) -> Bool {
        let isOpen = provider?.skillsMenuSnapshot.isOpen == true
        switch identifier {
        case "SkillsMenuMovieControl": return provider != nil
        case "SkillsMenuOpenControl": return provider != nil && !isOpen
        default: return isOpen
        }
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.skillsMenuSnapshot else { return "Skills menu: unavailable" }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: SkillsMenuSnapshot) -> String {
        let result = "\n" + TitleMenuSection.movieLine(snapshot.movie)
            + (snapshot.lastResult.map { "\nLast result: \($0)" } ?? "")
        guard snapshot.isOpen else { return "Skills menu: closed\(result)" }
        return "Skills menu: \(snapshot.page)\n"
            + list(snapshot.rows, selected: snapshot.selectedIndex ?? -1) + result
    }
}
