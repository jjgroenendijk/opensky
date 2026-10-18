// The Launch page's New game group: the Survival Mode answer, so the plugin's
// prompt does not stop a new game unless the player asks for it.

import AppKit
import OpenSkyGameData

extension LaunchPageViewController {
    func makeNewGameGroup() -> NSView {
        PanelComponents.configureCheckbox(
            survivalModeControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeControl"
        )
        survivalModeControl.toolTip = "Hunger, fatigue, and cold; change it later in Gameplay"
        PanelComponents.configureCheckbox(
            survivalModeAskControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeAskControl"
        )
        survivalModeAskControl.toolTip = "Show the game's Survival Mode question in a new game"
        refreshNewGame()
        return layout.group("New game", [
            layout.toggle(survivalModeControl), layout.toggle(survivalModeAskControl)
        ])
    }

    func refreshNewGame() {
        let store = context.playerSettings()
        let ask = store.bool(.survivalModeAsk)
        survivalModeAskControl.state = ask ? .on : .off
        survivalModeControl.state = store.bool(.survivalMode) ? .on : .off
        survivalModeControl.isEnabled = !ask
    }

    @objc private func survivalModeChanged() {
        let store = context.playerSettings()
        store.set(.survivalModeAsk, to: survivalModeAskControl.state == .on ? 1 : 0)
        store.set(.survivalMode, to: survivalModeControl.state == .on ? 1 : 0)
        refreshNewGame()
    }
}
