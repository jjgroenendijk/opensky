// The Gameplay group: whether a new game uses Survival Mode, or lets the plugin's own
// prompt ask. The prompt stops a new game, so it is off unless the player asks for it.

import AppKit
import OpenSkyGameData

extension SettingsViewController {
    /// In menu order; the setting values are `survivalModeAsk` and `survivalMode`.
    static let survivalModeTitles = ["Off", "On", "Ask in a new game"]

    func makeGameplayGroup() -> NSView {
        survivalModePopUp.addItems(withTitles: Self.survivalModeTitles)
        PanelComponents.configurePopUp(
            survivalModePopUp, target: self, action: #selector(survivalModeChanged),
            identifier: "SettingsSurvivalModeControl"
        )
        survivalModePopUp.toolTip = "Hunger, fatigue, and cold in a new game"
        return layout.group("Gameplay", [layout.row("Survival Mode", survivalModePopUp)])
    }

    func refreshGameplay() {
        let store = playerSettings()
        let index = store.bool(.survivalModeAsk) ? 2 : store.bool(.survivalMode) ? 1 : 0
        survivalModePopUp.selectItem(at: index)
    }

    @objc func survivalModeChanged() {
        let store = playerSettings()
        let index = survivalModePopUp.indexOfSelectedItem
        store.set(.survivalModeAsk, to: index == 2 ? 1 : 0)
        store.set(.survivalMode, to: index == 1 ? 1 : 0)
    }
}
