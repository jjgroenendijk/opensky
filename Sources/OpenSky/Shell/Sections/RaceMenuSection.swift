// World > Character > Race Menu: open the full or limited race menu, step its
// rows, set the name, and switch between the game's movie and OpenSky's rows.

import AppKit
import OpenSkyMenus

final class RaceMenuSection: MenuButtonSection {
    weak var provider: (any RaceMenuControlProviding)?
    let nameControl = NSTextField(string: "")

    init() {
        super.init(statsIdentifier: "RaceMenuStatsLabel")
    }

    override var sectionTitle: String {
        "Race Menu"
    }

    override var sectionIdentifier: String {
        "raceMenu"
    }

    override var isOverridden: Bool {
        provider?.raceMenuSnapshot.isOpen == true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            nameControl, identifier: "RaceMenuNameControl", width: 180, placeholder: "Name"
        )
        // Return sets the name, as the race menu's own name entry does.
        nameControl.target = self
        nameControl.action = #selector(nameChanged)
        nameControl.toolTip = "Type a name and press Return."
        return super.makeContentViews() + [nameControl]
    }

    override func makeActions() -> [[Action]] {
        [
            [
                Action(
                    title: "Open", identifier: "RaceMenuOpenControl",
                    toolTip: "Open the full race menu."
                ) { [weak self] in self?.provider?.openRaceMenu(limited: false) },
                Action(
                    title: "Open Limited", identifier: "RaceMenuOpenLimitedControl",
                    toolTip: "Open the race menu as ShowLimitedRaceMenu does."
                ) { [weak self] in self?.provider?.openRaceMenu(limited: true) },
                Action(
                    title: "Reset", identifier: "RaceMenuResetControl",
                    toolTip: "Put the player back to the vanilla Player record."
                ) { [weak self] in self?.provider?.resetPlayerIdentity() }
            ],
            [
                Action(
                    title: "Previous Preset", identifier: "RaceMenuPreviousPresetControl",
                    toolTip: "Give the player the previous preset face of their race."
                ) { [weak self] in self?.provider?.applyRacePreset(offset: -1) },
                Action(
                    title: "Next Preset", identifier: "RaceMenuNextPresetControl",
                    toolTip: "Give the player the next preset face of their race."
                ) { [weak self] in self?.provider?.applyRacePreset(offset: 1) },
                Action(
                    title: "Movie", identifier: "RaceMenuMovieControl",
                    toolTip: "Switch between the game's race menu movie and OpenSky's rows."
                ) { [weak self] in
                    guard let provider = self?.provider else { return }
                    provider.setRaceMenuMovieEnabled(!provider.raceMenuSnapshot.movie.isEnabled)
                }
            ],
            [
                send("Up", "RaceMenuUpControl", .move(.up)),
                send("Down", "RaceMenuDownControl", .move(.down)),
                send("Left", "RaceMenuLeftControl", .move(.left)),
                send("Right", "RaceMenuRightControl", .move(.right)),
                send("Done", "RaceMenuDoneControl", .button(.cancel))
            ]
        ]
    }

    private func send(_ title: String, _ id: String, _ event: MenuInputEvent) -> Action {
        let tip = "Send \(title) to the race menu."
        return Action(title: title, identifier: id, toolTip: tip) { [weak self] in
            self?.provider?.sendRaceMenuInput(event)
        }
    }

    override func isEnabled(_ identifier: String) -> Bool {
        if identifier == "RaceMenuMovieControl" {
            return provider != nil
        }
        let isOpen = provider?.raceMenuSnapshot.isOpen == true
        let needsClosed = identifier.hasPrefix("RaceMenuOpen")
            || identifier == "RaceMenuResetControl" || identifier.hasSuffix("PresetControl")
        return needsClosed ? provider != nil && !isOpen : isOpen
    }

    override func refreshReadout() {
        super.refreshReadout()
        nameControl.isEnabled = provider?.raceMenuSnapshot.isOpen == true
    }

    @objc private func nameChanged() {
        provider?.setRaceMenuName(nameControl.stringValue)
        finishInteraction()
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.raceMenuSnapshot else { return "Race menu: unavailable" }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: RaceMenuSnapshot) -> String {
        let result = "\n" + TitleMenuSection.movieLine(snapshot.movie)
            + (snapshot.lastResult.map { "\nLast character: \($0)" } ?? "")
            + (snapshot.face.isEmpty ? "" : "\n" + snapshot.face.joined(separator: "\n"))
        guard snapshot.isOpen else { return "Race menu: closed\(result)" }
        let kind = (snapshot.isLimited ? "limited" : "full")
            + (snapshot.isEditingName ? ", typing a name" : "")
        return "Race menu: open, \(kind)\n" + list(snapshot.rows, selected: snapshot.selectedIndex)
            + result
    }
}
