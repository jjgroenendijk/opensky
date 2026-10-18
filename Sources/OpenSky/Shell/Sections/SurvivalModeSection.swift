// World > Settings > Survival Mode: the answer to the plugin's prompt and the
// plugin's own state.

import AppKit
import OpenSkyMenus

final class SurvivalModeSection: MenuButtonSection {
    weak var provider: (any SurvivalModeControlProviding)?

    init() {
        super.init(statsIdentifier: "SurvivalModeStatsLabel")
    }

    override var sectionTitle: String {
        "Survival Mode"
    }

    override var sectionIdentifier: String {
        "survivalMode"
    }

    override func makeActions() -> [[Action]] {
        [[
            Action(
                title: "On", identifier: "SurvivalModeOnControl",
                toolTip: "Turn Survival Mode on; a new game does not ask."
            ) { [weak self] in self?.choose(on: true) },
            Action(
                title: "Off", identifier: "SurvivalModeOffControl",
                toolTip: "Turn Survival Mode off; a new game does not ask."
            ) { [weak self] in self?.choose(on: false) },
            Action(
                title: "Ask", identifier: "SurvivalModeAskControl",
                toolTip: "Let a new game ask, as the plugin does."
            ) { [weak self] in self?.provider?.setSurvivalModeAsk(true) }
        ]]
    }

    private func choose(on: Bool) {
        provider?.setSurvivalModeAsk(false)
        provider?.setSurvivalMode(on)
    }

    override func isEnabled(_ identifier: String) -> Bool {
        provider != nil
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.survivalModeSnapshot else {
            return "Survival Mode: unavailable"
        }
        return snapshot.lines.joined(separator: "\n")
    }
}
